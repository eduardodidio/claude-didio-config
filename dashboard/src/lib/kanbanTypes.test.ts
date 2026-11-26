import { describe, it, expect } from 'vitest';
import type {
  FlagType,
  FlagSeverity,
  AgentFlag,
  ActionType,
  OperatorAction,
  KanbanColumn,
  Priority,
  KanbanCard,
  KanbanBoardState,
  PipelineStatus,
  GovernanceState,
} from './kanbanTypes';
import { KANBAN_COLUMNS } from './kanbanTypes';

describe('kanbanTypes', () => {
  it('FlagType accepts all valid flag types', () => {
    const types: FlagType[] = [
      'blocked',
      'needs_review',
      'escalated',
      'needs_input',
      'token_warning',
    ];
    expect(types).toHaveLength(5);
  });

  it('FlagSeverity accepts all valid severities', () => {
    const severities: FlagSeverity[] = ['critical', 'warning', 'info'];
    expect(severities).toHaveLength(3);
  });

  it('ActionType accepts all valid action types', () => {
    const actions: ActionType[] = [
      'unblock',
      'approve',
      'skip',
      'pause',
      'resume',
      'cancel',
    ];
    expect(actions).toHaveLength(6);
  });

  it('KanbanColumn accepts all valid column types', () => {
    const columns: KanbanColumn[] = [
      'BACKLOG',
      'PLANNING',
      'RUNNING',
      'REVIEW',
      'DONE',
    ];
    expect(columns).toHaveLength(5);
  });

  it('KANBAN_COLUMNS is a readonly array of 5 columns in order', () => {
    expect(KANBAN_COLUMNS).toEqual([
      'BACKLOG',
      'PLANNING',
      'RUNNING',
      'REVIEW',
      'DONE',
    ]);
    expect(KANBAN_COLUMNS).toHaveLength(5);
  });

  it('Priority accepts all valid priority levels', () => {
    const priorities: Priority[] = ['low', 'medium', 'high', 'max'];
    expect(priorities).toHaveLength(4);
  });

  it('accepts a well-formed AgentFlag literal', () => {
    const flag: AgentFlag = {
      flag_id: 'F01_blocked_20261101',
      type: 'blocked',
      feature: 'F01',
      task: 'F01-T03',
      severity: 'critical',
      reason: 'Dependency missing',
      suggested_actions: ['auto_resolve', 'skip_task'],
      created_at: '2026-11-01T10:00:00Z',
      resolved_at: null,
    };
    expect(flag.flag_id).toBeTruthy();
    expect(flag.resolved_at).toBeNull();
  });

  it('accepts a well-formed OperatorAction literal', () => {
    const action: OperatorAction = {
      action_id: 'act-001',
      action: 'unblock',
      feature: 'F01',
      task: 'F01-T03',
      operator: 'user',
      timestamp: '2026-11-01T10:05:00Z',
      params: { reason: 'manual override' },
    };
    expect(action.action).toBe('unblock');
  });

  it('accepts a well-formed KanbanCard literal', () => {
    const card: KanbanCard = {
      feature: 'F01',
      column: 'RUNNING',
      progress: 60,
      taskCount: 10,
      completedTasks: 6,
      currentPhase: 'developer',
      currentTask: 'F01-T05',
      flags: [],
      isBlocked: false,
      priority: 'medium',
    };
    expect(card.progress).toBe(60);
  });

  it('accepts a well-formed KanbanBoardState literal', () => {
    const state: KanbanBoardState = {
      cards: [],
      flags: [],
      generated_at: '2026-11-01T10:00:00Z',
    };
    expect(state.cards).toEqual([]);
  });

  it('accepts a well-formed PipelineStatus literal', () => {
    const ps: PipelineStatus = {
      feature: 'F30',
      phase: 'wave_2',
      started_at: '2026-11-01T08:00:00Z',
      token_budget_used: 5000,
      token_budget_total: 10000,
      agent_count: 3,
      current_wave: 2,
    };
    expect(ps.token_budget_used).toBe(5000);
  });

  it('accepts a well-formed GovernanceState literal', () => {
    const gov: GovernanceState = {
      pipelines: [],
      total_flags: 5,
      critical_flags: 1,
      resolved_flags: 3,
      generated_at: '2026-11-01T10:00:00Z',
    };
    expect(gov.total_flags).toBe(5);
  });
});
