import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { useActions } from './useActions';

function Probe() {
  const { dispatch, isPending, isError, error } = useActions();

  return (
    <div>
      <button
        onClick={() => dispatch('unblock', 'F01', 'F01-T01').catch(() => {})}
        disabled={isPending}
      >
        dispatch
      </button>
      {isPending && <span>pending</span>}
      {isError && <span>error:{(error as Error).message}</span>}
    </div>
  );
}

function renderWithClient() {
  const client = new QueryClient({
    defaultOptions: { queries: { retry: false, refetchInterval: false } },
  });
  return {
    ...render(
      <QueryClientProvider client={client}>
        <Probe />
      </QueryClientProvider>,
    ),
    client,
  };
}

describe('useActions', () => {
  beforeEach(() => {
    vi.stubGlobal('fetch', vi.fn());
  });

  afterEach(() => {
    vi.unstubAllGlobals();
    vi.restoreAllMocks();
  });

  it('dispatch sends POST with correct payload', async () => {
    (globalThis.fetch as ReturnType<typeof vi.fn>).mockResolvedValue({
      ok: true,
      json: async () => ({ ok: true }),
    });

    renderWithClient();
    const user = userEvent.setup();
    await user.click(screen.getByText('dispatch'));

    await waitFor(() => {
      expect(globalThis.fetch).toHaveBeenCalledWith(
        './api/actions',
        expect.objectContaining({
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
        }),
      );
    });

    // Verify the body contains the right action
    const callArgs = (globalThis.fetch as ReturnType<typeof vi.fn>).mock.calls[0];
    const body = JSON.parse(callArgs[1].body);
    expect(body.action).toBe('unblock');
    expect(body.feature).toBe('F01');
    expect(body.task).toBe('F01-T01');
    expect(body.operator).toBe('user');
    expect(body.action_id).toBeTruthy();
  });

  it('reports error on failure', async () => {
    (globalThis.fetch as ReturnType<typeof vi.fn>).mockResolvedValue({
      ok: false,
      status: 500,
    });

    renderWithClient();
    const user = userEvent.setup();
    await user.click(screen.getByText('dispatch'));

    await waitFor(() =>
      expect(screen.getByText(/error:Failed to post action: 500/)).toBeInTheDocument(),
    );
  });
});
