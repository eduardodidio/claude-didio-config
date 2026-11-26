import type {
  WarRoomCard,
  WarRoomBoardState,
  WarRoomStatus,
  CreateCardInput,
} from './warroomTypes';

/**
 * Validate that a raw object looks like a WarRoomCard.
 */
function isValidCard(obj: unknown): obj is WarRoomCard {
  if (typeof obj !== 'object' || obj === null) return false;
  const c = obj as Record<string, unknown>;
  return (
    typeof c.card_id === 'string' &&
    typeof c.title === 'string' &&
    typeof c.body === 'string' &&
    typeof c.source === 'string' &&
    typeof c.created_at === 'string' &&
    typeof c.status === 'string'
  );
}

/**
 * Fetch all War Room cards from the aggregated JSON endpoint.
 * The Vite dev-server plugin serves /warroom-cards.json from logs/warroom/cards/*.json.
 */
export async function fetchWarroomCards(): Promise<WarRoomCard[]> {
  const res = await fetch('./warroom-cards.json', { cache: 'no-store' });
  if (!res.ok) throw new Error(`warroom-cards.json ${res.status}`);
  const raw: unknown = await res.json();
  if (!Array.isArray(raw)) return [];
  const cards = raw.filter(isValidCard);
  // Sort by created_at descending (newest first)
  cards.sort((a, b) => b.created_at.localeCompare(a.created_at));
  return cards;
}

/**
 * Post a new War Room card via the dev-server API.
 * The server writes the JSON file to logs/warroom/cards/<card_id>.json.
 */
export async function postWarroomCard(
  card: WarRoomCard,
): Promise<{ ok: boolean; file: string }> {
  const res = await fetch('./api/warroom-cards', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(card),
  });
  if (!res.ok) throw new Error(`Failed to post warroom card: ${res.status}`);
  return res.json();
}

/**
 * Update an existing War Room card (same POST endpoint, overwrites by card_id).
 */
export async function updateWarroomCard(
  card: WarRoomCard,
): Promise<{ ok: boolean; file: string }> {
  const res = await fetch('./api/warroom-cards', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ ...card, updated_at: new Date().toISOString() }),
  });
  if (!res.ok) throw new Error(`Failed to update warroom card: ${res.status}`);
  return res.json();
}

/**
 * Generate a card_id in WR-YYYYMMDD-NNN format.
 * The NNN is sequential based on existing cards for that day.
 */
export function generateCardId(existingCards: WarRoomCard[]): string {
  const now = new Date();
  const dateStr = now.toISOString().slice(0, 10).replace(/-/g, '');
  const prefix = `WR-${dateStr}-`;
  const todayCards = existingCards.filter((c) => c.card_id.startsWith(prefix));
  const maxN = todayCards.reduce((max, c) => {
    const suffix = c.card_id.slice(prefix.length);
    const n = parseInt(suffix, 10);
    return isNaN(n) ? max : Math.max(max, n);
  }, 0);
  const next = String(maxN + 1).padStart(3, '0');
  return `${prefix}${next}`;
}

/**
 * Create a new WarRoomCard from operator input.
 * Generates card_id, sets defaults, and posts to the server.
 */
export async function createWarroomCard(
  input: CreateCardInput,
  existingCards: WarRoomCard[] = [],
): Promise<WarRoomCard> {
  const card: WarRoomCard = {
    card_id: generateCardId(existingCards),
    title: input.title,
    body: input.body,
    source: input.source ?? 'operator',
    created_at: new Date().toISOString(),
    updated_at: null,
    status: 'incoming',
    priority_suggestion: input.priority_suggestion ?? null,
    overlord_assessment: null,
    promoted_to: null,
    tags: input.tags ?? [],
    source_agent: null,
    source_feature: null,
  };
  await postWarroomCard(card);
  return card;
}

/**
 * Build board state from a flat card list.
 * Groups cards by status into columns and calculates totals.
 */
export function buildBoardState(cards: WarRoomCard[]): WarRoomBoardState {
  const columns: Record<WarRoomStatus, WarRoomCard[]> = {
    incoming: [],
    triaging: [],
    promoted: [],
    deferred: [],
    archived: [],
  };

  for (const card of cards) {
    if (columns[card.status]) {
      columns[card.status].push(card);
    } else {
      // Fallback: unknown status goes to incoming
      columns.incoming.push(card);
    }
  }

  return {
    cards,
    columns,
    total: cards.length,
    incoming_count: columns.incoming.length,
    generated_at: new Date().toISOString(),
  };
}
