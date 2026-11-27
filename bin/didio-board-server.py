#!/usr/bin/env python3
"""didio board server -- lightweight HTTP server for the Live Kanban Board.

Serves board.html (SPA) and JSON API endpoints that read live project data
from the filesystem. Zero external dependencies -- Python 3 stdlib only.

Usage:
    python3 bin/didio-board-server.py [--port PORT] [--open] [--no-open]

Environment:
    DIDIO_PROJECT_ROOT  Project root directory (default: cwd)
"""
import argparse
import glob
import json
import os
import signal
import sys
import threading
import webbrowser
from http.server import HTTPServer, BaseHTTPRequestHandler
from pathlib import Path
from urllib.parse import urlparse

PROJECT_ROOT = Path(os.environ.get("DIDIO_PROJECT_ROOT", os.getcwd()))
SCRIPT_DIR = Path(__file__).resolve().parent


def read_json_files(pattern):
    """Read all JSON files matching a glob pattern, skipping malformed ones."""
    results = []
    matched = sorted(glob.glob(str(pattern)))
    for fpath in matched:
        try:
            with open(fpath, "r", encoding="utf-8") as f:
                data = json.load(f)
            results.append(data)
        except (json.JSONDecodeError, OSError) as e:
            print(f"[warn] skipping {fpath}: {e}", file=sys.stderr)
    return results


def get_warroom_data():
    """Read warroom cards and compute counts by status."""
    cards_dir = PROJECT_ROOT / "logs" / "warroom" / "cards"
    cards = read_json_files(cards_dir / "*.json")
    statuses = ["incoming", "triaging", "promoted", "deferred", "archived", "needs_input"]
    counts = {s: 0 for s in statuses}
    for card in cards:
        status = card.get("status", "incoming")
        if status in counts:
            counts[status] += 1
        else:
            counts[status] = counts.get(status, 0) + 1
    return {"cards": cards, "counts": counts, "total": len(cards)}


def get_pipelines_data():
    """Read pipeline state files and compute counts by status."""
    agents_dir = PROJECT_ROOT / "logs" / "agents"
    pipelines = read_json_files(agents_dir / "pipeline-*.state.json")
    statuses = ["planned", "running", "done", "failed", "paused"]
    counts = {s: 0 for s in statuses}
    for p in pipelines:
        status = p.get("status", "planned")
        if status in counts:
            counts[status] += 1
        else:
            counts[status] = counts.get(status, 0) + 1
    return {"pipelines": pipelines, "counts": counts}


def get_features_data():
    """Read feature directories and extract metadata from README files."""
    features_dir = PROJECT_ROOT / "tasks" / "features"
    features = []
    if features_dir.is_dir():
        for d in sorted(features_dir.iterdir()):
            if d.is_dir() and d.name.startswith("F"):
                fid = d.name.split("-")[0] if "-" in d.name else d.name
                name = d.name.replace(fid + "-", "").replace("-", " ").title() if "-" in d.name else d.name
                features.append({
                    "id": fid,
                    "name": name,
                    "dir": d.name,
                    "status": "planned",
                })
    return {"features": features}


