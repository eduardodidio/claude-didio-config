import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { ActionButton } from './ActionButton';

function renderButton(
  props: Partial<React.ComponentProps<typeof ActionButton>> = {},
) {
  const client = new QueryClient({
    defaultOptions: { queries: { retry: false, refetchInterval: false } },
  });
  return render(
    <QueryClientProvider client={client}>
      <ActionButton
        action="unblock"
        feature="F01"
        {...props}
      />
    </QueryClientProvider>,
  );
}

describe('ActionButton', () => {
  beforeEach(() => {
    vi.stubGlobal('fetch', vi.fn());
    vi.stubGlobal('confirm', vi.fn(() => true));
  });

  afterEach(() => {
    vi.unstubAllGlobals();
    vi.restoreAllMocks();
  });

  it('renders correct label per action type', () => {
    renderButton({ action: 'unblock' });
    expect(screen.getByRole('button')).toHaveTextContent('Unblock');
  });

  it('renders custom label when provided', () => {
    renderButton({ action: 'approve', label: 'Go!' });
    expect(screen.getByRole('button')).toHaveTextContent('Go!');
  });

  it('disables during pending state', async () => {
    // Fetch never resolves to keep pending state
    (globalThis.fetch as ReturnType<typeof vi.fn>).mockReturnValue(
      new Promise(() => {}),
    );
    renderButton();
    const user = userEvent.setup();
    await user.click(screen.getByRole('button'));
    expect(screen.getByRole('button')).toBeDisabled();
  });

  it('calls dispatch on click (non-destructive)', async () => {
    (globalThis.fetch as ReturnType<typeof vi.fn>).mockResolvedValue({
      ok: true,
      json: async () => ({ ok: true }),
    });
    renderButton({ action: 'unblock', feature: 'F01' });
    const user = userEvent.setup();
    await user.click(screen.getByRole('button'));

    await waitFor(() => {
      expect(globalThis.fetch).toHaveBeenCalledWith(
        './api/actions',
        expect.objectContaining({ method: 'POST' }),
      );
    });
  });

  it('shows confirmation for destructive actions (cancel)', async () => {
    (globalThis.fetch as ReturnType<typeof vi.fn>).mockResolvedValue({
      ok: true,
      json: async () => ({ ok: true }),
    });
    (globalThis.confirm as ReturnType<typeof vi.fn>).mockReturnValue(true);

    renderButton({ action: 'cancel', feature: 'F01' });
    const user = userEvent.setup();
    await user.click(screen.getByRole('button'));

    expect(globalThis.confirm).toHaveBeenCalledWith(
      expect.stringContaining('cancel'),
    );
  });

  it('shows confirmation for destructive actions (skip)', async () => {
    (globalThis.fetch as ReturnType<typeof vi.fn>).mockResolvedValue({
      ok: true,
      json: async () => ({ ok: true }),
    });
    (globalThis.confirm as ReturnType<typeof vi.fn>).mockReturnValue(true);

    renderButton({ action: 'skip', feature: 'F01', task: 'F01-T03' });
    const user = userEvent.setup();
    await user.click(screen.getByRole('button'));

    expect(globalThis.confirm).toHaveBeenCalledWith(
      expect.stringContaining('skip'),
    );
  });

  it('does not dispatch when destructive action is cancelled', async () => {
    (globalThis.confirm as ReturnType<typeof vi.fn>).mockReturnValue(false);

    renderButton({ action: 'cancel', feature: 'F01' });
    const user = userEvent.setup();
    await user.click(screen.getByRole('button'));

    expect(globalThis.fetch).not.toHaveBeenCalled();
  });

  it('respects disabled prop', () => {
    renderButton({ disabled: true });
    expect(screen.getByRole('button')).toBeDisabled();
  });
});
