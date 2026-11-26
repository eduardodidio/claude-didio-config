import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { useWarroomState } from './useWarroomState';
import type { WarRoomBoardState, WarRoomCard } from '@/lib/warroomTypes';

// ---------------------------------------------------------------------------
// Probe component
// ---------------------------------------------------------------------------

function Probe() {
  const { data, isLoading, isError } = useWarroomState({ refetchInterval: false as any });
  if (isLoading) return <div>loading</div>;
  if (isError) return <div>error</div>;
  if (!data) return <div>no-data</div>;
  return (
    <div>
      <span data-testid="total">{data.total}</span>
      <span data-testid="incoming">{data.incoming_count}</span>
      {Object.entries(data.columns).map(([status, cards]) => (
        <span key={status} data-testid={`col-${status}`}>
          {(cards as WarRoomCard[]).length}
        </span>
      ))}
    </div>
  );
}

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

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function makeSeededClient(boardState: WarRoomBoardState | null) {
  const client = new QueryClient({
    defaultOptions: { queries: { retry: false, refetchInterval: false, staleTime: Infinity } },
  });
  if (boardState) {
    client.setQueryData(['warroom', 'cards'], boardState);
  }
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

describe('useWarroomState', () => {
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

  it('returns data when cache is seeded', () => {
    const cards = [
      makeCard({ card_id: 'WR-001', status: 'incoming' }),
      makeCard({ card_id: 'WR-002', status: 'triaging' }),
    ];
    const client = makeSeededClient(makeBoardState(cards));
    renderWith(client);
    expect(screen.getByTestId('total')).toHaveTextContent('2');
    expect(screen.getByTestId('incoming')).toHaveTextContent('1');
  });

  it('groups cards into correct columns', () => {
    const cards = [
      makeCard({ card_id: 'WR-001', status: 'incoming' }),
      makeCard({ card_id: 'WR-002', status: 'incoming' }),
      makeCard({ card_id: 'WR-003', status: 'promoted' }),
    ];
    const client = makeSeededClient(makeBoardState(cards));
    renderWith(client);
    expect(screen.getByTestId('col-incoming')).toHaveTextContent('2');
    expect(screen.getByTestId('col-promoted')).toHaveTextContent('1');
    expect(screen.getByTestId('col-triaging')).toHaveTextContent('0');
  });

  it('shows loading state when no data is cached', () => {
    // Stub fetch to never resolve
    vi.stubGlobal('fetch', vi.fn().mockReturnValue(new Promise(() => {})));
    const client = new QueryClient({
      defaultOptions: { queries: { retry: false, refetchInterval: false } },
    });
    renderWith(client);
    expect(screen.getByText('loading')).toBeInTheDocument();
  });

  it('handles empty board state', () => {
    const client = makeSeededClient(makeBoardState([]));
    renderWith(client);
    expect(screen.getByTestId('total')).toHaveTextContent('0');
    expect(screen.getByTestId('incoming')).toHaveTextContent('0');
  });
});
