import { describe, it, expect } from 'vitest';
import {
  COLUMN_CONFIG,
  flagDotClass,
  deriveColumn,
} from './kanbanHelpers';
import type { AgentFlag, KanbanColumn } from './kanbanTypes';
import type { FeatureProgress, AgentRun } from './types';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

function fp(overrides: Partial<FeatureProgress> = {}): FeatureProgress {
  return {
    feature: 'F01',
    total: 10,
    completed: 0,
    running: 0,
    failed: 0,
    percent: 0,
    current_wave: null,
    current_task: null,
    trail: [],
    ...overrides,
  };
}

function agent(overrides: Partial<AgentRun> = {}): AgentRun {
  return {
    feature: 'F01',
    role: 'developer',
    task: 'F01-T01',
    task_file: 'tasks/features/F01/F01-T01.md',
    started_at: '2026-11-01T10:00:00Z',
    finished_at: null,
    status: 'running',
    exit_code: null,
    pid: 1,
    log: 'logs/agents/F01-T01.jsonl',
    phrase: null,
    ...overrides,
  };
}

// ---------------------------------------------------------------------------
// COLUMN_CONFIG
// ---------------------------------------------------------------------------

describe('COLUMN_CONFIG', () => {
  it('has entries for all 5 columns', () => {
    const expected: KanbanColumn[] = ['BACKLOG', 'PLANNING', 'RUNNING', 'REVIEW', 'DONE'];
    for (const col of expected) {
      expect(COLUMN_CONFIG[col]).toBeDefined();
      expect(COLUMN_CONFIG[col].label).toBeTruthy();
      expect(COLUMN_CONFIG[col].bgClass).toBeTruthy();
      expect(COLUMN_CONFIG[col].headerClass).toBeTruthy();
    }
  });

  it('labels are human-readable titles', () => {
    expect(COLUMN_CONFIG.BACKLOG.label).toBe('Backlog');
    expect(COLUMN_CONFIG.DONE.label).toBe('Done');
  });
});

// ---------------------------------------------------------------------------
// flagDotClass
// ---------------------------------------------------------------------------

describe('flagDotClass', () => {
  it('returns red for blocked type', () => {
    expect(flagDotClass('warning', 'blocked')).toBe('bg-red-500');
  });

  it('returns red for critical severity', () => {
    expect(flagDotClass('critical', 'needs_review')).toBe('bg-red-500');
  });

  it('returns yellow for warning severity', () => {
    expect(flagDotClass('warning', 'needs_review')).toBe('bg-yellow-500');
  });

  it('returns blue for info severity', () => {
    expect(flagDotClass('info', 'needs_review')).toBe('bg-blue-500');
  });

  it('returns blue for unknown severity', () => {
    expect(flagDotClass('unknown', 'some_type')).toBe('bg-blue-500');
  });
});

// ---------------------------------------------------------------------------
// deriveColumn
// ---------------------------------------------------------------------------

describe('deriveColumn', () => {
  it('returns DONE for 100% features', () => {
    expect(deriveColumn(fp({ percent: 100 }), [], [])).toBe('DONE');
  });

  it('returns BACKLOG for 0% with no running agents', () => {
    expect(deriveColumn(fp({ percent: 0, running: 0 }), [], [])).toBe('BACKLOG');
  });

  it('returns PLANNING for running architect', () => {
    const agents = [agent({ role: 'architect', status: 'running' })];
    expect(deriveColumn(fp({ percent: 5, running: 1 }), [], agents)).toBe('PLANNING');
  });

  it('returns RUNNING for running developer', () => {
    const agents = [agent({ role: 'developer', status: 'running' })];
    expect(deriveColumn(fp({ percent: 30, running: 1 }), [], agents)).toBe('RUNNING');
  });

  it('returns REVIEW for running qa', () => {
    const agents = [agent({ role: 'qa', status: 'running' })];
    expect(deriveColumn(fp({ percent: 80, running: 1 }), [], agents)).toBe('REVIEW');
  });

  it('returns REVIEW for running reviewer', () => {
    const agents = [agent({ role: 'reviewer', status: 'running' })];
    expect(deriveColumn(fp({ percent: 80, running: 1 }), [], agents)).toBe('REVIEW');
  });

  it('returns REVIEW for running security', () => {
    const agents = [agent({ role: 'security', status: 'running' })];
    expect(deriveColumn(fp({ percent: 80, running: 1 }), [], agents)).toBe('REVIEW');
  });

  it('falls back to PLANNING for < 20% with no running agent match', () => {
    expect(deriveColumn(fp({ percent: 10, running: 1 }), [], [])).toBe('PLANNING');
  });

  it('falls back to RUNNING for 20-79%', () => {
    expect(deriveColumn(fp({ percent: 50, running: 1 }), [], [])).toBe('RUNNING');
  });

  it('falls back to REVIEW for >= 80%', () => {
    expect(deriveColumn(fp({ percent: 85, running: 1 }), [], [])).toBe('REVIEW');
  });

  it('ignores completed agents when looking for running phase', () => {
    const agents = [agent({ role: 'architect', status: 'completed' })];
    // 50% with no running agent -> fallback heuristic -> RUNNING
    expect(deriveColumn(fp({ percent: 50, running: 1 }), [], agents)).toBe('RUNNING');
  });

  it('only matches agents for the same feature', () => {
    const agents = [agent({ feature: 'F02', role: 'architect', status: 'running' })];
    // F01 feature with 10% -> fallback -> PLANNING
    expect(deriveColumn(fp({ percent: 10, running: 1 }), [], agents)).toBe('PLANNING');
  });
});
