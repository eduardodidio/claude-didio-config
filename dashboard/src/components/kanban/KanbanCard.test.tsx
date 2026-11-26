import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { KanbanCard } from './KanbanCard';
import type { KanbanCard as KanbanCardType, AgentFlag } from '@/lib/kanbanTypes';

function mkFlag(overrides: Partial<AgentFlag> = {}): AgentFlag {
  return {
    flag_id: 'f1',
    type: 'blocked',
    feature: 'F01',
    task: null,
    severity: 'critical',
    reason: 'dep missing',
    suggested_actions: [],
    created_at: '2026-11-01T10:00:00Z',
    resolved_at: null,
    ...overrides,
  };
}

function mkCard(overrides: Partial<KanbanCardType> = {}): KanbanCardType {
  return {
    feature: 'F01',
    column: 'RUNNING',
    progress: 60,
    taskCount: 10,
    completedTasks: 6,
    currentPhase: 'developer',
    currentTask: 'F01-T05',
    flags: [],
    isBlocked: false,
    priority: 'medium',
    ...overrides,
  };
}

describe('KanbanCard', () => {
  it('renders feature ID, progress bar, task count', () => {
    render(<KanbanCard card={mkCard()} />);

    expect(screen.getByTestId('card-feature-id-F01')).toHaveTextContent('F01');
    expect(screen.getByTestId('card-progress-F01')).toBeInTheDocument();
    expect(screen.getByTestId('card-task-count-F01')).toHaveTextContent('6/10 tasks');
  });

  it('shows blocked badge when isBlocked is true', () => {
    render(<KanbanCard card={mkCard({ isBlocked: true })} />);
    expect(screen.getByTestId('blocked-badge-F01')).toHaveTextContent('BLOCKED');
  });

  it('does not show blocked badge when isBlocked is false', () => {
    render(<KanbanCard card={mkCard({ isBlocked: false })} />);
    expect(screen.queryByTestId('blocked-badge-F01')).not.toBeInTheDocument();
  });

  it('shows flag indicator dots for active flags', () => {
    const flags = [
      mkFlag({ flag_id: 'f1', resolved_at: null }),
      mkFlag({ flag_id: 'f2', type: 'needs_review', severity: 'warning', resolved_at: null }),
    ];
    render(<KanbanCard card={mkCard({ flags })} />);

    expect(screen.getByTestId('card-flags-F01')).toBeInTheDocument();
    expect(screen.getByTestId('flag-dot-f1')).toBeInTheDocument();
    expect(screen.getByTestId('flag-dot-f2')).toBeInTheDocument();
  });

  it('does not show flag dots for resolved flags', () => {
    const flags = [
      mkFlag({ flag_id: 'f1', resolved_at: '2026-11-01T12:00:00Z' }),
    ];
    render(<KanbanCard card={mkCard({ flags })} />);
    expect(screen.queryByTestId('card-flags-F01')).not.toBeInTheDocument();
  });

  it('calls onClick when clicked', async () => {
    const onClick = vi.fn();
    render(<KanbanCard card={mkCard()} onClick={onClick} />);

    const user = userEvent.setup();
    // Click the feature ID label inside the Card (the Card element has the onClick)
    await user.click(screen.getByTestId('card-feature-id-F01'));
    expect(onClick).toHaveBeenCalled();
  });
});
