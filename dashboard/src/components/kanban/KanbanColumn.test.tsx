import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { KanbanColumn } from './KanbanColumn';
import type { KanbanCard } from '@/lib/kanbanTypes';

function mkCard(overrides: Partial<KanbanCard> = {}): KanbanCard {
  return {
    feature: 'F01',
    column: 'RUNNING',
    progress: 50,
    taskCount: 10,
    completedTasks: 5,
    currentPhase: 'developer',
    currentTask: 'F01-T05',
    flags: [],
    isBlocked: false,
    priority: 'medium',
    ...overrides,
  };
}

describe('KanbanColumn', () => {
  it('renders column header with title and card count', () => {
    const cards = [mkCard(), mkCard({ feature: 'F02' })];
    render(<KanbanColumn title="RUNNING" cards={cards} />);

    expect(screen.getByTestId('column-title-RUNNING')).toHaveTextContent('Running');
    expect(screen.getByTestId('column-count-RUNNING')).toHaveTextContent('2');
  });

  it('renders all provided cards', () => {
    const cards = [mkCard({ feature: 'F01' }), mkCard({ feature: 'F02' })];
    render(<KanbanColumn title="RUNNING" cards={cards} />);

    expect(screen.getByTestId('kanban-card-F01')).toBeInTheDocument();
    expect(screen.getByTestId('kanban-card-F02')).toBeInTheDocument();
  });

  it('shows empty state when cards array is empty', () => {
    render(<KanbanColumn title="BACKLOG" cards={[]} />);
    expect(screen.getByTestId('column-empty-BACKLOG')).toHaveTextContent('No features');
  });

  it('each column variant has correct background tint class', () => {
    const { container: c1 } = render(
      <KanbanColumn title="BACKLOG" cards={[]} />,
    );
    expect(c1.querySelector('[data-testid="kanban-column-BACKLOG"]')?.className).toContain('bg-muted');

    const { container: c2 } = render(
      <KanbanColumn title="DONE" cards={[]} />,
    );
    expect(c2.querySelector('[data-testid="kanban-column-DONE"]')?.className).toContain('bg-green');
  });

  it('calls onCardClick when a card is clicked', async () => {
    const onClick = vi.fn();
    const cards = [mkCard({ feature: 'F01' })];
    render(<KanbanColumn title="RUNNING" cards={cards} onCardClick={onClick} />);

    const user = userEvent.setup();
    // Click the feature ID label inside the Card to trigger the Card onClick
    await user.click(screen.getByTestId('card-feature-id-F01'));
    expect(onClick).toHaveBeenCalledWith('F01');
  });
});
