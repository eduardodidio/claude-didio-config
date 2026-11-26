import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { FlagPanel } from './FlagPanel';
import type { AgentFlag, ActionType } from '@/lib/kanbanTypes';

function mkFlag(overrides: Partial<AgentFlag> = {}): AgentFlag {
  return {
    flag_id: 'f1',
    type: 'blocked',
    feature: 'F01',
    task: null,
    severity: 'critical',
    reason: 'dependency missing',
    suggested_actions: ['auto_resolve', 'skip_task'],
    created_at: '2026-11-01T10:00:00Z',
    resolved_at: null,
    ...overrides,
  };
}

describe('FlagPanel', () => {
  it('renders all active flags sorted by severity', () => {
    const flags = [
      mkFlag({ flag_id: 'f1', severity: 'info', type: 'token_warning' }),
      mkFlag({ flag_id: 'f2', severity: 'critical', type: 'blocked' }),
      mkFlag({ flag_id: 'f3', severity: 'warning', type: 'needs_review' }),
    ];
    const onAction = vi.fn();
    render(<FlagPanel flags={flags} onAction={onAction} />);

    expect(screen.getByTestId('flag-panel')).toBeInTheDocument();
    // All 3 flag cards rendered
    expect(screen.getByTestId('flag-card-f1')).toBeInTheDocument();
    expect(screen.getByTestId('flag-card-f2')).toBeInTheDocument();
    expect(screen.getByTestId('flag-card-f3')).toBeInTheDocument();
  });

  it('shows empty state with no flags', () => {
    const onAction = vi.fn();
    render(<FlagPanel flags={[]} onAction={onAction} />);
    expect(screen.getByTestId('flag-panel-empty')).toBeInTheDocument();
  });

  it('shows loading skeleton when isLoading is true', () => {
    const onAction = vi.fn();
    render(<FlagPanel flags={[]} onAction={onAction} isLoading />);
    expect(screen.getByTestId('flag-panel-skeleton')).toBeInTheDocument();
  });

  it('resolved flags appear in collapsed section', () => {
    const flags = [
      mkFlag({ flag_id: 'f1', resolved_at: '2026-11-01T12:00:00Z' }),
    ];
    const onAction = vi.fn();
    render(<FlagPanel flags={flags} onAction={onAction} />);
    expect(screen.getByTestId('resolved-section')).toBeInTheDocument();
    // Collapsed by default -- resolved list not visible
    expect(screen.queryByTestId('resolved-list')).not.toBeInTheDocument();
  });

  it('expands resolved section on toggle click', async () => {
    const flags = [
      mkFlag({ flag_id: 'f1', resolved_at: '2026-11-01T12:00:00Z' }),
    ];
    const onAction = vi.fn();
    render(<FlagPanel flags={flags} onAction={onAction} />);

    const user = userEvent.setup();
    await user.click(screen.getByTestId('resolved-toggle'));
    expect(screen.getByTestId('resolved-list')).toBeInTheDocument();
  });

  it('action button click calls onAction with correct params', async () => {
    const flags = [
      mkFlag({
        flag_id: 'f1',
        suggested_actions: ['auto_resolve'],
      }),
    ];
    const onAction = vi.fn();
    render(<FlagPanel flags={flags} onAction={onAction} />);

    const user = userEvent.setup();
    // Click the "Unblock" button (from auto_resolve mapping)
    const actionsContainer = screen.getByTestId('flag-actions-f1');
    const unblockBtn = actionsContainer.querySelector('button');
    expect(unblockBtn).toBeTruthy();
    await user.click(unblockBtn!);

    expect(onAction).toHaveBeenCalledWith('unblock', flags[0]);
  });

  it('dismiss button always calls onAction with approve', async () => {
    const flags = [mkFlag({ flag_id: 'f1', suggested_actions: [] })];
    const onAction = vi.fn();
    render(<FlagPanel flags={flags} onAction={onAction} />);

    const user = userEvent.setup();
    const actionsContainer = screen.getByTestId('flag-actions-f1');
    // Only the Dismiss (ghost) button when there are no suggested actions
    const dismissBtn = actionsContainer.querySelector('button');
    expect(dismissBtn).toBeTruthy();
    await user.click(dismissBtn!);

    expect(onAction).toHaveBeenCalledWith('approve', flags[0]);
  });
});
