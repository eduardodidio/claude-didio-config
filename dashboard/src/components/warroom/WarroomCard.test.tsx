import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { WarroomCard } from './WarroomCard';
import type { WarRoomCard as WarRoomCardType } from '@/lib/warroomTypes';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

function makeCard(overrides: Partial<WarRoomCardType> = {}): WarRoomCardType {
  return {
    card_id: 'WR-20261126-001',
    title: 'Auth refactor needed',
    body: 'The authentication module needs a refactor to support SSO.',
    source: 'operator',
    created_at: new Date(Date.now() - 3600_000).toISOString(), // 1h ago
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

describe('WarroomCard', () => {
  it('renders title and card_id', () => {
    const card = makeCard();
    render(<WarroomCard card={card} />);

    expect(screen.getByTestId('card-title-WR-20261126-001')).toHaveTextContent('Auth refactor needed');
    expect(screen.getByTestId('card-id-badge-WR-20261126-001')).toHaveTextContent('WR-20261126-001');
  });

  it('renders body text', () => {
    const card = makeCard();
    render(<WarroomCard card={card} />);

    expect(screen.getByTestId('card-body-WR-20261126-001')).toHaveTextContent(
      'The authentication module needs a refactor to support SSO.',
    );
  });

  it('renders timestamp', () => {
    const card = makeCard();
    render(<WarroomCard card={card} />);

    const timestamp = screen.getByTestId('card-timestamp-WR-20261126-001');
    expect(timestamp).toBeInTheDocument();
    // Should show relative time (e.g. "1h ago")
    expect(timestamp.textContent).toMatch(/ago|just now/);
  });

  it('renders source badge for operator', () => {
    const card = makeCard({ source: 'operator' });
    render(<WarroomCard card={card} />);

    const source = screen.getByTestId('card-source-WR-20261126-001');
    expect(source).toBeInTheDocument();
    expect(source).toHaveAttribute('title', 'Operator');
  });

  it('renders source badge for agent', () => {
    const card = makeCard({ source: 'agent' });
    render(<WarroomCard card={card} />);

    const source = screen.getByTestId('card-source-WR-20261126-001');
    expect(source).toHaveAttribute('title', 'Agent');
  });

  it('renders source badge for external', () => {
    const card = makeCard({ source: 'external' });
    render(<WarroomCard card={card} />);

    const source = screen.getByTestId('card-source-WR-20261126-001');
    expect(source).toHaveAttribute('title', 'External');
  });

  it('renders tags when present', () => {
    const card = makeCard({ tags: ['auth', 'q1', 'refactor'] });
    render(<WarroomCard card={card} />);

    const tagsContainer = screen.getByTestId('card-tags-WR-20261126-001');
    expect(tagsContainer).toBeInTheDocument();
    expect(tagsContainer).toHaveTextContent('auth');
    expect(tagsContainer).toHaveTextContent('q1');
    expect(tagsContainer).toHaveTextContent('refactor');
  });

  it('does not render tags container when tags are empty', () => {
    const card = makeCard({ tags: [] });
    render(<WarroomCard card={card} />);

    expect(screen.queryByTestId('card-tags-WR-20261126-001')).not.toBeInTheDocument();
  });

  it('renders priority pill when priority_suggestion is set', () => {
    const card = makeCard({ priority_suggestion: 'high' });
    render(<WarroomCard card={card} />);

    const priority = screen.getByTestId('card-priority-WR-20261126-001');
    expect(priority).toBeInTheDocument();
    expect(priority).toHaveTextContent('HIGH');
  });

  it('does not render priority pill when priority_suggestion is null', () => {
    const card = makeCard({ priority_suggestion: null });
    render(<WarroomCard card={card} />);

    expect(screen.queryByTestId('card-priority-WR-20261126-001')).not.toBeInTheDocument();
  });

  it('renders overlord assessment indicator when assessment exists', () => {
    const card = makeCard({
      overlord_assessment: {
        assessed_at: '2026-11-26T10:30:00Z',
        recommendation: 'promote',
        priority: 'high',
        rationale: 'Aligns with OKRs',
        promoted_as: 'F32',
      },
    });
    render(<WarroomCard card={card} />);

    const assessment = screen.getByTestId('card-assessment-WR-20261126-001');
    expect(assessment).toBeInTheDocument();
    expect(assessment).toHaveTextContent('Promote');
  });

  it('does not render assessment indicator when assessment is null', () => {
    const card = makeCard({ overlord_assessment: null });
    render(<WarroomCard card={card} />);

    expect(screen.queryByTestId('card-assessment-WR-20261126-001')).not.toBeInTheDocument();
  });

  it('truncates long titles (>60 chars)', () => {
    const longTitle = 'A'.repeat(80);
    const card = makeCard({ title: longTitle });
    render(<WarroomCard card={card} />);

    const titleEl = screen.getByTestId('card-title-WR-20261126-001');
    // Should be truncated to 60 chars + ellipsis
    expect(titleEl.textContent!.length).toBeLessThanOrEqual(61);
    expect(titleEl.textContent).toContain('\u2026');
  });

  it('fires onSelect with correct card_id on click', async () => {
    const onSelect = vi.fn();
    const card = makeCard();
    render(<WarroomCard card={card} onSelect={onSelect} />);

    const user = userEvent.setup();
    // Click the card container
    await user.click(screen.getByTestId('card-title-WR-20261126-001'));

    expect(onSelect).toHaveBeenCalledWith('WR-20261126-001');
  });
});
