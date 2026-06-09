import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { render, screen, waitFor } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { useMetaMetrics } from './useMetaMetrics';
import type { MetaMetricsReport } from '@/lib/metaTypes';

const sampleReport: MetaMetricsReport = {
  generated_at: '2026-04-11T10:00:00Z',
  gandalf: {
    total_decisions: 5,
    avg_latency_secs: 90,
    min_latency_secs: 30,
    avg_options_considered: 3,
    min_options_considered: 1,
    type_distribution: { wave_proceed: 5 },
    status_distribution: { executed: 5 },
    avg_actions_per_decision: 2,
  },
  saruman: {
    total_reviews: 5,
    verdict_distribution: { agree: 5, challenge: 0, escalate: 0 },
    verdict_rates: { agree: 1, challenge: 0, escalate: 0 },
    bias_frequency: {
      sunk_cost: 0,
      anchoring: 0,
      scope_creep: 0,
      optimism: 0,
      recency: 0,
    },
    avg_confidence: 0.9,
    avg_blind_spots: 0.5,
    avg_risks: 0.5,
    avg_decision_to_governance_latency_secs: 10,
  },
  loop_health: {
    challenge_round_trips: 0,
    blocking_escalations: 0,
    auto_reviewed_pct: 1,
    decisions_without_governance: 0,
  },
};

function Probe() {
  const q = useMetaMetrics();
  if (q.isLoading) return <div>loading</div>;
  if (q.error) return <div>error: {(q.error as Error).message}</div>;
  return <div>decisions:{q.data?.gandalf.total_decisions ?? 0}</div>;
}

function renderWithClient() {
  const client = new QueryClient({
    defaultOptions: { queries: { retry: false } },
  });
  return render(
    <QueryClientProvider client={client}>
      <Probe />
    </QueryClientProvider>,
  );
}

describe('useMetaMetrics', () => {
  beforeEach(() => {
    vi.stubGlobal('fetch', vi.fn());
  });
  afterEach(() => {
    vi.unstubAllGlobals();
    vi.restoreAllMocks();
  });

  it('transitions from loading to data', async () => {
    (globalThis.fetch as unknown as ReturnType<typeof vi.fn>).mockResolvedValue({
      ok: true,
      status: 200,
      json: async () => sampleReport,
    });
    renderWithClient();
    expect(screen.getByText('loading')).toBeInTheDocument();
    await waitFor(() =>
      expect(screen.getByText('decisions:5')).toBeInTheDocument(),
    );
  });

  it('enters error state on fetch failure (404)', async () => {
    (globalThis.fetch as unknown as ReturnType<typeof vi.fn>).mockResolvedValue({
      ok: false,
      status: 404,
      json: async () => ({}),
    });
    renderWithClient();
    await waitFor(() =>
      expect(
        screen.getByText(/error: meta-metrics.json 404/),
      ).toBeInTheDocument(),
    );
  });
});
