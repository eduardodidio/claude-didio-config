import { useState } from 'react';
import { AnimatePresence, motion } from 'framer-motion';
import { ChevronDown } from 'lucide-react';
import { useDidioState } from '@/hooks/useDidioState';
import { groupByFeature } from '@/lib/selectors';
import { Card, CardContent, CardHeader } from '@/components/ui/card';
import { AgentRunDialog } from '@/components/AgentRunDialog';
import type { AgentRun, FeatureGroup } from '@/lib/types';

function aggregateStatusColor(runs: AgentRun[]): string {
  if (runs.some((r) => r.status === 'failed')) return 'bg-red-500';
  if (runs.some((r) => r.status === 'running')) return 'bg-amber-500';
  return 'bg-emerald-500';
}

function runStatusColor(status: AgentRun['status']): string {
  if (status === 'failed') return 'bg-red-500';
  if (status === 'running') return 'bg-amber-500';
  if (status === 'blocked') return 'bg-orange-500';
  return 'bg-emerald-500';
}

function formatDuration(run: AgentRun): string {
  if (!run.finished_at) return 'running…';
  const start = Date.parse(run.started_at);
  const end = Date.parse(run.finished_at);
  if (Number.isNaN(start) || Number.isNaN(end)) return '—';
  const ms = Math.max(0, end - start);
  if (ms < 1000) return `${ms}ms`;
  const s = ms / 1000;
  if (s < 60) return `${s.toFixed(1)}s`;
  const m = Math.floor(s / 60);
  const rs = Math.round(s - m * 60);
  return `${m}m ${rs}s`;
}

export function Features() {
  const { data, isLoading, error } = useDidioState();
  const [open, setOpen] = useState<Record<string, boolean>>({});
  const [selectedRun, setSelectedRun] = useState<AgentRun | null>(null);

  if (error) {
    return (
      <div role="alert" className="p-6 text-sm text-red-500">
        Failed to load state: {(error as Error).message}
      </div>
    );
  }
  if (isLoading || !data) {
    return <div className="p-6 text-sm text-muted-foreground">Loading…</div>;
  }

  const groups: FeatureGroup[] = groupByFeature(data).filter(
    (g) => g.runs.length > 0,
  );

  if (groups.length === 0) {
    return (
      <div className="p-6 text-sm text-muted-foreground">
        No features yet. Spawn an agent to see runs grouped here.
      </div>
    );
  }

  return (
    <div className="p-6 space-y-4">
      <h1 className="text-2xl font-semibold tracking-tight">Features</h1>
      <div className="space-y-3">
        {groups.map((group) => {
          const isOpen = !!open[group.feature];
          const sortedRuns = [...group.runs].sort((a, b) =>
            a.started_at.localeCompare(b.started_at),
          );
          return (
            <Card key={group.feature} data-testid={`feature-card-${group.feature}`}>
              <CardHeader className="p-4">
                <button
                  type="button"
                  aria-expanded={isOpen}
                  aria-controls={`feature-body-${group.feature}`}
                  onClick={() =>
                    setOpen((prev) => ({
                      ...prev,
                      [group.feature]: !prev[group.feature],
                    }))
                  }
                  className="flex items-center justify-between w-full text-left"
                >
                  <div className="flex items-center gap-3">
                    <span
                      className={`inline-block w-2.5 h-2.5 rounded-full ${aggregateStatusColor(
                        group.runs,
                      )}`}
                      aria-label="aggregate status"
                    />
                    <span className="font-mono text-sm font-semibold text-primary">
                      {group.feature}
                    </span>
                    <span className="text-xs text-muted-foreground">
                      {group.runs.length} task{group.runs.length === 1 ? '' : 's'}
                    </span>
                  </div>
                  <ChevronDown
                    className={`w-4 h-4 text-muted-foreground transition-transform ${
                      isOpen ? 'rotate-180' : ''
                    }`}
                  />
                </button>
              </CardHeader>
              <AnimatePresence initial={false}>
                {isOpen && (
                  <motion.div
                    key="content"
                    id={`feature-body-${group.feature}`}
                    initial={{ height: 0, opacity: 0 }}
                    animate={{ height: 'auto', opacity: 1 }}
                    exit={{ height: 0, opacity: 0 }}
                    transition={{ duration: 0.18 }}
                    className="overflow-hidden"
                  >
                    <CardContent className="p-4 pt-0">
                      <ul className="space-y-1" data-testid={`feature-runs-${group.feature}`}>
                        {sortedRuns.map((run) => (
                          <li key={`${run.task}-${run.started_at}-${run.pid}`}>
                            <button
                              type="button"
                              onClick={() => setSelectedRun(run)}
                              data-testid="feature-run-row"
                              className="flex w-full items-center gap-3 rounded-md px-2 py-1.5 text-left text-sm font-mono hover:bg-accent/50 cursor-pointer"
                              title={run.phrase ?? `${run.role} · ${run.task}`}
                            >
                              <span
                                className={`inline-block w-2 h-2 rounded-full ${runStatusColor(
                                  run.status,
                                )}`}
                                aria-label={run.status}
                              />
                              <span className="text-primary">{run.role}</span>
                              <span className="text-muted-foreground">·</span>
                              <span className="truncate">{run.task}</span>
                              <span className="text-muted-foreground">·</span>
                              <span className="text-xs text-muted-foreground">
                                {run.status}
                              </span>
                              <span className="text-muted-foreground">·</span>
                              <span className="text-xs text-muted-foreground">
                                {formatDuration(run)}
                              </span>
                              {run.phrase && (
                                <span className="ml-auto truncate text-xs italic text-muted-foreground/80">
                                  "{run.phrase}"
                                </span>
                              )}
                            </button>
                          </li>
                        ))}
                      </ul>
                    </CardContent>
                  </motion.div>
                )}
              </AnimatePresence>
            </Card>
          );
        })}
      </div>

      <AgentRunDialog
        run={selectedRun}
        open={selectedRun !== null}
        onOpenChange={(o) => {
          if (!o) setSelectedRun(null);
        }}
      />
    </div>
  );
}

export default Features;
