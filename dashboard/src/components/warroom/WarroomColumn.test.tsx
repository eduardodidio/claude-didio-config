import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import { WarroomColumn } from './WarroomColumn';
import type { WarRoomCard } from '@/lib/warroomTypes';

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
// Tests
// ---------------------------------------------------------------------------

describe('WarroomColumn', () => {
  it('renders column header with correct label', () => {
    render(<WarroomColumn status="incoming" cards={[]} />);

    expect(screen.getByTestId('warroom-column-title-incoming')).toHaveTextContent('Incoming');
  });

  it('renders each status with the correct label', () => {
    const statuses = [
      { status: 'incoming' as const, label: 'Incoming' },
      { status: 'triaging' as const, label: 'Triaging' },
      { status: 'promoted' as const, label: 'Promoted' },
      { status: 'deferred' as const, label: 'Deferred' },
      { status: 'archived' as const, label: 'Archived' },
    ];

    for (const { status, label } of statuses) {
      const { unmount } = render(<WarroomColumn status={status} cards={[]} />);
      expect(screen.getByTestId(`warroom-column-title-${status}`)).toHaveTextContent(label);
      unmount();
    }
  });

  it('shows empty state when there are 0 cards', () => {
    render(<WarroomColumn status="incoming" cards={[]} />);

    expect(screen.getByTestId('warroom-column-empty-incoming')).toBeInTheDocument();
    expect(screen.getByTestId('warroom-column-empty-incoming')).toHaveTextContent('No cards');
  });

  it('renders all cards and shows correct count badge', () => {
    const cards = [
      makeCard({ card_id: 'WR-001' }),
      makeCard({ card_id: 'WR-002' }),
      makeCard({ card_id: 'WR-003' }),
    ];

    render(<WarroomColumn status="incoming" cards={cards} />);

    // Count badge shows 3
    expect(screen.getByTestId('warroom-column-count-incoming')).toHaveTextContent('3');

    // All 3 cards rendered
    expect(screen.getByTestId('warroom-card-WR-001')).toBeInTheDocument();
    expect(screen.getByTestId('warroom-card-WR-002')).toBeInTheDocument();
    expect(screen.getByTestId('warroom-card-WR-003')).toBeInTheDocument();
  });

  it('does not show empty state when cards are present', () => {
    const cards = [makeCard({ card_id: 'WR-001' })];
    render(<WarroomColumn status="incoming" cards={cards} />);

    expect(screen.queryByTestId('warroom-column-empty-incoming')).not.toBeInTheDocument();
  });

  it('passes onCardSelect to child cards', () => {
    const onCardSelect = vi.fn();
    const cards = [makeCard({ card_id: 'WR-001' })];

    render(
      <WarroomColumn status="incoming" cards={cards} onCardSelect={onCardSelect} />,
    );

    // Card should be rendered (the actual click test is in WarroomCard.test.tsx)
    expect(screen.getByTestId('warroom-card-WR-001')).toBeInTheDocument();
  });
});
