import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import {
  fetchWarroomCards,
  postWarroomCard,
  generateCardId,
  buildBoardState,
} from './fetchWarroom';
import type { WarRoomCard } from './warroomTypes';

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
// Setup
// ---------------------------------------------------------------------------

beforeEach(() => {
  vi.stubGlobal('fetch', vi.fn());
});

afterEach(() => {
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
});

// ---------------------------------------------------------------------------
// fetchWarroomCards
// ---------------------------------------------------------------------------

describe('fetchWarroomCards', () => {
  it('parses a valid response array', async () => {
    const cards = [makeCard(), makeCard({ card_id: 'WR-20261126-002', created_at: '2026-11-26T11:00:00Z' })];
    (globalThis.fetch as ReturnType<typeof vi.fn>).mockResolvedValue({
      ok: true,
      json: async () => cards,
    });

    const result = await fetchWarroomCards();
    expect(result).toHaveLength(2);
    // Sorted newest first
    expect(result[0].card_id).toBe('WR-20261126-002');
  });

  it('filters out invalid entries', async () => {
    const mixed = [
      makeCard(),
      { invalid: true },
      null,
      42,
      'string',
    ];
    (globalThis.fetch as ReturnType<typeof vi.fn>).mockResolvedValue({
      ok: true,
      json: async () => mixed,
    });

    const result = await fetchWarroomCards();
    expect(result).toHaveLength(1);
    expect(result[0].card_id).toBe('WR-20261126-001');
  });

  it('returns [] on empty array response', async () => {
    (globalThis.fetch as ReturnType<typeof vi.fn>).mockResolvedValue({
      ok: true,
      json: async () => [],
    });

    const result = await fetchWarroomCards();
    expect(result).toEqual([]);
  });

  it('returns [] when response is not an array', async () => {
    (globalThis.fetch as ReturnType<typeof vi.fn>).mockResolvedValue({
      ok: true,
      json: async () => ({ not: 'array' }),
    });

    const result = await fetchWarroomCards();
    expect(result).toEqual([]);
  });

  it('throws on non-ok response', async () => {
    (globalThis.fetch as ReturnType<typeof vi.fn>).mockResolvedValue({
      ok: false,
      status: 500,
    });

    await expect(fetchWarroomCards()).rejects.toThrow('warroom-cards.json 500');
  });
});

// ---------------------------------------------------------------------------
// postWarroomCard
// ---------------------------------------------------------------------------

describe('postWarroomCard', () => {
  it('sends POST with card JSON', async () => {
    (globalThis.fetch as ReturnType<typeof vi.fn>).mockResolvedValue({
      ok: true,
      json: async () => ({ ok: true, file: 'WR-20261126-001.json' }),
    });

    const card = makeCard();
    const result = await postWarroomCard(card);

    expect(result.ok).toBe(true);
    expect(result.file).toBe('WR-20261126-001.json');
    expect(globalThis.fetch).toHaveBeenCalledWith(
      './api/warroom-cards',
      expect.objectContaining({
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
      }),
    );
  });

  it('throws on non-ok response', async () => {
    (globalThis.fetch as ReturnType<typeof vi.fn>).mockResolvedValue({
      ok: false,
      status: 400,
    });

    await expect(postWarroomCard(makeCard())).rejects.toThrow('Failed to post warroom card: 400');
  });
});

// ---------------------------------------------------------------------------
// generateCardId
// ---------------------------------------------------------------------------

describe('generateCardId', () => {
  it('generates WR-YYYYMMDD-001 when no existing cards', () => {
    const id = generateCardId([]);
    expect(id).toMatch(/^WR-\d{8}-001$/);
  });

  it('generates sequential IDs based on existing cards for today', () => {
    const now = new Date();
    const dateStr = now.toISOString().slice(0, 10).replace(/-/g, '');
    const existing = [
      makeCard({ card_id: `WR-${dateStr}-001` }),
      makeCard({ card_id: `WR-${dateStr}-003` }),
    ];

    const id = generateCardId(existing);
    expect(id).toBe(`WR-${dateStr}-004`);
  });

  it('ignores cards from other days', () => {
    const existing = [
      makeCard({ card_id: 'WR-20200101-005' }),
    ];

    const id = generateCardId(existing);
    // Should be 001 since the existing card is from a different day
    expect(id).toMatch(/^WR-\d{8}-001$/);
  });
});

// ---------------------------------------------------------------------------
// buildBoardState
// ---------------------------------------------------------------------------

describe('buildBoardState', () => {
  it('builds empty state from empty array', () => {
    const state = buildBoardState([]);
    expect(state.total).toBe(0);
    expect(state.incoming_count).toBe(0);
    expect(state.columns.incoming).toEqual([]);
    expect(state.columns.triaging).toEqual([]);
    expect(state.columns.promoted).toEqual([]);
    expect(state.columns.deferred).toEqual([]);
    expect(state.columns.archived).toEqual([]);
    expect(state.cards).toEqual([]);
  });

  it('groups cards by status into correct columns', () => {
    const cards = [
      makeCard({ card_id: 'WR-001', status: 'incoming' }),
      makeCard({ card_id: 'WR-002', status: 'incoming' }),
      makeCard({ card_id: 'WR-003', status: 'triaging' }),
      makeCard({ card_id: 'WR-004', status: 'promoted' }),
      makeCard({ card_id: 'WR-005', status: 'deferred' }),
      makeCard({ card_id: 'WR-006', status: 'archived' }),
    ];

    const state = buildBoardState(cards);
    expect(state.total).toBe(6);
    expect(state.incoming_count).toBe(2);
    expect(state.columns.incoming).toHaveLength(2);
    expect(state.columns.triaging).toHaveLength(1);
    expect(state.columns.promoted).toHaveLength(1);
    expect(state.columns.deferred).toHaveLength(1);
    expect(state.columns.archived).toHaveLength(1);
  });

  it('calculates incoming_count accurately', () => {
    const cards = [
      makeCard({ card_id: 'WR-001', status: 'incoming' }),
      makeCard({ card_id: 'WR-002', status: 'incoming' }),
      makeCard({ card_id: 'WR-003', status: 'incoming' }),
      makeCard({ card_id: 'WR-004', status: 'promoted' }),
    ];

    const state = buildBoardState(cards);
    expect(state.incoming_count).toBe(3);
  });

  it('places unknown statuses into incoming as fallback', () => {
    const cards = [
      makeCard({ card_id: 'WR-001', status: 'unknown_status' as any }),
    ];

    const state = buildBoardState(cards);
    expect(state.columns.incoming).toHaveLength(1);
    expect(state.total).toBe(1);
  });

  it('sets generated_at timestamp', () => {
    const state = buildBoardState([]);
    expect(state.generated_at).toBeTruthy();
    // Should be a valid ISO string
    expect(new Date(state.generated_at).toISOString()).toBeTruthy();
  });
});
