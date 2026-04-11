import { describe, it, expect } from 'vitest';
import type {
  AgentRole,
  AgentRun,
  AgentStatus,
  DidioState,
  EasterEggFranchise,
  EasterEggsFile,
  FeatureGroup,
  OverviewStats,
} from './types';

describe('types', () => {
  it('accepts a well-formed DidioState literal', () => {
    const run: AgentRun = {
      feature: 'F01',
      role: 'developer',
      task: 'F01-T03',
      task_file: 'tasks/features/F01-dashboard/F01-T03.md',
      started_at: '2026-04-11T10:00:00Z',
      finished_at: null,
      status: 'running',
      exit_code: null,
      pid: 12345,
      log: 'logs/agents/F01-T03.jsonl',
      phrase: null,
    };

    const state: DidioState = {
      generated_at: '2026-04-11T10:00:01Z',
      agents: [run],
    };

    expect(state.agents).toHaveLength(1);
    expect(state.agents[0].finished_at).toBeNull();
  });

  it('accepts an empty agents array (boundary)', () => {
    const state: DidioState = {
      generated_at: '2026-04-11T10:00:00Z',
      agents: [],
    };
    expect(state.agents).toEqual([]);
  });

  it('accepts a completed AgentRun with finished_at and exit_code set', () => {
    const run: AgentRun = {
      feature: 'F01',
      role: 'qa',
      task: 'F01-T02',
      task_file: 'tasks/features/F01-dashboard/F01-T02.md',
      started_at: '2026-04-11T09:00:00Z',
      finished_at: '2026-04-11T09:05:00Z',
      status: 'completed',
      exit_code: 0,
      pid: 999,
      log: 'logs/agents/F01-T02.jsonl',
      phrase: 'May the tests be with you.',
    };
    expect(run.status).toBe('completed');
    expect(run.exit_code).toBe(0);
  });

  it('exposes all AgentRole literals', () => {
    const roles: AgentRole[] = [
      'architect',
      'developer',
      'qa',
      'security',
      'reviewer',
      'devops',
      'docs',
    ];
    expect(roles).toHaveLength(7);
  });

  it('exposes all AgentStatus literals', () => {
    const statuses: AgentStatus[] = ['running', 'completed', 'failed', 'blocked'];
    expect(statuses).toHaveLength(4);
  });

  it('accepts EasterEggFranchise matching the real file shape', () => {
    const f: EasterEggFranchise = {
      emoji: '⚔️',
      tags: ['ninja'],
      success: ['a', 'b', 'c', 'd'],
      failure: ['oops'],
    };
    expect(f.success).toHaveLength(4);
  });

  it('accepts EasterEggsFile with Record-keyed franchises and role_mapping arrays', () => {
    const eggs: EasterEggsFile = {
      version: 1,
      franchises: {
        star_wars: { emoji: '⚔️', success: ['a', 'b', 'c', 'd'], failure: ['x'] },
        mario: { emoji: '🍄', success: ['1', '2', '3', '4'], failure: ['0'] },
      },
      role_mapping: {
        architect: ['star_wars'],
        developer: ['mario'],
      },
      critical_failure_villains: [
        { name: 'Vader', franchise: 'star_wars', severity: 'high', line: '...' },
      ],
    };
    expect(Object.keys(eggs.franchises)).toHaveLength(2);
    expect(eggs.role_mapping.architect).toEqual(['star_wars']);
  });

  it('accepts a FeatureGroup (no waves field)', () => {
    const group: FeatureGroup = {
      feature: 'F01',
      runs: [],
    };
    expect(group.runs).toEqual([]);
  });

  it('accepts an OverviewStats literal', () => {
    const stats: OverviewStats = {
      activeFeatures: 1,
      running: 2,
      completed: 3,
      failed: 0,
    };
    expect(stats.activeFeatures + stats.running + stats.completed + stats.failed).toBe(6);
  });
});
