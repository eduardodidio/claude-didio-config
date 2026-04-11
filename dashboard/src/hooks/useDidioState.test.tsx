import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { render, screen, waitFor } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { useDidioState } from './useDidioState';
import type { DidioState } from '@/lib/types';

const sampleState: DidioState = {
  generated_at: '2026-04-11T10:00:00Z',
  agents: [
    {
      feature: 'F01',
      role: 'qa',
      task: 'F01-T06',
      task_file: 'tasks/features/F01-dashboard/F01-T06.md',
      started_at: '2026-04-11T09:00:00Z',
      finished_at: null,
      status: 'running',
      exit_code: null,
      pid: 42,
      log: 'logs/agents/F01-T06.jsonl',
      phrase: null,
    },
  ],
};

function Probe() {
  const q = useDidioState();
  if (q.isLoading) return <div>loading</div>;
  if (q.error) return <div>error: {(q.error as Error).message}</div>;
  return <div>agents:{q.data?.agents.length ?? 0}</div>;
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

describe('useDidioState', () => {
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
      json: async () => sampleState,
    });
    renderWithClient();
    expect(screen.getByText('loading')).toBeInTheDocument();
    await waitFor(() =>
      expect(screen.getByText('agents:1')).toBeInTheDocument(),
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
      expect(screen.getByText(/error: state.json 404/)).toBeInTheDocument(),
    );
  });
});