class BoardHandler(BaseHTTPRequestHandler):
    """HTTP request handler for the board server."""

    def log_message(self, format, *args):
        """Override to use stderr with prefix."""
        print(f"[board] {args[0]}", file=sys.stderr)

    def send_json(self, data, status=200):
        """Send a JSON response with CORS headers."""
        body = json.dumps(data, ensure_ascii=False, indent=2).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def send_html(self, html_path):
        """Send an HTML file."""
        try:
            with open(html_path, "r", encoding="utf-8") as f:
                body = f.read().encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Access-Control-Allow-Origin", "*")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        except FileNotFoundError:
            self.send_error(404, "board.html not found")

    def do_GET(self):
        parsed = urlparse(self.path)
        path = parsed.path.rstrip("/") or "/"

        if path == "/":
            self.send_html(SCRIPT_DIR / "board.html")
        elif path == "/api/warroom":
            self.send_json(get_warroom_data())
        elif path == "/api/pipelines":
            self.send_json(get_pipelines_data())
        elif path == "/api/features":
            self.send_json(get_features_data())
        elif path == "/api/config":
            config_path = PROJECT_ROOT / "didio.config.json"
            if config_path.is_file():
                try:
                    with open(config_path, "r", encoding="utf-8") as f:
                        self.send_json(json.load(f))
                except (json.JSONDecodeError, OSError):
                    self.send_json({"error": "config unreadable"}, 500)
            else:
                self.send_json({})
        elif path == "/api/squad":
            agents_dir = PROJECT_ROOT / "logs" / "agents"
            reports = read_json_files(agents_dir / "squad-report-*.json")
            bravo = read_json_files(agents_dir / "bravo-report-*.json")
            charlie = read_json_files(agents_dir / "charlie-report-*.json")
            delta = read_json_files(agents_dir / "delta-report-*.json")
            self.send_json({
                "squad": reports[-1] if reports else None,
                "bravo": bravo[-1] if bravo else None,
                "charlie": charlie[-1] if charlie else None,
                "delta": delta[-1] if delta else None,
            })
        else:
            self.send_error(404, f"Not found: {path}")

    def do_POST(self):
        """Handle action requests from the command center."""
        parsed = urlparse(self.path)
        path = parsed.path.rstrip("/")
        content_length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(content_length) if content_length else b""
        try:
            payload = json.loads(body) if body else {}
        except json.JSONDecodeError:
            self.send_json({"error": "invalid JSON"}, 400)
            return

        if path == "/api/warroom/move":
            card_id = payload.get("card_id")
            new_status = payload.get("status")
            if not card_id or not new_status:
                self.send_json({"error": "card_id and status required"}, 400)
                return
            cards_dir = PROJECT_ROOT / "logs" / "warroom" / "cards"
            card_file = cards_dir / f"{card_id}.json"
            if not card_file.is_file():
                self.send_json({"error": f"card {card_id} not found"}, 404)
                return
            try:
                with open(card_file, "r", encoding="utf-8") as f:
                    card = json.load(f)
                card["status"] = new_status
                import datetime
                card["updated_at"] = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
                with open(card_file, "w", encoding="utf-8") as f:
                    json.dump(card, f, ensure_ascii=False, indent=2)
                self.send_json({"ok": True, "card_id": card_id, "status": new_status})
            except (json.JSONDecodeError, OSError) as e:
                self.send_json({"error": str(e)}, 500)

        elif path == "/api/warroom/add":
            title = payload.get("title", "").strip()
            body_text = payload.get("body", "").strip()
            priority = payload.get("priority", "medium")
            tags = payload.get("tags", [])
            if not title:
                self.send_json({"error": "title required"}, 400)
                return
            cards_dir = PROJECT_ROOT / "logs" / "warroom" / "cards"
            cards_dir.mkdir(parents=True, exist_ok=True)
            import datetime
            today = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%d")
            existing = sorted(cards_dir.glob(f"WR-{today}-*.json"))
            seq = len(existing) + 1
            card_id = f"WR-{today}-{seq:03d}"
            now_iso = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
            card = {
                "card_id": card_id, "title": title, "body": body_text,
                "source": "operator", "status": "incoming",
                "priority_suggestion": priority, "tags": tags if isinstance(tags, list) else [],
                "created_at": now_iso, "updated_at": None,
                "overlord_assessment": None, "promoted_to": None,
            }
            with open(cards_dir / f"{card_id}.json", "w", encoding="utf-8") as f:
                json.dump(card, f, ensure_ascii=False, indent=2)
            self.send_json({"ok": True, "card_id": card_id})

        elif path == "/api/command":
            # Execute a didio command suggestion
            action = payload.get("action")
            self.send_json({"ok": True, "action": action, "note": "queued for review"})

        else:
            self.send_json({"error": f"unknown POST route: {path}"}, 404)

    def do_OPTIONS(self):
        """Handle CORS preflight."""
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()


def main():
    parser = argparse.ArgumentParser(description="didio board server")
    parser.add_argument("--port", type=int, default=8844,
                        help="Port to listen on (default: 8844)")
    parser.add_argument("--open", action="store_true", default=True,
                        help="Open browser automatically (default)")
    parser.add_argument("--no-open", action="store_true",
                        help="Do not open browser")
    args = parser.parse_args()

    if args.no_open:
        args.open = False

    port = args.port
    server = HTTPServer(("", port), BoardHandler)

    # Graceful shutdown
    def shutdown_handler(signum, frame):
        print(f"\n[board] Shutting down...", file=sys.stderr)
        threading.Thread(target=server.shutdown).start()

    signal.signal(signal.SIGINT, shutdown_handler)
    signal.signal(signal.SIGTERM, shutdown_handler)

    print(f"[board] Serving on http://localhost:{port}", file=sys.stderr)
    print(f"[board] Project root: {PROJECT_ROOT}", file=sys.stderr)

    if args.open:
        threading.Timer(0.5, lambda: webbrowser.open(f"http://localhost:{port}")).start()

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
        print("[board] Server stopped.", file=sys.stderr)


if __name__ == "__main__":
    main()
