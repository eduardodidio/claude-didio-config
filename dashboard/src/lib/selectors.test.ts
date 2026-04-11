import { describe, it, expect } from 'vitest';
import {
  computeOverviewStats,
  groupByFeature,
  latestPhrase,
} from './selectors';
import type { AgentRun, DidioState } from './types';

function run(partial: Partial<AgentRun>): AgentRun {
  return {
    feature: 'F01',
    role: 'developer',
    task: 'F01-T01',
    task_file: 'tasks/features/F01-dashboard/F01-T01.md',
    started_at: '2026-04-11T09:00:00Z',
    finished_at: null,
    status: 'running',
    exit_code: null,
    pid: 1,
    log: 'logs/agents/F01-T01.jsonl',
    phrase: null,
    ...partial,
  };
}

const fixture: DidioState = {
  generated_at: '2026-04-11T10:00:00Z',
  agents: [
    run({
      task: 'F01-T01',
      role: 'architect',
      status: 'completed',
      started_at: '2026-04-11T08:00:00Z',
      finished_at: '2026-04-11T08:05:00Z',
      phrase: 'I have a bad feeling about this.',
    }),
    run({
      task: 'F01-T02',
      role: 'developer',
      status: 'completed',
      started_at: '2026-04-11T08:30:00Z',
      phrase: 'These are not the bugs you are looking for.',
    }),
    run({
      task: 'F01-T03',
      role: 'qa',
      status: 'running',
      started_at: '2026-04-11T09:30:00Z',
    }),
    run({
      feature: 'F02',
      task: 'F02-T01',
      role: 'developer',
      status: 'failed',
      started_at: '2026-04-11T09:45:00Z',
      phrase: 'Houston, we have a problem.',
    }),
    run({
      feature: 'F02',
      task: 'F02-T02',
      role: 'reviewer',
      status: 'running',
      started_at: '2026-04-11T09:50:00Z',
    }),
  ],
};

describe('computeOverviewStats', () => {
  it('counts active features and statuses', () => {
    const stats = computeOverviewStats(fixture);
    expect(stats).toEqual({
      activeFeatures: 2,
      running: 2,
      completed: 2,
      failed: 1,
    });
  });

  it('returns zeros for empty agents (edge)', () => {
    const stats = computeOverviewStats({
      generated_at: 'x',
      agents: [],
    });
    expect(stats).toEqual({
      activeFeatures: 0,
      running: 0,
      completed: 0,
      failed: 0,
    });
  });

  it('boundary: single running agent', () => {
    const stats = computeOverviewStats({
      generated_at: 'x',
      agents: [run({ status: 'running' })],
    });
    expect(stats.running).toBe(1);
    expect(stats.completed).toBe(0);
  });
});

describe('groupByFeature', () => {
  it('groups agents under their feature key', () => {
    const groups = groupByFeature(fixture);
    expect(groups).toHaveLength(2);
    const f01 = groups.find((g) => g.feature === 'F01')!;
    const f02 = groups.find((g) => g.feature === 'F02')!;
    expect(f01.runs).toHaveLength(3);
    expect(f02.runs).toHaveLength(2);
  });

  it('returns empty array for empty state', () => {
    expect(groupByFeature({ generated_at: 'x', agents: [] })).toEqual([]);
  });
});

describe('latestPhrase', () => {
  it('picks the phrase from the most recently started run', () => {
    const latest = latestPhrase(fixture);
    expect(latest).not.toBeNull();
    expect(latest!.role).toBe('developer');
    expect(latest!.phrase).toBe('Houston, we have a problem.');
  });

  it('returns null when no runs have a phrase', () => {
    const state: DidioState = {
      generated_at: 'x',
      agents: [run({ phrase: null }), run({ phrase: null })],
    };
    expect(latestPhrase(state)).toBeNull();
  });

  it('returns null for empty state (edge)', () => {
    expect(latestPhrase({ generated_at: 'x', agents: [] })).toBeNull();
  });
});
