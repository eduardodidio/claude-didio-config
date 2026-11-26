// ---------------------------------------------------------------------------
// F30-T01 — Kanban Board Types
// Canonical TypeScript types mirroring schemas/flag.schema.json and
// schemas/action.schema.json.
// ---------------------------------------------------------------------------

// Flag types
export type FlagType =
  | 'blocked'
  | 'needs_review'
  | 'escalated'
  | 'needs_input'
  | 'token_warning';

export type FlagSeverity = 'critical' | 'warning' | 'info';

export interface AgentFlag {
  flag_id: string;
  type: FlagType;
  feature: string;
  task: string | null;
  severity: FlagSeverity;
  reason: string;
  suggested_actions: string[];
  created_at: string;
  resolved_at: string | null;
}

// Action types
export type ActionType =
  | 'unblock'
  | 'approve'
  | 'skip'
  | 'pause'
  | 'resume'
  | 'cancel';

export interface OperatorAction {
  action_id: string;
  action: ActionType;
  feature: string;
  task: string | null;
  operator: string;
  timestamp: string;
  params: Record<string, unknown>;
}

// Kanban column types
export type KanbanColumn =
  | 'BACKLOG'
  | 'PLANNING'
  | 'RUNNING'
  | 'REVIEW'
  | 'DONE';

export const KANBAN_COLUMNS: readonly KanbanColumn[] = [
  'BACKLOG',
  'PLANNING',
  'RUNNING',
  'REVIEW',
  'DONE',
] as const;

// Priority
export type Priority = 'low' | 'medium' | 'high' | 'max';

export interface KanbanCard {
  feature: string;
  column: KanbanColumn;
  progress: number; // 0-100
  taskCount: number;
  completedTasks: number;
  currentPhase: string | null;
  currentTask: string | null;
  flags: AgentFlag[];
  isBlocked: boolean;
  priority: Priority;
}

export interface KanbanBoardState {
  cards: KanbanCard[];
  flags: AgentFlag[];
  generated_at: string;
}

// Governance types
export interface PipelineStatus {
  feature: string;
  phase: string;
  started_at: string;
  token_budget_used: number;
  token_budget_total: number;
  agent_count: number;
  current_wave: number | null;
}

export interface GovernanceState {
  pipelines: PipelineStatus[];
  total_flags: number;
  critical_flags: number;
  resolved_flags: number;
  generated_at: string;
}
