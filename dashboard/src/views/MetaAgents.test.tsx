import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { render, screen, waitFor } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { MetaAgents } from './MetaAgents';
import type { MetaMetricsReport } from '@/lib/metaTypes';

const fullReport: MetaMetricsReport = {
  generated_at: '2026-04-11T10:00:00Z',
  gandalf: {
    total_decisions: 4,
    avg_latency_secs: 100,
    min_latency_secs: 40,
    avg_options_considered: 2.5,
    min_options_considered: 1,
    type_distribution: { wave_proceed: 3, block: 1 },
    status_distribution: { executed: 3, blocked: 1 },
    avg_actions_per_decision: 1.75,
  },
  saruman: {
    total_reviews: 4,
    verdict_distribution: { agree: 2, challenge: 1, escalate: 1 },
    verdict_rates: { agree: 0.5, challenge: 0.25, escalate: 0.25 },
    bias_frequency: {
      sunk_cost: 1,
      anchoring: 0,
      scope_creep: 2,
      optimism: 0,
      recency: 1,
    },
    avg_confidence: 0.82,
    avg_blind_spots: 1.5,
    avg_risks: 2,
    avg_decision_to_governance_latency_secs: 25,
  },
  loop_health: {
    challenge_round_trips: 3,
    blocking_escalations: 0,
    auto_reviewed_pct: 0.6,
    decisions_without_governance: 1,
  },
};

const emptySeedReport: MetaMetricsReport = {
  generated_at: '',
  gandalf: {} as MetaMetricsReport['gandalf'],
  saruman: {} as MetaMetricsReport['saruman'],
  loop_health: {} as MetaMetricsReport['loop_health'],
};

function makeClient(seed?: MetaMetricsReport) {
  const client = new QueryClient({
    defaultOptions: {
      queries: { retry: false, refetchInterval: false, staleTime: Infinity },
    },
  });
  if (seed) {
    client.setQueryData(['didio-meta-metrics'], seed);
  }
  return client;
}

function renderWith(client: QueryClient) {
  return render(
    <QueryClientProvider client={client}>
      <MetaAgents />
    </QueryClientProvider>,
  );
}

beforeEach(() => {
  vi.stubGlobal(
    'fetch',
    vi.fn().mockResolvedValue({
      ok: true,
      status: 200,
      json: async () => fullReport,
    }),
  );
});

afterEach(() => {
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
});

describe('MetaAgents', () => {
  it('happy: renders all three KPI sections with values from a full report', () => {
    renderWith(makeClient(fullReport));

    expect(screen.getByTestId('gandalf-section')).toBeInTheDocument();
    expect(screen.getByTestId('gandalf-total-decisions')).toHaveTextContent('4');
    expect(screen.getByTestId('gandalf-avg-latency')).toHaveTextContent('100');
    expect(screen.getByTestId('gandalf-type-distribution')).toHaveTextContent(
      'wave_proceed',
    );

    expect(screen.getByTestId('saruman-section')).toBeInTheDocument();
    expect(screen.getByTestId('saruman-total-reviews')).toHaveTextContent('4');
    expect(screen.getByTestId('saruman-verdict-agree')).toHaveTextContent('2');
    expect(screen.getByTestId('saruman-verdict-agree')).toHaveTextContent('50.0%');
    expect(screen.getByTestId('saruman-bias-frequency')).toHaveTextContent(
      'scope_creep',
    );

    expect(screen.getByTestId('loop-health-section')).toBeInTheDocument();
    expect(screen.getByTestId('loop-challenge-round-trips')).toHaveTextContent(
      '3',
    );
    expect(screen.getByTestId('loop-auto-reviewed-pct')).toHaveTextContent(
      '60.0%',
    );
  });

  it('edge: empty seed (gandalf/saruman/loop_health = {}) renders — and zeros without crashing', () => {
    renderWith(makeClient(emptySeedReport));

    expect(screen.getByTestId('gandalf-total-decisions')).toHaveTextContent('—');
    expect(screen.getByTestId('gandalf-avg-latency')).toHaveTextContent('—');
    expect(screen.getByTestId('gandalf-type-distribution')).toHaveTextContent(
      'No data',
    );

    expect(screen.getByTestId('saruman-total-reviews')).toHaveTextContent('—');
    expect(screen.getByTestId('saruman-verdict-agree')).toHaveTextContent('—');
    expect(screen.getByTestId('saruman-bias-frequency')).toHaveTextContent(
      'sunk_cost',
    );

    expect(screen.getByTestId('loop-challenge-round-trips')).toHaveTextContent(
      '—',
    );
    expect(screen.getByTestId('loop-auto-reviewed-pct')).toHaveTextContent('—');
  });

  it('error: fetch failure renders an error state', async () => {
    (globalThis.fetch as unknown as ReturnType<typeof vi.fn>).mockResolvedValue({
      ok: false,
      status: 404,
      json: async () => ({}),
    });
    const client = new QueryClient({
      defaultOptions: { queries: { retry: false } },
    });
    render(
      <QueryClientProvider client={client}>
        <MetaAgents />
      </QueryClientProvider>,
    );

    await waitFor(() =>
      expect(screen.getByTestId('meta-agents-error')).toBeInTheDocument(),
    );
    expect(screen.getByTestId('meta-agents-error')).toHaveTextContent(
      'meta-metrics.json 404',
    );
  });

  it('boundary: a verdict count of 0 renders explicitly, not as —', () => {
    const zeroVerdictReport: MetaMetricsReport = {
      ...fullReport,
      saruman: {
        ...fullReport.saruman,
        verdict_distribution: { agree: 4, challenge: 0, escalate: 0 },
        verdict_rates: { agree: 1, challenge: 0, escalate: 0 },
      },
    };
    renderWith(makeClient(zeroVerdictReport));

    expect(screen.getByTestId('saruman-verdict-challenge')).toHaveTextContent(
      '0',
    );
    expect(screen.getByTestId('saruman-verdict-challenge')).not.toHaveTextContent(
      '—',
    );
  });
});
