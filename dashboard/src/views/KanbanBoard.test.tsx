import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { render, screen, waitFor } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { KanbanBoard } from './KanbanBoard';
import type { DidioState } from '@/lib/types';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const didioWithFeatures: DidioState = {
  generated_at: '2026-11-01T10:00:00Z',
  agents: [],
  features: [
    {
      feature: 'F01',
      total: 5,
      completed: 0,
      running: 0,
      failed: 0,
      percent: 0,
      current_wave: null,
      current_task: null,
      trail: [],
    },
    {
      feature: 'F02',
      total: 10,
      completed: 5,
      running: 1,
      failed: 0,
      percent: 50,
      current_wave: 1,
      current_task: 'F02-T05',
      trail: [],
    },
    {
      feature: 'F03',
      total: 8,
      completed: 8,
      running: 0,
      failed: 0,
      percent: 100,
      current_wave: null,
      current_task: null,
      trail: [],
    },
  ],
};

function makeSeededClient(didio: DidioState | null) {
  const client = new QueryClient({
    defaultOptions: { queries: { retry: false, refetchInterval: false, staleTime: Infinity } },
  });
  if (didio) {
    client.setQueryData(['didio-state'], didio);
  }
  client.setQueryData(['kanban-flags'], []);
  client.setQueryData(['kanban-pipeline'], []);
  return client;
}

function renderBoard(client?: QueryClient) {
  const qc = client ?? makeSeededClient(didioWithFeatures);
  return render(
    <QueryClientProvider client={qc}>
      <KanbanBoard />
    </QueryClientProvider>,
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe('KanbanBoard', () => {
  beforeEach(() => {
    // Stub fetch to prevent real network calls (some hooks may still try)
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue({
      ok: true,
      json: async () => [],
    }));
  });

  afterEach(() => {
    vi.unstubAllGlobals();
    vi.restoreAllMocks();
  });

  it('renders 5 columns when data is available', () => {
    renderBoard();
    expect(screen.getByTestId('kanban-board-view')).toBeInTheDocument();
    expect(screen.getByTestId('kanban-column-BACKLOG')).toBeInTheDocument();
    expect(screen.getByTestId('kanban-column-PLANNING')).toBeInTheDocument();
    expect(screen.getByTestId('kanban-column-RUNNING')).toBeInTheDocument();
    expect(screen.getByTestId('kanban-column-REVIEW')).toBeInTheDocument();
    expect(screen.getByTestId('kanban-column-DONE')).toBeInTheDocument();
  });

  it('shows loading skeleton when no data is cached', () => {
    const client = new QueryClient({
      defaultOptions: { queries: { retry: false, refetchInterval: false } },
    });
    // Stub fetch to never resolve so it stays in loading state
    vi.stubGlobal('fetch', vi.fn().mockReturnValue(new Promise(() => {})));
    renderBoard(client);
    expect(screen.getByTestId('kanban-board-skeleton')).toBeInTheDocument();
  });

  it('shows error alert on fetch failure', async () => {
    const client = new QueryClient({
      defaultOptions: { queries: { retry: false, refetchInterval: false } },
    });
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue({
      ok: false,
      status: 500,
    }));
    renderBoard(client);
    await waitFor(() =>
      expect(screen.getByTestId('kanban-board-error')).toBeInTheDocument(),
    );
  });

  it('shows empty state when no features exist', () => {
    const emptyDidio: DidioState = {
      generated_at: '2026-11-01T10:00:00Z',
      agents: [],
      features: [],
    };
    renderBoard(makeSeededClient(emptyDidio));
    expect(screen.getByTestId('kanban-board-empty')).toBeInTheDocument();
  });
});
