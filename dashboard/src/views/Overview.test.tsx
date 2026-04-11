import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { render, screen, waitFor } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import type { ReactNode } from 'react';
import { Overview } from './Overview';
import type { AgentRun, DidioState } from '@/lib/types';

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

const sixRunFixture: DidioState = {
  generated_at: '2026-04-11T10:00:00Z',
  agents: [
    run({
      task: 'F01-T01',
      role: 'architect',
      status: 'completed',
      started_at: '2026-04-11T08:00:00Z',
      phrase: 'I have a bad feeling about this.',
    }),
    run({
      task: 'F01-T02',
      role: 'developer',
      status: 'completed',
      started_at: '2026-04-11T08:10:00Z',
    }),
    run({
      task: 'F01-T03',
      role: 'qa',
      status: 'completed',
      started_at: '2026-04-11T08:20:00Z',
    }),
    run({
      task: 'F01-T04',
      role: 'developer',
      status: 'running',
      started_at: '2026-04-11T08:30:00Z',
    }),
    run({
      feature: 'F02',
      task: 'F02-T01',
      role: 'reviewer',
      status: 'running',
      started_at: '2026-04-11T08:40:00Z',
    }),
    run({
      feature: 'F02',
      task: 'F02-T02',
      role: 'developer',
      status: 'failed',
      started_at: '2026-04-11T08:50:00Z',
      phrase: 'Houston, we have a problem.',
    }),
  ],
};

function makeClient(seed?: DidioState, opts?: { error?: Error }) {
  const client = new QueryClient({
    defaultOptions: {
      queries: { retry: false, refetchInterval: false, staleTime: Infinity },
    },
  });
  if (opts?.error) {
    client.setQueryData(['didio-state'], undefined);
    client.setQueryDefaults(['didio-state'], {
      queryFn: () => Promise.reject(opts.error),
      retry: false,
    });
  } else if (seed) {
    client.setQueryData(['didio-state'], seed);
  }
  return client;
}

function renderWith(client: QueryClient): ReactNode {
  return render(
    <QueryClientProvider client={client}>
      <Overview />
    </QueryClientProvider>,
  ) as unknown as ReactNode;
}

beforeEach(() => {
  vi.stubGlobal(
    'fetch',
    vi.fn().mockResolvedValue({
      ok: true,
      status: 200,
      json: async () => sixRunFixture,
    }),
  );
});

afterEach(() => {
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
});

describe('Overview', () => {
  it('happy: 6-run fixture renders 2 running, 3 completed, 1 failed', () => {
    renderWith(makeClient(sixRunFixture));

    expect(screen.getByTestId('card-active-features')).toHaveTextContent('2');
    expect(screen.getByTestId('card-running')).toHaveTextContent('2');
    expect(screen.getByTestId('card-completed')).toHaveTextContent('3');
    expect(screen.getByTestId('card-failed')).toHaveTextContent('1');

    expect(screen.getByTestId('latest-phrase-card')).toHaveTextContent(
      'Houston, we have a problem.',
    );
    expect(screen.getByTestId('latest-phrase-card')).toHaveTextContent(
      /developer/i,
    );

    const pills = screen.getAllByTestId('timeline-pill');
    expect(pills).toHaveLength(6);
  });

  it('edge: empty agents → all cards show 0 and phrase placeholder', () => {
    const empty: DidioState = { generated_at: 'x', agents: [] };
    renderWith(makeClient(empty));

    expect(screen.getByTestId('card-active-features')).toHaveTextContent('0');
    expect(screen.getByTestId('card-running')).toHaveTextContent('0');
    expect(screen.getByTestId('card-completed')).toHaveTextContent('0');
    expect(screen.getByTestId('card-failed')).toHaveTextContent('0');
    expect(screen.getByTestId('latest-phrase-card')).toHaveTextContent(
      /no phrases yet/i,
    );
    expect(screen.queryAllByTestId('timeline-pill')).toHaveLength(0);
  });

  it('error: query in error state renders error banner', async () => {
    (globalThis.fetch as unknown as ReturnType<typeof vi.fn>).mockResolvedValue({
      ok: false,
      status: 500,
      json: async () => ({}),
    });
    const client = new QueryClient({
      defaultOptions: { queries: { retry: false } },
    });
    render(
      <QueryClientProvider client={client}>
        <Overview />
      </QueryClientProvider>,
    );
    await waitFor(() =>
      expect(screen.getByTestId('overview-error')).toBeInTheDocument(),
    );
    expect(screen.getByTestId('overview-error')).toHaveTextContent(/500/);
  });

  it('boundary: 100 runs → only last 20 rendered in timeline', () => {
    const many: DidioState = {
      generated_at: 'x',
      agents: Array.from({ length: 100 }, (_, i) =>
        run({
          task: `F01-T${String(i).padStart(3, '0')}`,
          started_at: `2026-04-11T${String(Math.floor(i / 60)).padStart(
            2,
            '0',
          )}:${String(i % 60).padStart(2, '0')}:00Z`,
        }),
      ),
    };
    renderWith(makeClient(many));
    const pills = screen.getAllByTestId('timeline-pill');
    expect(pills).toHaveLength(20);
    // The last pill should correspond to task index 99
    expect(pills[pills.length - 1]).toHaveTextContent('F01-T099');
    // The first of the 20 should be index 80 (off-by-one guard)
    expect(pills[0]).toHaveTextContent('F01-T080');
  });

  it('shows skeleton while loading (no cached data)', () => {
    const client = new QueryClient({
      defaultOptions: { queries: { retry: false } },
    });
    render(
      <QueryClientProvider client={client}>
        <Overview />
      </QueryClientProvider>,
    );
    expect(screen.getByTestId('overview-skeleton')).toBeInTheDocument();
  });
});
