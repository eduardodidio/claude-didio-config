import { describe, it, expect } from 'vitest';
import { computeMetaMetrics } from './metaMetrics';
import type { DecisionRecord, GovernanceReport, MetaRunState } from './metaTypes';

import d001 from '../test/fixtures/meta/decisions/D-20260101-001.json';
import d002 from '../test/fixtures/meta/decisions/D-20260101-002.json';
import d003 from '../test/fixtures/meta/decisions/D-20260101-003.json';
import d004 from '../test/fixtures/meta/decisions/D-20260101-004.json';
import g001 from '../test/fixtures/meta/governance/G-D-20260101-001.json';
import g002 from '../test/fixtures/meta/governance/G-D-20260101-002.json';
import g003 from '../test/fixtures/meta/governance/G-D-20260101-003.json';
import g004 from '../test/fixtures/meta/governance/G-D-20260101-004.json';
import stateFixture from '../test/fixtures/meta/state.json';

const NOW = '2026-01-01T02:00:00Z';

const decisions = [d001, d002, d003, d004] as unknown as DecisionRecord[];
const governance = [g001, g002, g003, g004] as unknown as GovernanceReport[];
const runs = stateFixture.agents as unknown as MetaRunState[];

describe('computeMetaMetrics', () => {
  it('happy path: full fixture corpus matches the documented answer key', () => {
    const report = computeMetaMetrics({ decisions, governance, runs, now: NOW });

    expect(report.generated_at).toBe(NOW);

    expect(report.gandalf).toEqual({
      total_decisions: 4,
      avg_latency_secs: 165.0,
      min_latency_secs: 120,
      avg_options_considered: 2.5,
      min_options_considered: 1,
      type_distribution: {
        feature_start: 1,
        wave_proceed: 1,
        quality_gate: 1,
        block: 1,
      },
      status_distribution: { executed: 2, partial: 1, blocked: 1 },
      avg_actions_per_decision: 3.0,
    });

    expect(report.saruman).toEqual({
      total_reviews: 4,
      verdict_distribution: { agree: 2, challenge: 1, escalate: 1 },
      verdict_rates: { agree: 0.5, challenge: 0.25, escalate: 0.25 },
      bias_frequency: {
        sunk_cost: 2,
        anchoring: 1,
        scope_creep: 1,
        optimism: 1,
        recency: 1,
      },
      avg_confidence: 0.7,
      avg_blind_spots: 2.0,
      avg_risks: 2.0,
      avg_decision_to_governance_latency_secs: 60.0,
    });

    expect(report.loop_health).toEqual({
      challenge_round_trips: 1,
      blocking_escalations: 1,
      auto_reviewed_pct: 1.0,
      decisions_without_governance: 0,
    });
  });

  it('AC3: exit_code 2 on the t800 run does not exclude D-20260101-004 from KPIs', () => {
    const report = computeMetaMetrics({ decisions, governance, runs, now: NOW });

    expect(report.gandalf.total_decisions).toBe(4);
    expect(report.gandalf.type_distribution.block).toBe(1);
    expect(report.gandalf.min_latency_secs).toBe(120);
    expect(report.loop_health.decisions_without_governance).toBe(0);
  });

  it('edge: empty input yields all-zero counts and null averages, never NaN', () => {
    const report = computeMetaMetrics({
      decisions: [],
      governance: [],
      runs: [],
      now: NOW,
    });

    expect(report).toEqual({
      generated_at: NOW,
      gandalf: {
        total_decisions: 0,
        avg_latency_secs: null,
        min_latency_secs: null,
        avg_options_considered: null,
        min_options_considered: null,
        type_distribution: {},
        status_distribution: {},
        avg_actions_per_decision: null,
      },
      saruman: {
        total_reviews: 0,
        verdict_distribution: { agree: 0, challenge: 0, escalate: 0 },
        verdict_rates: { agree: 0, challenge: 0, escalate: 0 },
        bias_frequency: {
          sunk_cost: 0,
          anchoring: 0,
          scope_creep: 0,
          optimism: 0,
          recency: 0,
        },
        avg_confidence: null,
        avg_blind_spots: null,
        avg_risks: null,
        avg_decision_to_governance_latency_secs: null,
      },
      loop_health: {
        challenge_round_trips: 0,
        blocking_escalations: 0,
        auto_reviewed_pct: null,
        decisions_without_governance: 0,
      },
    });

    expect(Number.isNaN(report.gandalf.avg_latency_secs)).toBe(false);
    expect(Number.isNaN(report.saruman.avg_confidence)).toBe(false);
  });

  it('edge: a decision with no governance contributes to decisions_without_governance and is excluded from Saruman/loop joins', () => {
    const lonelyDecision: DecisionRecord = {
      ...d001,
      decision_id: 'D-20260101-099',
    } as DecisionRecord;
    const lonelyRun: MetaRunState = {
      role: 't800',
      task: 'D-20260101-099',
      started_at: '2026-01-01T01:00:00Z',
      finished_at: '2026-01-01T01:02:00Z',
      status: 'completed',
      exit_code: 0,
    };

    const report = computeMetaMetrics({
      decisions: [...decisions, lonelyDecision],
      governance,
      runs: [...runs, lonelyRun],
      now: NOW,
    });

    expect(report.loop_health.decisions_without_governance).toBe(1);
    expect(report.gandalf.total_decisions).toBe(5);
    // governance-side KPIs are unaffected by the ungoverned decision
    expect(report.saruman.total_reviews).toBe(4);
    expect(report.saruman.avg_decision_to_governance_latency_secs).toBe(60.0);
  });

  it('boundary: confidence at the 0/1 extremes and bias all-true vs all-false average correctly', () => {
    const allTrueBias: GovernanceReport = {
      decision_id: 'D-extreme-true',
      verdict: 'agree',
      bias_check: {
        sunk_cost: true,
        anchoring: true,
        scope_creep: true,
        optimism: true,
        recency: true,
      },
      blind_spots: [],
      risks: [],
      recommendation: 'n/a',
      confidence: 1,
    };
    const allFalseBias: GovernanceReport = {
      decision_id: 'D-extreme-false',
      verdict: 'agree',
      bias_check: {
        sunk_cost: false,
        anchoring: false,
        scope_creep: false,
        optimism: false,
        recency: false,
      },
      blind_spots: [],
      risks: [],
      recommendation: 'n/a',
      confidence: 0,
    };

    const report = computeMetaMetrics({
      decisions: [],
      governance: [allTrueBias, allFalseBias],
      runs: [],
      now: NOW,
    });

    expect(report.saruman.avg_confidence).toBe(0.5);
    expect(report.saruman.bias_frequency).toEqual({
      sunk_cost: 1,
      anchoring: 1,
      scope_creep: 1,
      optimism: 1,
      recency: 1,
    });
    expect(report.saruman.avg_blind_spots).toBe(0);
    expect(report.saruman.avg_risks).toBe(0);
  });

  it('boundary: a single decision produces non-null averages equal to its own values', () => {
    const report = computeMetaMetrics({
      decisions: [decisions[0]],
      governance: [governance[0]],
      runs: runs.filter((r) => r.task === 'D-20260101-001'),
      now: NOW,
    });

    expect(report.gandalf.total_decisions).toBe(1);
    expect(report.gandalf.avg_latency_secs).toBe(120);
    expect(report.gandalf.min_latency_secs).toBe(120);
    expect(report.gandalf.avg_options_considered).toBe(3);
    expect(report.gandalf.min_options_considered).toBe(3);
    expect(report.saruman.avg_decision_to_governance_latency_secs).toBe(60);
    expect(report.loop_health.auto_reviewed_pct).toBe(1.0);
  });
});
