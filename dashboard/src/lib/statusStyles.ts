import type { AgentRun, TrailStatus } from './types';

interface StatusStyleEntry {
  dot: string;
  chip: string;
  glyph: string;
}

export const STATUS_STYLE: Record<string, StatusStyleEntry> = {
  completed: {
    dot: 'bg-emerald-500',
    chip: 'bg-emerald-500/15 text-emerald-500 border-emerald-500/30',
    glyph: '✓',
  },
  running: {
    dot: 'bg-amber-500',
    chip: 'bg-amber-500/15 text-amber-500 border-amber-500/40 animate-pulse',
    glyph: '▶',
  },
  failed: {
    dot: 'bg-red-500',
    chip: 'bg-red-500/15 text-red-500 border-red-500/40',
    glyph: '✗',
  },
  blocked: {
    dot: 'bg-orange-500',
    chip: 'bg-orange-500/15 text-orange-500 border-orange-500/40',
    glyph: '⊘',
  },
  planned: {
    dot: 'bg-muted',
    chip: 'bg-muted text-muted-foreground border-border',
    glyph: '·',
  },
};

const FALLBACK: StatusStyleEntry = {
  dot: 'bg-muted',
  chip: 'bg-muted text-muted-foreground border-border',
  glyph: '·',
};

export function getStatusDot(status: string): string {
  return (STATUS_STYLE[status] ?? FALLBACK).dot;
}

export function getTrailChipClasses(status: TrailStatus): string {
  return (STATUS_STYLE[status] ?? FALLBACK).chip;
}

export function getTrailGlyph(status: TrailStatus): string {
  return (STATUS_STYLE[status] ?? FALLBACK).glyph;
}

export function getAggregateDot(runs: AgentRun[]): string {
  if (runs.some((r) => r.status === 'failed')) return STATUS_STYLE.failed.dot;
  if (runs.some((r) => r.status === 'running')) return STATUS_STYLE.running.dot;
  return STATUS_STYLE.completed.dot;
}
