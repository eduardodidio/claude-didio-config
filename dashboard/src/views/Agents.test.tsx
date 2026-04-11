import { describe, it, expect, vi } from 'vitest';
import { render, screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import type { AgentRun, DidioState } from '@/lib/types';

const fixture: DidioState = {
  generated_at: '2026-04-11T12:00:00Z',
  agents: [
    {
      feature: 'F01',
      role: 'developer',
      task: 'F01-T12',
      task_file: 'tasks/features/F01-dashboard/F01-T12.md',
      started_at: '2026-04-11T10:00:00Z',
      finished_at: '2026-04-11T10:00:30Z',
      status: 'completed',
      exit_code: 0,
      pid: 1,
      log: 'logs/agents/F01-T12.jsonl',
      phrase: 'A developer must have the best of intentions.',
    },
    {
      feature: 'F01',
      role: 'developer',
      task: 'F01-T11',
      task_file: 'tasks/features/F01-dashboard/F01-T11.md',
      started_at: '2026-04-11T09:00:00Z',
      finished_at: '2026-04-11T09:01:00Z',
      status: 'completed',
      exit_code: 0,
      pid: 2,
      log: 'logs/agents/F01-T11.jsonl',
      phrase: null,
    },
    {
      feature: 'F01',
      role: 'qa',
      task: 'F01-T06',
      task_file: 'tasks/features/F01-dashboard/F01-T06.md',
      started_at: '2026-04-11T08:00:00Z',
      finished_at: null,
      status: 'running',
      exit_code: null,
      pid: 3,
      log: 'logs/agents/F01-T06.jsonl',
      phrase: null,
    },
    {
      feature: 'F02',
      role: 'security',
      task: 'F02-T01',
      task_file: 'tasks/features/F02-other/F02-T01.md',
      started_at: '2026-04-11T07:00:00Z',
      finished_at: '2026-04-11T07:00:05Z',
      status: 'failed',
      exit_code: 1,
      pid: 4,
      log: 'logs/agents/F02-T01.jsonl',
      phrase: null,
    },
  ],
};

let mockData: { agents: AgentRun[] } | undefined = fixture;

vi.mock('@/hooks/useDidioState', () => ({
  useDidioState: () => ({ data: mockData, isLoading: false, error: null }),
}));

vi.mock('@/components/ui/tooltip', () => {
  const Pass = ({ children }: { children?: React.ReactNode }) => <>{children}</>;
  return {
    TooltipProvider: Pass,
    Tooltip: Pass,
    TooltipTrigger: Pass,
    TooltipContent: Pass,
  };
});

import { Agents } from './Agents';

const dataRows = () =>
  screen
    .getAllByRole('row')
    .slice(1)
    .filter((r) => !within(r).queryByText(/^no matches$/));

describe('Agents view', () => {
  beforeEach(() => {
    mockData = fixture;
  });

  it('happy: shows all rows with no filters', () => {
    render(<Agents />);
    expect(dataRows()).toHaveLength(4);
    expect(screen.getByText('F01-T12')).toBeInTheDocument();
    expect(screen.getByText('F02-T01')).toBeInTheDocument();
  });

  it('filter: selecting role=developer narrows to matching rows', async () => {
    const user = userEvent.setup();
    render(<Agents />);
    await user.selectOptions(screen.getByLabelText(/Filter by role/i), 'developer');
    const rows = dataRows();
    expect(rows).toHaveLength(2);
    for (const r of rows) {
      expect(within(r).getByText('developer')).toBeInTheDocument();
    }
    expect(screen.queryByText('F01-T06')).not.toBeInTheDocument();
    expect(screen.queryByText('F02-T01')).not.toBeInTheDocument();
  });

  it('edge: filter combination producing zero rows shows "no matches"', async () => {
    const user = userEvent.setup();
    render(<Agents />);
    await user.selectOptions(screen.getByLabelText(/Filter by role/i), 'qa');
    await user.selectOptions(screen.getByLabelText(/Filter by feature/i), 'F02');
    expect(screen.getByText('no matches')).toBeInTheDocument();
  });

  it('error: runs with missing exit_code render an em dash', () => {
    render(<Agents />);
    const runningRow = screen.getByText('F01-T06').closest('tr')!;
    const cells = within(runningRow).getAllByRole('cell');
    expect(cells[4]).toHaveTextContent('—');
  });

  it('boundary: with a single row, clicking task header is a visual no-op', async () => {
    mockData = { agents: [fixture.agents[0]] };
    const user = userEvent.setup();
    render(<Agents />);
    expect(dataRows()).toHaveLength(1);
    await user.click(screen.getByRole('button', { name: /task/i }));
    expect(dataRows()).toHaveLength(1);
    expect(screen.getByText('F01-T12')).toBeInTheDocument();
  });

  it('sort: default is started_at desc; clicking task toggles to alphabetical', async () => {
    const user = userEvent.setup();
    render(<Agents />);
    let tasks = dataRows().map((r) => within(r).getAllByRole('cell')[1].textContent);
    expect(tasks).toEqual(['F01-T12', 'F01-T11', 'F01-T06', 'F02-T01']);
    await user.click(screen.getByRole('button', { name: /task/i }));
    tasks = dataRows().map((r) => within(r).getAllByRole('cell')[1].textContent);
    expect(tasks).toEqual(['F01-T06', 'F01-T11', 'F01-T12', 'F02-T01']);
  });
});
