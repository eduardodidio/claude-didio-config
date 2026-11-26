import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { render, screen, waitFor } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { Governance } from './Governance';
import type { DidioState } from '@/lib/types';
import type { PipelineStatus, AgentFlag } from '@/lib/kanbanTypes';
import type { MetaMetricsReport } from '@/lib/metaTypes';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const didioFixture: DidioState = {
  generated_at: '2026-11-01T10:00:00Z',
  agents: [],
  features: [
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
  ],
};

const pipelinesFixture: PipelineStatus[] = [
  {
    feature: 'F01',
    phase: 'wave_1',
    started_at: '2026-11-01T08:00:00Z',
    token_budget_used: 5000,
    token_budget_total: 10000,
    agent_count: 2,
    current_wave: 1,
  },
];

const flagsFixture: AgentFlag[] = [
  {
    flag_id: 'f1',
    type: 'blocked',
    feature: 'F01',
    task: null,
    severity: 'critical',
    reason: 'test',
    suggested_actions: [],
    created_at: '2026-11-01T10:00:00Z',
    resolved_at: null,
  },
];

const metaFixture: MetaMetricsReport = {
  generated_at: '2026-11-01T10:00:00Z',
  handler: {
    total_decisions: 3,
    avg_latency_secs: 60,
    min_latency_secs: 30,
    avg_options_considered: 2,
    min_options_considered: 1,
    type_distribution: { wave_proceed: 3 },
    status_distribution: { executed: 3 },
    avg_actions_per_decision: 1,
  },
  gatekeeper: {
    total_reviews: 2,
    verdict_distribution: { agree: 2, challenge: 0, escalate: 0 },
    verdict_rates: { agree: 1, challenge: 0, escalate: 0 },
    bias_frequency: { sunk_cost: 0, anchoring: 0, scope_creep: 0, optimism: 0, recency: 0 },
    avg_confidence: 0.95,
    avg_blind_spots: 0,
    avg_risks: 0,
    avg_decision_to_governance_latency_secs: 5,
  },
  loop_health: {
    challenge_round_trips: 0,
    blocking_escalations: 0,
    auto_reviewed_pct: 1,
    decisions_without_governance: 0,
  },
};

function makeSeededClient(
  didio: DidioState = didioFixture,
  flags: AgentFlag[] = flagsFixture,
  pipelines: PipelineStatus[] = pipelinesFixture,
  meta: MetaMetricsReport = metaFixture,
) {
  const client = new QueryClient({
    defaultOptions: { queries: { retry: false, refetchInterval: false, staleTime: Infinity } },
  });
  client.setQueryData(['didio-state'], didio);
  client.setQueryData(['kanban-flags'], flags);
  client.setQueryData(['kanban-pipeline'], pipelines);
  client.setQueryData(['meta-metrics'], meta);
  return client;
}

function renderGovernance(client?: QueryClient) {
  const qc = client ?? makeSeededClient();
  return render(
    <QueryClientProvider client={qc}>
      <Governance />
    </QueryClientProvider>,
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe('Governance', () => {
  beforeEach(() => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue({
      ok: true,
      json: async () => [],
    }));
  });

  afterEach(() => {
    vi.unstubAllGlobals();
    vi.restoreAllMocks();
  });

  it('renders all 4 sections', () => {
    renderGovernance();
    expect(screen.getByTestId('governance-view')).toBeInTheDocument();
    expect(screen.getByTestId('pipelines-section')).toBeInTheDocument();
    expect(screen.getByTestId('token-budget-section')).toBeInTheDocument();
    expect(screen.getByTestId('flag-analytics-section')).toBeInTheDocument();
    expect(screen.getByTestId('decision-history-section')).toBeInTheDocument();
  });

  it('shows loading skeleton when no data is cached', () => {
    const client = new QueryClient({
      defaultOptions: { queries: { retry: false, refetchInterval: false } },
    });
    vi.stubGlobal('fetch', vi.fn().mockReturnValue(new Promise(() => {})));
    renderGovernance(client);
    expect(screen.getByTestId('governance-skeleton')).toBeInTheDocument();
  });

  it('handles missing data gracefully', () => {
    const emptyDidio: DidioState = {
      generated_at: '2026-11-01T10:00:00Z',
      agents: [],
      features: [],
    };
    const emptyMeta: MetaMetricsReport = {
      generated_at: '2026-11-01T10:00:00Z',
      handler: {
        total_decisions: 0,
        avg_latency_secs: 0,
        min_latency_secs: 0,
        avg_options_considered: 0,
        min_options_considered: 0,
        type_distribution: {},
        status_distribution: {},
        avg_actions_per_decision: 0,
      },
      gatekeeper: {
        total_reviews: 0,
        verdict_distribution: { agree: 0, challenge: 0, escalate: 0 },
        verdict_rates: { agree: 0, challenge: 0, escalate: 0 },
        bias_frequency: { sunk_cost: 0, anchoring: 0, scope_creep: 0, optimism: 0, recency: 0 },
        avg_confidence: 0,
        avg_blind_spots: 0,
        avg_risks: 0,
        avg_decision_to_governance_latency_secs: 0,
      },
      loop_health: {
        challenge_round_trips: 0,
        blocking_escalations: 0,
        auto_reviewed_pct: 0,
        decisions_without_governance: 0,
      },
    };
    renderGovernance(makeSeededClient(emptyDidio, [], [], emptyMeta));
    expect(screen.getByTestId('governance-view')).toBeInTheDocument();
    expect(screen.getByTestId('pipelines-section')).toBeInTheDocument();
    expect(screen.getByTestId('token-budget-section')).toBeInTheDocument();
    expect(screen.getByTestId('flag-analytics-section')).toBeInTheDocument();
    expect(screen.getByTestId('decision-history-section')).toBeInTheDocument();
  });
});
