import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { render, screen, waitFor } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { useFlags } from './useFlags';

const sampleFlags = [
  {
    flag_id: 'f1',
    type: 'blocked',
    feature: 'F01',
    task: null,
    severity: 'critical',
    reason: 'dependency missing',
    suggested_actions: ['auto_resolve'],
    created_at: '2026-11-01T10:00:00Z',
    resolved_at: null,
  },
];

function Probe() {
  const q = useFlags();
  if (q.isLoading) return <div>loading</div>;
  if (q.error) return <div>error: {(q.error as Error).message}</div>;
  return <div>flags:{q.data?.length ?? 0}</div>;
}

function renderWithClient() {
  const client = new QueryClient({
    defaultOptions: { queries: { retry: false, refetchInterval: false } },
  });
  return render(
    <QueryClientProvider client={client}>
      <Probe />
    </QueryClientProvider>,
  );
}

describe('useFlags', () => {
  beforeEach(() => {
    vi.stubGlobal('fetch', vi.fn());
  });

  afterEach(() => {
    vi.unstubAllGlobals();
    vi.restoreAllMocks();
  });

  it('returns flag data on successful fetch', async () => {
    (globalThis.fetch as ReturnType<typeof vi.fn>).mockResolvedValue({
      ok: true,
      json: async () => sampleFlags,
    });

    renderWithClient();
    expect(screen.getByText('loading')).toBeInTheDocument();
    await waitFor(() =>
      expect(screen.getByText('flags:1')).toBeInTheDocument(),
    );
  });

  it('returns error on failed fetch', async () => {
    (globalThis.fetch as ReturnType<typeof vi.fn>).mockResolvedValue({
      ok: false,
      status: 500,
    });

    renderWithClient();
    await waitFor(() =>
      expect(screen.getByText(/error: flags.json 500/)).toBeInTheDocument(),
    );
  });
});
