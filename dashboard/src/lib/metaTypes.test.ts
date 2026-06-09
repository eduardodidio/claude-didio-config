import { describe, it, expect } from 'vitest';
import { isVerdict } from './metaTypes';
import type {
  DecisionRecord,
  GovernanceReport,
  MetaRunState,
  GandalfKpis,
  SarumanKpis,
  LoopHealthKpis,
  MetaMetricsReport,
} from './metaTypes';

describe('metaTypes', () => {
  it('accepts a literal satisfying DecisionRecord', () => {
    const decision: DecisionRecord = {
      decision_id: 'D-20260101-001',
      type: 'wave_proceed',
      options_considered: ['proceed', 'block'],
      decision: 'proceed',
      rationale: 'all gates green',
      actions: ['notify-team'],
      status: 'executed',
    };

    expect(decision.type).toBe('wave_proceed');
  });

  it('accepts a literal satisfying GovernanceReport', () => {
    const report: GovernanceReport = {
      decision_id: 'D-20260101-001',
      verdict: 'agree',
      bias_check: {
        sunk_cost: false,
        anchoring: true,
        scope_creep: false,
        optimism: false,
        recency: false,
      },
      blind_spots: ['no rollback plan'],
      risks: ['latency regression'],
      recommendation: 'proceed with monitoring',
      confidence: 0.85,
    };

    expect(report.verdict).toBe('agree');
  });

  it('accepts a literal satisfying MetaRunState', () => {
    const run: MetaRunState = {
      role: 't800',
      task: 'D-20260101-001',
      started_at: '2026-01-01T00:00:00Z',
      finished_at: '2026-01-01T00:05:00Z',
      exit_code: 0,
      status: 'completed',
    };

    expect(run.role).toBe('t800');
  });

  it('accepts a literal satisfying MetaMetricsReport', () => {
    const gandalf: GandalfKpis = {
      total_decisions: 3,
      avg_latency_secs: 120,
      min_latency_secs: 60,
      avg_options_considered: 2,
      min_options_considered: 1,
      type_distribution: { wave_proceed: 2, block: 1 },
      status_distribution: { executed: 2, blocked: 1 },
      avg_actions_per_decision: 1.5,
    };

    const saruman: SarumanKpis = {
      total_reviews: 3,
      verdict_distribution: { agree: 1, challenge: 1, escalate: 1 },
      verdict_rates: { agree: 1 / 3, challenge: 1 / 3, escalate: 1 / 3 },
      bias_frequency: {
        sunk_cost: 1,
        anchoring: 0,
        scope_creep: 0,
        optimism: 0,
        recency: 0,
      },
      avg_confidence: 0.8,
      avg_blind_spots: 1,
      avg_risks: 1,
      avg_decision_to_governance_latency_secs: 30,
    };

    const loopHealth: LoopHealthKpis = {
      challenge_round_trips: 1,
      blocking_escalations: 1,
      auto_reviewed_pct: 0.5,
      decisions_without_governance: 0,
    };

    const report: MetaMetricsReport = {
      generated_at: '2026-01-01T00:00:00Z',
      gandalf,
      saruman,
      loop_health: loopHealth,
    };

    expect(report.gandalf.total_decisions).toBe(3);
  });

  it('boundary: confidence accepts 0 and 1', () => {
    const low: GovernanceReport = {
      verdict: 'challenge',
      bias_check: {
        sunk_cost: false,
        anchoring: false,
        scope_creep: false,
        optimism: false,
        recency: false,
      },
      blind_spots: [],
      risks: [],
      recommendation: 'reconsider',
      confidence: 0,
    };
    const high: GovernanceReport = { ...low, confidence: 1, verdict: 'escalate' };

    expect(low.confidence).toBe(0);
    expect(high.confidence).toBe(1);
  });

  it('isVerdict returns true for known verdicts', () => {
    expect(isVerdict('agree')).toBe(true);
    expect(isVerdict('challenge')).toBe(true);
    expect(isVerdict('escalate')).toBe(true);
  });

  it('isVerdict returns false for an unknown verdict string', () => {
    expect(isVerdict('x')).toBe(false);
  });
});
