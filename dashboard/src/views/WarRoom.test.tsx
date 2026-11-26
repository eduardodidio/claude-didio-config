import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { render, screen, waitFor } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { WarRoom } from './WarRoom';
import type { WarRoomBoardState, WarRoomCard } from '@/lib/warroomTypes';

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

function makeBoardState(cards: WarRoomCard[] = []): WarRoomBoardState {
  const columns = {
    incoming: cards.filter((c) => c.status === 'incoming'),
    triaging: cards.filter((c) => c.status === 'triaging'),
    promoted: cards.filter((c) => c.status === 'promoted'),
    deferred: cards.filter((c) => c.status === 'deferred'),
    archived: cards.filter((c) => c.status === 'archived'),
  };
  return {
    cards,
    columns,
    total: cards.length,
    incoming_count: columns.incoming.length,
    generated_at: new Date().toISOString(),
  };
}

function makeSeededClient(boardState: WarRoomBoardState | null) {
  const client = new QueryClient({
    defaultOptions: { queries: { retry: false, refetchInterval: false, staleTime: Infinity } },
  });
  if (boardState) {
    client.setQueryData(['warroom', 'cards'], boardState);
  }
  return client;
}

function renderWarRoom(client?: QueryClient) {
  const qc = client ?? makeSeededClient(
    makeBoardState([
      makeCard({ card_id: 'WR-001', status: 'incoming' }),
      makeCard({ card_id: 'WR-002', status: 'triaging' }),
      makeCard({ card_id: 'WR-003', status: 'promoted' }),
    ]),
  );
  return render(
    <QueryClientProvider client={qc}>
      <WarRoom />
    </QueryClientProvider>,
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe('WarRoom', () => {
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

  it('renders 5 columns when data is available', () => {
    renderWarRoom();
    expect(screen.getByTestId('warroom-view')).toBeInTheDocument();
    expect(screen.getByTestId('warroom-column-incoming')).toBeInTheDocument();
    expect(screen.getByTestId('warroom-column-triaging')).toBeInTheDocument();
    expect(screen.getByTestId('warroom-column-promoted')).toBeInTheDocument();
    expect(screen.getByTestId('warroom-column-deferred')).toBeInTheDocument();
    expect(screen.getByTestId('warroom-column-archived')).toBeInTheDocument();
  });

  it('shows loading skeleton when no data is cached', () => {
    const client = new QueryClient({
      defaultOptions: { queries: { retry: false, refetchInterval: false } },
    });
    // Stub fetch to never resolve so it stays in loading state
    vi.stubGlobal('fetch', vi.fn().mockReturnValue(new Promise(() => {})));
    renderWarRoom(client);
    expect(screen.getByTestId('warroom-skeleton')).toBeInTheDocument();
  });

  it('shows error state on fetch failure', async () => {
    const client = new QueryClient({
      defaultOptions: { queries: { retry: false, refetchInterval: false } },
    });
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue({
      ok: false,
      status: 500,
    }));
    renderWarRoom(client);
    await waitFor(() =>
      expect(screen.getByTestId('warroom-error')).toBeInTheDocument(),
    );
  });

  it('shows empty state when no cards exist', () => {
    const client = makeSeededClient(makeBoardState([]));
    renderWarRoom(client);
    expect(screen.getByTestId('warroom-empty')).toBeInTheDocument();
  });

  it('renders cards in correct columns', () => {
    renderWarRoom();
    // incoming column should have 1 card
    expect(screen.getByTestId('warroom-column-count-incoming')).toHaveTextContent('1');
    // triaging column should have 1 card
    expect(screen.getByTestId('warroom-column-count-triaging')).toHaveTextContent('1');
    // promoted column should have 1 card
    expect(screen.getByTestId('warroom-column-count-promoted')).toHaveTextContent('1');
  });

  it('shows Add Card button', () => {
    renderWarRoom();
    expect(screen.getByTestId('warroom-add-card')).toBeInTheDocument();
    expect(screen.getByTestId('warroom-add-card')).toHaveTextContent('Add Card');
  });

  it('shows triage panel placeholder by default', () => {
    renderWarRoom();
    expect(screen.getByTestId('triage-panel-placeholder')).toBeInTheDocument();
    expect(screen.getByTestId('triage-panel-placeholder')).toHaveTextContent('Select a card');
  });
});
