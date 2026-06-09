import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { fetchMetaMetrics } from './fetchMetaMetrics';
import type { MetaMetricsReport } from './metaTypes';

const sampleReport: MetaMetricsReport = {
  generated_at: '2026-04-11T10:00:00Z',
  gandalf: {
    total_decisions: 3,
    avg_latency_secs: 120,
    min_latency_secs: 60,
    avg_options_considered: 2,
    min_options_considered: 1,
    type_distribution: { wave_proceed: 2, block: 1 },
    status_distribution: { executed: 2, blocked: 1 },
    avg_actions_per_decision: 1.5,
  },
  saruman: {
    total_reviews: 3,
    verdict_distribution: { agree: 1, challenge: 1, escalate: 1 },
    verdict_rates: { agree: 1 / 3, challenge: 1 / 3, escalate: 1 / 3 },
    bias_frequency: {
      sunk_cost: 1,
      anchoring: 0,
      scope_creep: 0,
      optimism: 1,
      recency: 0,
    },
    avg_confidence: 0.8,
    avg_blind_spots: 1.2,
    avg_risks: 1.5,
    avg_decision_to_governance_latency_secs: 30,
  },
  loop_health: {
    challenge_round_trips: 2,
    blocking_escalations: 1,
    auto_reviewed_pct: 0.75,
    decisions_without_governance: 0,
  },
};

describe('fetchMetaMetrics', () => {
  beforeEach(() => {
    vi.stubGlobal('fetch', vi.fn());
  });
  afterEach(() => {
    vi.unstubAllGlobals();
    vi.restoreAllMocks();
  });

  it('resolves with typed MetaMetricsReport on 200', async () => {
    (globalThis.fetch as unknown as ReturnType<typeof vi.fn>).mockResolvedValue({
      ok: true,
      status: 200,
      json: async () => sampleReport,
    });
    const result = await fetchMetaMetrics();
    expect(result.gandalf.total_decisions).toBe(3);
    expect(result.saruman.total_reviews).toBe(3);
    expect(result.loop_health.challenge_round_trips).toBe(2);
    expect(globalThis.fetch).toHaveBeenCalledWith('./meta-metrics.json', {
      cache: 'no-store',
    });
  });

  it('tolerates the empty seed (gandalf/saruman/loop_health = {})', async () => {
    (globalThis.fetch as unknown as ReturnType<typeof vi.fn>).mockResolvedValue({
      ok: true,
      status: 200,
      json: async () => ({
        generated_at: '',
        gandalf: {},
        saruman: {},
        loop_health: {},
      }),
    });
    const result = await fetchMetaMetrics();
    expect(result.generated_at).toBe('');
    expect(result.gandalf).toEqual({});
    expect(result.saruman).toEqual({});
    expect(result.loop_health).toEqual({});
  });

  it('throws on non-ok response', async () => {
    (globalThis.fetch as unknown as ReturnType<typeof vi.fn>).mockResolvedValue({
      ok: false,
      status: 500,
      json: async () => ({}),
    });
    await expect(fetchMetaMetrics()).rejects.toThrow('meta-metrics.json 500');
  });

  it('throws on 404', async () => {
    (globalThis.fetch as unknown as ReturnType<typeof vi.fn>).mockResolvedValue({
      ok: false,
      status: 404,
      json: async () => ({}),
    });
    await expect(fetchMetaMetrics()).rejects.toThrow('meta-metrics.json 404');
  });
});
