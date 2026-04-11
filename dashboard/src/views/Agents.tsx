import { useMemo, useState } from 'react';
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table';
import { Badge } from '@/components/ui/badge';
import {
  Tooltip,
  TooltipContent,
  TooltipProvider,
  TooltipTrigger,
} from '@/components/ui/tooltip';
import { useDidioState } from '@/hooks/useDidioState';
import type { AgentRun, AgentStatus } from '@/lib/types';
import { cn } from '@/lib/utils';
import { AgentRunDialog } from '@/components/AgentRunDialog';

const STATUS_DOT: Record<AgentStatus, string> = {
  running: 'bg-blue-500',
  completed: 'bg-green-500',
  failed: 'bg-red-500',
  blocked: 'bg-yellow-500',
};

function humanizeDuration(run: AgentRun): string {
  if (!run.finished_at) return '—';
  const start = Date.parse(run.started_at);
  const end = Date.parse(run.finished_at);
  if (Number.isNaN(start) || Number.isNaN(end)) return '—';
  const ms = Math.max(0, end - start);
  if (ms < 1000) return `${ms}ms`;
  const s = ms / 1000;
  if (s < 60) return `${s.toFixed(1)}s`;
  const m = Math.floor(s / 60);
  const rem = Math.round(s - m * 60);
  return `${m}m ${rem}s`;
}

function truncate(text: string, max: number): string {
  return text.length > max ? `${text.slice(0, max - 1)}…` : text;
}

type SortMode = 'started_desc' | 'task_alpha';

export function Agents() {
  const { data } = useDidioState();
  const runs: AgentRun[] = useMemo(() => data?.agents ?? [], [data]);

  const [roleFilter, setRoleFilter] = useState<string>('');
  const [featureFilter, setFeatureFilter] = useState<string>('');
  const [statusFilter, setStatusFilter] = useState<string>('');
  const [sort, setSort] = useState<SortMode>('started_desc');
  const [selectedRun, setSelectedRun] = useState<AgentRun | null>(null);

  const roles = useMemo(
    () => Array.from(new Set(runs.map((r) => r.role))).sort(),
    [runs],
  );
  const features = useMemo(
    () => Array.from(new Set(runs.map((r) => r.feature))).sort(),
    [runs],
  );
  const statuses = useMemo(
    () => Array.from(new Set(runs.map((r) => r.status))).sort(),
    [runs],
  );

  const visible = useMemo(() => {
    const filtered = runs.filter(
      (r) =>
        (!roleFilter || r.role === roleFilter) &&
        (!featureFilter || r.feature === featureFilter) &&
        (!statusFilter || r.status === statusFilter),
    );
    const sorted = [...filtered];
    if (sort === 'task_alpha') {
      sorted.sort((a, b) => a.task.localeCompare(b.task));
    } else {
      sorted.sort((a, b) => b.started_at.localeCompare(a.started_at));
    }
    return sorted;
  }, [runs, roleFilter, featureFilter, statusFilter, sort]);

  const toggleTaskSort = () =>
    setSort((s) => (s === 'task_alpha' ? 'started_desc' : 'task_alpha'));

  return (
    <TooltipProvider>
      <div className="space-y-4 p-6">
        <h1 className="text-2xl font-semibold">Agents</h1>

        <div className="flex flex-wrap gap-3">
          <select
            aria-label="Filter by role"
            value={roleFilter}
            onChange={(e) => setRoleFilter(e.target.value)}
            className="rounded-md border bg-background px-3 py-2 text-sm"
          >
            <option value="">All roles</option>
            {roles.map((r) => (
              <option key={r} value={r}>
                {r}
              </option>
            ))}
          </select>

          <select
            aria-label="Filter by feature"
            value={featureFilter}
            onChange={(e) => setFeatureFilter(e.target.value)}
            className="rounded-md border bg-background px-3 py-2 text-sm"
          >
            <option value="">All features</option>
            {features.map((f) => (
              <option key={f} value={f}>
                {f}
              </option>
            ))}
          </select>

          <select
            aria-label="Filter by status"
            value={statusFilter}
            onChange={(e) => setStatusFilter(e.target.value)}
            className="rounded-md border bg-background px-3 py-2 text-sm"
          >
            <option value="">All statuses</option>
            {statuses.map((s) => (
              <option key={s} value={s}>
                {s}
              </option>
            ))}
          </select>
        </div>

        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>role</TableHead>
              <TableHead>
                <button
                  type="button"
                  onClick={toggleTaskSort}
                  className="font-medium text-muted-foreground hover:text-foreground"
                >
                  task {sort === 'task_alpha' ? '▲' : '▾'}
                </button>
              </TableHead>
              <TableHead>status</TableHead>
              <TableHead>duration</TableHead>
              <TableHead>exit</TableHead>
              <TableHead>phrase</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {visible.length === 0 ? (
              <TableRow>
                <TableCell colSpan={6} className="text-center text-muted-foreground">
                  no matches
                </TableCell>
              </TableRow>
            ) : (
              visible.map((run) => {
                const phrase = run.phrase ?? '';
                const phraseShort = truncate(phrase, 30);
                return (
                  <TableRow
                    key={`${run.feature}-${run.task}-${run.started_at}`}
                    data-testid="agent-row"
                    onClick={() => setSelectedRun(run)}
                    className="cursor-pointer hover:bg-accent/50"
                  >
                    <TableCell>{run.role}</TableCell>
                    <TableCell>{run.task}</TableCell>
                    <TableCell>
                      <span className="inline-flex items-center gap-2">
                        <span
                          aria-label={run.status}
                          className={cn('h-2 w-2 rounded-full', STATUS_DOT[run.status])}
                        />
                        {run.status}
                      </span>
                    </TableCell>
                    <TableCell>{humanizeDuration(run)}</TableCell>
                    <TableCell>
                      {run.exit_code === null || run.exit_code === undefined
                        ? '—'
                        : run.exit_code}
                    </TableCell>
                    <TableCell onClick={(e) => e.stopPropagation()}>
                      {phrase ? (
                        <Tooltip>
                          <TooltipTrigger asChild>
                            <Badge variant="outline" className="cursor-default">
                              {phraseShort}
                            </Badge>
                          </TooltipTrigger>
                          <TooltipContent>{phrase}</TooltipContent>
                        </Tooltip>
                      ) : (
                        <span className="text-muted-foreground">—</span>
                      )}
                    </TableCell>
                  </TableRow>
                );
              })
            )}
          </TableBody>
        </Table>

        <AgentRunDialog
          run={selectedRun}
          open={selectedRun !== null}
          onOpenChange={(o) => {
            if (!o) setSelectedRun(null);
          }}
        />
      </div>
    </TooltipProvider>
  );
}

export default Agents;
