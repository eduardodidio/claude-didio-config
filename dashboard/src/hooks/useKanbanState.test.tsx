import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { render, screen, waitFor } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { useKanbanState } from './useKanbanState';
import type { DidioState } from '@/lib/types';
import type { AgentFlag, PipelineStatus } from '@/lib/kanbanTypes';

// ---------------------------------------------------------------------------
// Probe component
// ---------------------------------------------------------------------------

function Probe() {
  const { data, isLoading, isError } = useKanbanState();
  if (isLoading) return <div>loading</div>;
  if (isError) return <div>error</div>;
  if (!data) return <div>no-data</div>;
  return (
    <div>
      <span data-testid="card-count">{data.cards.length}</span>
      {data.cards.map((c) => (
        <span key={c.feature} data-testid={`col-${c.feature}`}>
          {c.column}
        </span>
      ))}
      {data.cards
        .filter((c) => c.isBlocked)
        .map((c) => (
          <span key={c.feature} data-testid={`blocked-${c.feature}`}>
            blocked
          </span>
        ))}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const didioFixture: DidioState = {
  generated_at: '2026-11-01T10:00:00Z',
  agents: [
    {
      feature: 'F01',
      role: 'developer',
      task: 'F01-T03',
      task_file: 'tasks/features/F01/F01-T03.md',
      started_at: '2026-11-01T09:00:00Z',
      finished_at: null,
      status: 'running',
      exit_code: null,
      pid: 1,
      log: 'logs/agents/F01-T03.jsonl',
      phrase: null,
    },
  ],
  features: [
    {
      feature: 'F01',
      total: 10,
      completed: 5,
      running: 1,
      failed: 0,
      percent: 50,
      current_wave: 1,
      current_task: 'F01-T03',
      trail: [],
    },
    {
      feature: 'F02',
      total: 4,
      completed: 4,
      running: 0,
      failed: 0,
      percent: 100,
      current_wave: null,
      current_task: null,
      trail: [],
    },
  ],
};

const flagsFixture: AgentFlag[] = [
  {
    flag_id: 'f1',
    type: 'blocked',
    feature: 'F01',
    task: 'F01-T03',
    severity: 'critical',
    reason: 'dep missing',
    suggested_actions: [],
    created_at: '2026-11-01T10:00:00Z',
    resolved_at: null,
  },
];

// ---------------------------------------------------------------------------
// Helper: seed query cache directly to avoid fetchState normalization
// ---------------------------------------------------------------------------

function makeSeededClient(
  didio: DidioState,
  flags: AgentFlag[] = [],
  pipelines: PipelineStatus[] = [],
) {
  const client = new QueryClient({
    defaultOptions: { queries: { retry: false, refetchInterval: false, staleTime: Infinity } },
  });
  // Seed the three queries that useKanbanState depends on
  client.setQueryData(['didio-state'], didio);
  client.setQueryData(['kanban-flags'], flags);
  client.setQueryData(['kanban-pipeline'], pipelines);
  return client;
}

function renderWith(client: QueryClient) {
  return render(
    <QueryClientProvider client={client}>
      <Probe />
    </QueryClientProvider>,
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe('useKanbanState', () => {
  it('derives correct board state from merged data sources', () => {
    const client = makeSeededClient(didioFixture, flagsFixture);
    renderWith(client);
    expect(screen.getByTestId('card-count')).toHaveTextContent('2');
  });

  it('maps features to correct columns', () => {
    const client = makeSeededClient(didioFixture, []);
    renderWith(client);
    // F01: running developer -> RUNNING
    expect(screen.getByTestId('col-F01')).toHaveTextContent('RUNNING');
    // F02: 100% -> DONE
    expect(screen.getByTestId('col-F02')).toHaveTextContent('DONE');
  });

  it('marks blocked features correctly', () => {
    const client = makeSeededClient(didioFixture, flagsFixture);
    renderWith(client);
    expect(screen.getByTestId('blocked-F01')).toHaveTextContent('blocked');
  });

  it('handles missing pipeline state gracefully', () => {
    // No pipeline data seeded, but didio and flags are present
    const client = makeSeededClient(didioFixture, []);
    renderWith(client);
    expect(screen.getByTestId('card-count')).toHaveTextContent('2');
  });

  it('returns no-data when didio state is not available', () => {
    const client = new QueryClient({
      defaultOptions: { queries: { retry: false, refetchInterval: false, staleTime: Infinity } },
    });
    // Only seed flags and pipeline, not didio-state
    client.setQueryData(['kanban-flags'], []);
    client.setQueryData(['kanban-pipeline'], []);
    renderWith(client);
    // useKanbanState returns null boardState when didioQuery.data is missing
    // The component should show loading or no-data
    expect(
      screen.getByText('loading') || screen.getByText('no-data'),
    ).toBeInTheDocument();
  });
});
