import { describe, it, expect } from 'vitest';
import {
  derivePipelineTable,
  deriveTokenBudget,
  deriveFlagAnalytics,
} from './governanceHelpers';
import type { DidioState } from './types';
import type { PipelineStatus, AgentFlag } from './kanbanTypes';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

function mkPipeline(overrides: Partial<PipelineStatus> = {}): PipelineStatus {
  return {
    feature: 'F01',
    phase: 'wave_1',
    started_at: '2026-11-01T08:00:00Z',
    token_budget_used: 2000,
    token_budget_total: 10000,
    agent_count: 2,
    current_wave: 1,
    ...overrides,
  };
}

function mkFlag(overrides: Partial<AgentFlag> = {}): AgentFlag {
  return {
    flag_id: 'f1',
    type: 'blocked',
    feature: 'F01',
    task: null,
    severity: 'critical',
    reason: 'test',
    suggested_actions: [],
    created_at: '2026-11-01T10:00:00Z',
    resolved_at: null,
    ...overrides,
  };
}

function mkDidio(features: DidioState['features'] = []): DidioState {
  return {
    generated_at: '2026-11-01T10:00:00Z',
    agents: [],
    features,
  };
}

// ---------------------------------------------------------------------------
// derivePipelineTable
// ---------------------------------------------------------------------------

describe('derivePipelineTable', () => {
  it('creates correct rows from features + pipelines', () => {
    const didio = mkDidio([
      {
        feature: 'F01',
        total: 10,
        completed: 5,
        running: 1,
        failed: 0,
        percent: 50,
        current_wave: 1,
        current_task: 'F01-T05',
        trail: [],
      },
    ]);
    const pipelines = [mkPipeline({ feature: 'F01', phase: 'wave_1' })];
    const flags = [mkFlag({ feature: 'F01' })];

    const rows = derivePipelineTable(didio, pipelines, flags);
    expect(rows).toHaveLength(1);
    expect(rows[0].feature).toBe('F01');
    expect(rows[0].phase).toBe('wave_1');
    expect(rows[0].progress).toBe(50);
    expect(rows[0].flagCount).toBe(1);
    expect(rows[0].tokenUsed).toBe(2000);
  });

  it('returns pipeline-only rows when features array is empty', () => {
    const pipelines = [mkPipeline({ feature: 'F01' })];
    const rows = derivePipelineTable(mkDidio([]), pipelines, []);
    expect(rows).toHaveLength(1);
    expect(rows[0].progress).toBe(0);
  });

  it('returns empty when both features and pipelines are empty', () => {
    const rows = derivePipelineTable(mkDidio([]), [], []);
    expect(rows).toEqual([]);
  });

  it('returns empty for undefined inputs', () => {
    const rows = derivePipelineTable(undefined, undefined, undefined);
    expect(rows).toEqual([]);
  });

  it('excludes resolved flags from flag count', () => {
    const didio = mkDidio([
      {
        feature: 'F01',
        total: 5,
        completed: 2,
        running: 0,
        failed: 0,
        percent: 40,
        current_wave: null,
        current_task: null,
        trail: [],
      },
    ]);
    const flags = [
      mkFlag({ flag_id: 'f1', feature: 'F01', resolved_at: null }),
      mkFlag({ flag_id: 'f2', feature: 'F01', resolved_at: '2026-11-01T12:00:00Z' }),
    ];
    const rows = derivePipelineTable(didio, [], flags);
    expect(rows[0].flagCount).toBe(1);
  });
});

// ---------------------------------------------------------------------------
// deriveTokenBudget
// ---------------------------------------------------------------------------

describe('deriveTokenBudget', () => {
  it('aggregates correctly across pipelines', () => {
    const pipelines = [
      mkPipeline({ feature: 'F01', token_budget_used: 3000, token_budget_total: 10000 }),
      mkPipeline({ feature: 'F02', token_budget_used: 7000, token_budget_total: 10000 }),
    ];
    const result = deriveTokenBudget(pipelines);
    expect(result).not.toBeNull();
    expect(result!.totalAllocated).toBe(20000);
    expect(result!.totalConsumed).toBe(10000);
    expect(result!.remaining).toBe(10000);
    expect(result!.pctUsed).toBe(50);
    expect(result!.perFeature).toHaveLength(2);
  });

  it('returns null for empty pipelines', () => {
    expect(deriveTokenBudget([])).toBeNull();
  });

  it('returns null for undefined pipelines', () => {
    expect(deriveTokenBudget(undefined)).toBeNull();
  });

  it('sets hasWarning when any feature >= 80%', () => {
    const pipelines = [
      mkPipeline({ token_budget_used: 8500, token_budget_total: 10000 }),
    ];
    const result = deriveTokenBudget(pipelines);
    expect(result!.hasWarning).toBe(true);
  });

  it('no warning when all below 80%', () => {
    const pipelines = [
      mkPipeline({ token_budget_used: 5000, token_budget_total: 10000 }),
    ];
    const result = deriveTokenBudget(pipelines);
    expect(result!.hasWarning).toBe(false);
  });

  it('handles zero total budget gracefully', () => {
    const pipelines = [
      mkPipeline({ token_budget_used: 0, token_budget_total: 0 }),
    ];
    const result = deriveTokenBudget(pipelines);
    expect(result!.pctUsed).toBe(0);
    expect(result!.perFeature[0].pct).toBe(0);
  });
});

// ---------------------------------------------------------------------------
// deriveFlagAnalytics
// ---------------------------------------------------------------------------

describe('deriveFlagAnalytics', () => {
  it('computes correct counts and distributions', () => {
    const flags = [
      mkFlag({ flag_id: 'f1', severity: 'critical', type: 'blocked', resolved_at: null }),
      mkFlag({ flag_id: 'f2', severity: 'warning', type: 'needs_review', resolved_at: null }),
      mkFlag({ flag_id: 'f3', severity: 'critical', type: 'blocked', resolved_at: '2026-11-01T12:00:00Z' }),
      mkFlag({ flag_id: 'f4', severity: 'info', type: 'token_warning', resolved_at: null }),
    ];

    const result = deriveFlagAnalytics(flags);
    expect(result.total).toBe(4);
    expect(result.active).toBe(3);
    expect(result.resolved).toBe(1);
    expect(result.critical).toBe(1); // only unresolved criticals
    expect(result.bySeverity.critical).toBe(2);
    expect(result.bySeverity.warning).toBe(1);
    expect(result.bySeverity.info).toBe(1);
    expect(result.byType.blocked).toBe(2);
    expect(result.byType.needs_review).toBe(1);
    expect(result.byType.token_warning).toBe(1);
  });

  it('returns zeroed analytics for undefined flags', () => {
    const result = deriveFlagAnalytics(undefined);
    expect(result.total).toBe(0);
    expect(result.active).toBe(0);
    expect(result.resolved).toBe(0);
    expect(result.critical).toBe(0);
  });

  it('returns zeroed analytics for empty flags', () => {
    const result = deriveFlagAnalytics([]);
    expect(result.total).toBe(0);
  });
});
