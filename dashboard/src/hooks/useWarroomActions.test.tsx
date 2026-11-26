import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { useCreateCard, useUpdateCard, useTriageCard } from './useWarroomActions';
import type { WarRoomCard, CreateCardInput } from '@/lib/warroomTypes';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

function makeCard(overrides: Partial<WarRoomCard> = {}): WarRoomCard {
  return {
    card_id: 'WR-20261126-001',
    title: 'Test card',
    body: 'Test body',
    source: 'operator',
    created_at: '2026-11-26T10:00:00Z',
    updated_at: null,
    status: 'incoming',
    priority_suggestion: null,
    overlord_assessment: null,
    promoted_to: null,
    tags: [],
    source_agent: null,
    source_feature: null,
    ...overrides,
  };
}

// ---------------------------------------------------------------------------
// Probe: useCreateCard
// ---------------------------------------------------------------------------

function CreateProbe() {
  const mutation = useCreateCard();

  return (
    <div>
      <button
        onClick={() =>
          mutation.mutate({ title: 'New', body: 'Body text' } as CreateCardInput)
        }
      >
        create
      </button>
      {mutation.isPending && <span>pending</span>}
      {mutation.isError && <span>error:{(mutation.error as Error).message}</span>}
      {mutation.isSuccess && <span>success</span>}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Probe: useUpdateCard
// ---------------------------------------------------------------------------

function UpdateProbe() {
  const mutation = useUpdateCard();
  const card = makeCard();

  return (
    <div>
      <button onClick={() => mutation.mutate({ ...card, status: 'triaging' })}>
        update
      </button>
      {mutation.isPending && <span>pending</span>}
      {mutation.isSuccess && <span>success</span>}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Probe: useTriageCard
// ---------------------------------------------------------------------------

function TriageProbe() {
  const mutation = useTriageCard();
  const card = makeCard();

  return (
    <div>
      <button onClick={() => mutation.mutate(card)}>triage</button>
      {mutation.isPending && <span>pending</span>}
      {mutation.isSuccess && <span>success</span>}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function renderWithClient(ui: React.ReactElement) {
  const client = new QueryClient({
    defaultOptions: { queries: { retry: false, refetchInterval: false } },
  });
  return {
    ...render(
      <QueryClientProvider client={client}>{ui}</QueryClientProvider>,
    ),
    client,
  };
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe('useWarroomActions', () => {
  beforeEach(() => {
    vi.stubGlobal('fetch', vi.fn());
  });

  afterEach(() => {
    vi.unstubAllGlobals();
    vi.restoreAllMocks();
  });

  describe('useCreateCard', () => {
    it('calls fetch to create a card and reports success', async () => {
      // First call: fetchWarroomCards (GET), second call: postWarroomCard (POST)
      (globalThis.fetch as ReturnType<typeof vi.fn>)
        .mockResolvedValueOnce({ ok: true, json: async () => [] })
        .mockResolvedValueOnce({
          ok: true,
          json: async () => ({ ok: true, file: 'WR-20261126-001.json' }),
        });

      renderWithClient(<CreateProbe />);
      const user = userEvent.setup();
      await user.click(screen.getByText('create'));

      await waitFor(() =>
        expect(screen.getByText('success')).toBeInTheDocument(),
      );
    });

    it('reports error on fetch failure', async () => {
      (globalThis.fetch as ReturnType<typeof vi.fn>)
        .mockResolvedValueOnce({ ok: true, json: async () => [] })
        .mockResolvedValueOnce({ ok: false, status: 500 });

      renderWithClient(<CreateProbe />);
      const user = userEvent.setup();
      await user.click(screen.getByText('create'));

      await waitFor(() =>
        expect(screen.getByText(/error:/)).toBeInTheDocument(),
      );
    });
  });

  describe('useUpdateCard', () => {
    it('calls fetch to update a card', async () => {
      (globalThis.fetch as ReturnType<typeof vi.fn>).mockResolvedValue({
        ok: true,
        json: async () => ({ ok: true, file: 'WR-20261126-001.json' }),
      });

      renderWithClient(<UpdateProbe />);
      const user = userEvent.setup();
      await user.click(screen.getByText('update'));

      await waitFor(() =>
        expect(screen.getByText('success')).toBeInTheDocument(),
      );

      expect(globalThis.fetch).toHaveBeenCalledWith(
        './api/warroom-cards',
        expect.objectContaining({ method: 'POST' }),
      );
    });
  });

  describe('useTriageCard', () => {
    it('posts card with status set to triaging', async () => {
      (globalThis.fetch as ReturnType<typeof vi.fn>).mockResolvedValue({
        ok: true,
        json: async () => ({ ok: true, file: 'WR-20261126-001.json' }),
      });

      renderWithClient(<TriageProbe />);
      const user = userEvent.setup();
      await user.click(screen.getByText('triage'));

      await waitFor(() =>
        expect(screen.getByText('success')).toBeInTheDocument(),
      );

      // Verify the posted body has status=triaging
      const callArgs = (globalThis.fetch as ReturnType<typeof vi.fn>).mock.calls[0];
      const body = JSON.parse(callArgs[1].body);
      expect(body.status).toBe('triaging');
    });
  });
});
