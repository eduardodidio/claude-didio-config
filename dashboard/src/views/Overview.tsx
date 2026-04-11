import { motion } from 'framer-motion';
import { useDidioState } from '@/hooks/useDidioState';
import {
  Card,
  CardContent,
  CardHeader,
  CardTitle,
  CardDescription,
} from '@/components/ui/card';
import { Skeleton } from '@/components/ui/skeleton';
import { computeOverviewStats, latestPhrase } from '@/lib/selectors';
import type { AgentRun, AgentStatus, DidioState } from '@/lib/types';

const STATUS_COLOR: Record<AgentStatus, string> = {
  running: 'bg-didio text-didio-foreground',
  completed: 'bg-emerald-500 text-white',
  failed: 'bg-red-500 text-white',
  blocked: 'bg-amber-500 text-black',
};

function formatElapsed(fromIso: string): string {
  const then = new Date(fromIso).getTime();
  if (Number.isNaN(then)) return '—';
  const deltaSec = Math.max(0, Math.floor((Date.now() - then) / 1000));
  if (deltaSec < 60) return `${deltaSec}s ago`;
  const m = Math.floor(deltaSec / 60);
  if (m < 60) return `${m}m ago`;
  const h = Math.floor(m / 60);
  if (h < 24) return `${h}h ago`;
  return `${Math.floor(h / 24)}d ago`;
}

function pickLatestPhraseRun(state: DidioState): AgentRun | null {
  const withPhrase = state.agents.filter(
    (r): r is AgentRun & { phrase: string } =>
      typeof r.phrase === 'string' && r.phrase.length > 0,
  );
  if (withPhrase.length === 0) return null;
  return [...withPhrase].sort((a, b) =>
    b.started_at.localeCompare(a.started_at),
  )[0];
}

interface StatCardProps {
  label: string;
  value: number;
  testId: string;
}

function StatCard({ label, value, testId }: StatCardProps) {
  return (
    <Card data-testid={testId}>
      <CardHeader className="pb-2">
        <CardDescription>{label}</CardDescription>
      </CardHeader>
      <CardContent>
        <div className="text-3xl font-semibold tabular-nums">{value}</div>
      </CardContent>
    </Card>
  );
}

function OverviewSkeleton() {
  return (
    <div data-testid="overview-skeleton" className="space-y-6">
      <div className="grid grid-cols-2 gap-4 md:grid-cols-4">
        {Array.from({ length: 4 }).map((_, i) => (
          <Skeleton key={i} className="h-24 w-full" />
        ))}
      </div>
      <Skeleton className="h-14 w-full" />
      <Skeleton className="h-32 w-full" />
    </div>
  );
}

export function Overview() {
  const query = useDidioState();

  if (query.isLoading) return <OverviewSkeleton />;

  if (query.isError || !query.data) {
    return (
      <div
        role="alert"
        data-testid="overview-error"
        className="rounded-md border border-red-500/40 bg-red-500/10 p-4 text-red-600"
      >
        Failed to load dashboard state
        {query.error instanceof Error ? `: ${query.error.message}` : '.'}
      </div>
    );
  }

  const state = query.data;
  const stats = computeOverviewStats(state);
  const phrase = latestPhrase(state);
  const phraseRun = pickLatestPhraseRun(state);

  const timelineRuns = [...state.agents]
    .sort((a, b) => a.started_at.localeCompare(b.started_at))
    .slice(-20);

  return (
    <div className="space-y-6">
      <div
        className="grid grid-cols-2 gap-4 md:grid-cols-4"
        data-testid="overview-cards"
      >
        <StatCard
          label="Active features"
          value={stats.activeFeatures}
          testId="card-active-features"
        />
        <StatCard
          label="Running"
          value={stats.running}
          testId="card-running"
        />
        <StatCard
          label="Completed"
          value={stats.completed}
          testId="card-completed"
        />
        <StatCard label="Failed" value={stats.failed} testId="card-failed" />
      </div>

      <Card>
        <CardHeader className="pb-2">
          <CardTitle className="text-base">Recent runs</CardTitle>
          <CardDescription>
            Last {timelineRuns.length} of {state.agents.length}
          </CardDescription>
        </CardHeader>
        <CardContent>
          <div
            data-testid="overview-timeline"
            className="flex flex-wrap gap-2"
          >
            {timelineRuns.map((run, idx) => (
              <motion.div
                key={`${run.task}-${run.started_at}`}
                initial={{ opacity: 0, y: 6 }}
                animate={{ opacity: 1, y: 0 }}
                transition={{ delay: idx * 0.02, duration: 0.2 }}
                className={`didio-glow rounded-full px-3 py-1 text-xs font-medium ${STATUS_COLOR[run.status]}`}
                title={`${run.task} · ${run.role} · ${run.status}`}
                data-testid="timeline-pill"
              >
                {run.task}
              </motion.div>
            ))}
            {timelineRuns.length === 0 && (
              <span className="text-sm text-muted-foreground">
                No runs yet
              </span>
            )}
          </div>
        </CardContent>
      </Card>

      <Card data-testid="latest-phrase-card" className="didio-glow">
        <CardHeader>
          <CardDescription>Latest phrase</CardDescription>
          <CardTitle className="text-xl leading-snug">
            {phrase ? `"${phrase.phrase}"` : 'No phrases yet'}
          </CardTitle>
        </CardHeader>
        {phrase && phraseRun && (
          <CardContent className="flex items-center justify-between text-sm text-muted-foreground">
            <span className="uppercase tracking-wide">{phrase.role}</span>
            <span>{formatElapsed(phraseRun.started_at)}</span>
          </CardContent>
        )}
      </Card>
    </div>
  );
}

export default Overview;
