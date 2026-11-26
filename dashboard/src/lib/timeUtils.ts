// ---------------------------------------------------------------------------
// F30-T05 — Relative time formatting utility
// ---------------------------------------------------------------------------

/**
 * Converts an ISO-8601 date string into a human-friendly relative timestamp.
 *
 * Examples: "just now", "5m ago", "2h ago", "3d ago"
 */
export function relativeTime(isoDate: string): string {
  const diff = Date.now() - Date.parse(isoDate);
  const mins = Math.floor(diff / 60_000);
  if (mins < 1) return 'just now';
  if (mins < 60) return `${mins}m ago`;
  const hours = Math.floor(mins / 60);
  if (hours < 24) return `${hours}h ago`;
  const days = Math.floor(hours / 24);
  return `${days}d ago`;
}
