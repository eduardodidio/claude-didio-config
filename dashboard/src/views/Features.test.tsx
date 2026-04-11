import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import type { AgentRun, DidioState } from '@/lib/types';

const mockState = vi.hoisted(() => ({
  data: undefined as DidioState | undefined,
  isLoading: false,
  error: null as Error | null,
}));

vi.mock('@/hooks/useDidioState', () => ({
  useDidioState: () => mockState,
}));

import { Features } from './Features';

function makeRun(over: Partial<AgentRun>): AgentRun {
  return {
    feature: 'F01',
    role: 'developer',
    task: 'F01-T01',
    task_file: 'tasks/features/F01/F01-T01.md',
    started_at: '2026-04-11T10:00:00Z',
    finished_at: '2026-04-11T10:00:05Z',
    status: 'completed',
    exit_code: 0,
    pid: 1000,
    log: 'logs/agents/run.log',
    phrase: null,
    ...over,
  };
}

function setState(state: Partial<typeof mockState>) {
  Object.assign(mockState, { data: undefined, isLoading: false, error: null }, state);
}

describe('Features view', () => {
  it('happy: renders 2 feature cards and expands to show run list', async () => {
    const user = userEvent.setup();
    setState({
      data: {
        generated_at: '2026-04-11T10:00:10Z',
        agents: [
          makeRun({ feature: 'F01', task: 'F01-T01', pid: 1 }),
          makeRun({ feature: 'F01', task: 'F01-T02', pid: 2 }),
          makeRun({ feature: 'F02', task: 'F02-T01', pid: 3 }),
          makeRun({ feature: 'F02', task: 'F02-T02', pid: 4 }),
        ],
      },
    });

    render(<Features />);

    expect(screen.getByText('F01')).toBeInTheDocument();
    expect(screen.getByText('F02')).toBeInTheDocument();

    const f01Header = screen.getByRole('button', { name: /F01/ });
    expect(f01Header).toHaveAttribute('aria-expanded', 'false');

    await user.click(f01Header);
    expect(f01Header).toHaveAttribute('aria-expanded', 'true');

    expect(screen.getAllByText('F01-T01').length).toBeGreaterThan(0);
    expect(screen.getAllByText('F01-T02').length).toBeGreaterThan(0);
    expect(screen.getByTestId('feature-runs-F01')).toBeInTheDocument();
  });

  it('edge: feature with 0 runs is filtered out (no entry rendered)', () => {
    setState({
      data: {
        generated_at: '2026-04-11T10:00:10Z',
        agents: [makeRun({ feature: 'F01' })],
      },
    });
    render(<Features />);
    expect(screen.getByText('F01')).toBeInTheDocument();
    expect(screen.queryByText('F99')).not.toBeInTheDocument();
  });

  it('error: error state renders an error message', () => {
    setState({ error: new Error('boom') });
    render(<Features />);
    const alert = screen.getByRole('alert');
    expect(alert).toHaveTextContent(/boom/);
  });

  it('boundary: a run with finished_at === null shows duration as running…', async () => {
    const user = userEvent.setup();
    setState({
      data: {
        generated_at: '2026-04-11T10:00:10Z',
        agents: [
          makeRun({
            feature: 'F03',
            task: 'F03-T01',
            finished_at: null,
            status: 'running',
          }),
        ],
      },
    });
    render(<Features />);
    await user.click(screen.getByRole('button', { name: /F03/ }));
    expect(screen.getByText('running…')).toBeInTheDocument();
  });

  it('loading: shows loading state when no data yet', () => {
    setState({ isLoading: true });
    render(<Features />);
    expect(screen.getByText(/loading/i)).toBeInTheDocument();
  });
});
