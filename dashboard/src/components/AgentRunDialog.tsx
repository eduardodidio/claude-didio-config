import { useEffect, useRef } from 'react';
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
} from '@/components/ui/dialog';
import { useAgentLog, type LogEntry } from '@/hooks/useAgentLog';
import type { AgentRun } from '@/lib/types';
import { cn } from '@/lib/utils';

interface AgentRunDialogProps {
  run: AgentRun | null;
  open: boolean;
  onOpenChange: (open: boolean) => void;
}

function durationOf(run: AgentRun): string {
  const start = Date.parse(run.started_at);
  const end = run.finished_at ? Date.parse(run.finished_at) : Date.now();
  if (Number.isNaN(start) || Number.isNaN(end)) return '—';
  const ms = Math.max(0, end - start);
  const s = Math.floor(ms / 1000);
  if (s < 60) return `${s}s`;
  const m = Math.floor(s / 60);
  return `${m}m ${s - m * 60}s`;
}

function lineColor(entry: LogEntry): string {
  const t = entry.type ?? '';
  if (t.includes('error') || t.includes('failed')) return 'text-red-400';
  if (t.includes('tool_use') || t.includes('tool_call')) return 'text-cyan-400';
  if (t.includes('tool_result')) return 'text-emerald-400';
  if (t.includes('text') || t.includes('assistant')) return 'text-zinc-100';
  if (t.includes('system')) return 'text-amber-400';
  return 'text-zinc-300';
}

function formatLine(entry: LogEntry): string {
  if (!entry.parsed) return entry.raw;
  const ts = entry.ts ? `${entry.ts.slice(11, 19)} ` : '';
  const type = entry.type ? `[${entry.type}] ` : '';
  const rest = { ...entry.parsed };
  delete rest.ts;
  delete rest.type;
  let body = '';
  if (typeof rest.text === 'string') body = rest.text;
  else if (typeof rest.message === 'string') body = rest.message;
  else if (typeof rest.name === 'string') body = String(rest.name);
  else body = JSON.stringify(rest);
  return `${ts}${type}${body}`;
}

export function AgentRunDialog({ run, open, onOpenChange }: AgentRunDialogProps) {
  const isRunning = run?.status === 'running';
  const { entries, error, loading } = useAgentLog(
    open && run ? run.task : null,
    !!isRunning,
  );
  const preRef = useRef<HTMLPreElement>(null);

  useEffect(() => {
    if (!isRunning) return;
    const el = preRef.current;
    if (el) el.scrollTop = el.scrollHeight;
  }, [entries, isRunning]);

  if (!run) return null;

  const copyPath = () => {
    void navigator.clipboard?.writeText(run.log);
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent
        className="max-h-[90vh] w-[min(95vw,1100px)] max-w-[1100px] gap-3 overflow-hidden"
        onClose={() => onOpenChange(false)}
        data-testid="agent-run-dialog"
      >
        <DialogHeader>
          <DialogTitle className="font-mono">
            {run.task}{' '}
            <span className="ml-2 text-xs uppercase text-muted-foreground">
              {run.role} · {run.status}
            </span>
          </DialogTitle>
          <DialogDescription className="flex flex-wrap gap-x-4 gap-y-1 font-mono text-xs">
            <span>feature: {run.feature}</span>
            <span>pid: {run.pid}</span>
            <span>duration: {durationOf(run)}</span>
            <span>
              exit:{' '}
              {run.exit_code === null || run.exit_code === undefined
                ? '—'
                : run.exit_code}
            </span>
            {run.phrase && (
              <span className="italic text-foreground">"{run.phrase}"</span>
            )}
          </DialogDescription>
        </DialogHeader>

        <div className="flex items-center justify-between text-xs text-muted-foreground">
          <span className="font-mono">{run.log}</span>
          <button
            type="button"
            onClick={copyPath}
            className="rounded border px-2 py-1 hover:bg-accent"
          >
            Copy path
          </button>
        </div>

        <pre
          ref={preRef}
          data-testid="agent-run-log"
          className="h-[60vh] overflow-auto rounded-md border bg-zinc-950 p-4 font-mono text-xs leading-relaxed"
        >
          {loading && entries.length === 0 && (
            <span className="text-zinc-500">loading log…</span>
          )}
          {error && entries.length === 0 && (
            <span className="text-red-400">failed to load log: {error}</span>
          )}
          {entries.length === 0 && !loading && !error && (
            <span className="text-zinc-500">no log entries yet</span>
          )}
          {entries.map((entry, i) => (
            <div key={i} className={cn('whitespace-pre-wrap', lineColor(entry))}>
              {formatLine(entry)}
            </div>
          ))}
        </pre>
      </DialogContent>
    </Dialog>
  );
}

export default AgentRunDialog;
