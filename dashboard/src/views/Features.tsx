import { useState, useMemo } from 'react';
import { AnimatePresence, motion } from 'framer-motion';
import { ChevronDown } from 'lucide-react';
import { useDidioState } from '@/hooks/useDidioState';
import { groupByFeature } from '@/lib/selectors';
import { getAggregateDot, getStatusDot, getTrailChipClasses, getTrailGlyph } from '@/lib/statusStyles';
import { Card, CardContent, CardHeader } from '@/components/ui/card';
import { Progress } from '@/components/ui/progress';
import { AgentRunDialog } from '@/components/AgentRunDialog';
import type { AgentRun, FeatureGroup } from '@/lib/types';

function shortTask(task: string): string {
  const parts = task.split('-');
  return parts[parts.length - 1] ?? task;
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

  const groups: FeatureGroup[] = useMemo(
    () => (data ? groupByFeature(data).filter((g) => g.runs.length > 0) : []),
    [data],
  );

  const features = useMemo(() => data?.features ?? [], [data]);

  const featureMap = useMemo(
    () => new Map(features.map((f) => [f.feature, f])),
    [features],
  );

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
          const progress = featureMap.get(group.feature);
          const percent = progress?.percent ?? 0;
          const fraction = progress
            ? `${progress.completed}/${progress.total}`
            : `${group.runs.length} task${group.runs.length === 1 ? '' : 's'}`;
          return (
            <Card key={group.feature} data-testid={`feature-card-${group.feature}`}>
              <CardHeader className="p-4 space-y-3">
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
                  <div className="flex items-center gap-3 flex-wrap">
                    <span
                      className={`inline-block w-2.5 h-2.5 rounded-full ${getAggregateDot(
                        group.runs,
                      )}`}
                      aria-label="aggregate status"
                    />
                    <span className="font-mono text-sm font-semibold text-primary">
                      {group.feature}
                    </span>
                    <span className="text-xs text-muted-foreground">
                      {fraction} · {percent}%
                    </span>
                    {progress?.current_task && (
                      <span className="text-xs font-mono rounded-md border border-amber-500/40 bg-amber-500/10 px-2 py-0.5 text-amber-500">
                        ▶ {progress.current_task}
                        {progress.current_wave !== null && ` · Wave ${progress.current_wave}`}
                      </span>
                    )}
                  </div>
                  <ChevronDown
                    className={`w-4 h-4 text-muted-foreground transition-transform ${
                      isOpen ? 'rotate-180' : ''
                    }`}
                  />
                </button>
                <Progress value={percent} aria-label={`${group.feature} progress`} />
                {progress && progress.trail.length > 0 && (
                  <div
                    className="flex flex-wrap gap-1"
                    data-testid={`feature-trail-${group.feature}`}
                  >
                    {progress.trail.map((item) => (
                      <span
                        key={item.task}
                        title={`${item.task}${item.wave !== null ? ` · Wave ${item.wave}` : ''} · ${item.status}`}
                        className={`inline-flex items-center gap-1 rounded border px-1.5 py-0.5 text-[10px] font-mono ${getTrailChipClasses(item.status)}`}
                      >
                        <span>{getTrailGlyph(item.status)}</span>
                        <span>{shortTask(item.task)}</span>
                      </span>
                    ))}
                  </div>
                )}
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
                        {group.runs.map((run) => (
                          <li key={`${run.task}-${run.started_at}-${run.pid}`}>
                            <button
                              type="button"
                              onClick={() => setSelectedRun(run)}
                              data-testid="feature-run-row"
                              className="flex w-full items-center gap-3 rounded-md px-2 py-1.5 text-left text-sm font-mono hover:bg-accent/50 cursor-pointer"
                              title={run.phrase ?? `${run.role} · ${run.task}`}
                            >
                              <span
                                className={`inline-block w-2 h-2 rounded-full ${getStatusDot(
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
