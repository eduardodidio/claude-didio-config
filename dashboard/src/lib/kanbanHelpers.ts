import type { AgentFlag, KanbanColumn } from './kanbanTypes';
import type { FeatureProgress, AgentRun } from './types';

// ---- Column display configuration ------------------------------------------

export interface ColumnConfig {
  label: string;
  bgClass: string;
  headerClass: string;
}

export const COLUMN_CONFIG: Record<KanbanColumn, ColumnConfig> = {
  BACKLOG: {
    label: 'Backlog',
    bgClass: 'bg-muted/40',
    headerClass: 'text-muted-foreground',
  },
  PLANNING: {
    label: 'Planning',
    bgClass: 'bg-blue-500/5',
    headerClass: 'text-blue-600',
  },
  RUNNING: {
    label: 'Running',
    bgClass: 'bg-amber-500/5',
    headerClass: 'text-amber-600',
  },
  REVIEW: {
    label: 'Review',
    bgClass: 'bg-purple-500/5',
    headerClass: 'text-purple-600',
  },
  DONE: {
    label: 'Done',
    bgClass: 'bg-green-500/5',
    headerClass: 'text-green-600',
  },
};

/** Map flag severity / type to a Tailwind dot color class. */
export function flagDotClass(severity: string, type: string): string {
  if (type === 'blocked' || severity === 'critical') return 'bg-red-500';
  if (severity === 'warning') return 'bg-yellow-500';
  return 'bg-blue-500';
}

// ---- Column derivation -----------------------------------------------------

/**
 * Derive which Kanban column a feature belongs to based on its progress,
 * active flags, and currently running agents.
 */
export function deriveColumn(
  feature: FeatureProgress,
  _flags: AgentFlag[],
  agents: AgentRun[],
): KanbanColumn {
  // Completed features always go to DONE
  if (feature.percent === 100) return 'DONE';

  // No progress and nothing running -> BACKLOG
  if (feature.percent === 0 && feature.running === 0) return 'BACKLOG';

  // Check for a running agent to determine phase
  const running = agents.find(
    (a) => a.feature === feature.feature && a.status === 'running',
  );
  if (running) {
    if (running.role === 'architect') return 'PLANNING';
    if (running.role === 'developer') return 'RUNNING';
    if (['qa', 'reviewer', 'security'].includes(running.role)) return 'REVIEW';
  }

  // Fallback: percent-based heuristic
  if (feature.percent < 20) return 'PLANNING';
  if (feature.percent < 80) return 'RUNNING';
  return 'REVIEW';
}
