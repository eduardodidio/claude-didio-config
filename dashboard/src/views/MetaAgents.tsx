import { motion } from 'framer-motion';
import { useMetaMetrics } from '@/hooks/useMetaMetrics';
import {
  Card,
  CardContent,
  CardHeader,
  CardTitle,
  CardDescription,
} from '@/components/ui/card';
import { Skeleton } from '@/components/ui/skeleton';
import type {
  BiasName,
  HandlerKpis,
  LoopHealthKpis,
  GateKeeperKpis,
  Verdict,
} from '@/lib/metaTypes';

const BIASES: readonly BiasName[] = [
  'sunk_cost',
  'anchoring',
  'scope_creep',
  'optimism',
  'recency',
];

const VERDICTS: readonly Verdict[] = ['agree', 'challenge', 'escalate'];

function fmtNum(value: number | null | undefined): string {
  return value === null || value === undefined ? '—' : String(value);
}

function fmtPct(value: number | null | undefined): string {
  return value === null || value === undefined
    ? '—'
    : `${(value * 100).toFixed(1)}%`;
}

interface StatProps {
  label: string;
  value: string;
  testId: string;
}

function Stat({ label, value, testId }: StatProps) {
  return (
    <div data-testid={testId} className="space-y-1">
      <div className="text-xs text-muted-foreground">{label}</div>
      <div className="text-2xl font-semibold tabular-nums">{value}</div>
    </div>
  );
}

interface DistRowProps {
  name: string;
  count: number;
}

function DistRow({ name, count }: DistRowProps) {
  return (
    <div className="flex items-center justify-between text-sm">
      <span className="text-muted-foreground">{name}</span>
      <span className="tabular-nums font-medium">{count}</span>
    </div>
  );
}

function MetaAgentsSkeleton() {
  return (
    <div data-testid="meta-agents-skeleton" className="space-y-6">
      <Skeleton className="h-40 w-full" />
      <Skeleton className="h-40 w-full" />
      <Skeleton className="h-32 w-full" />
    </div>
  );
}

interface HandlerSectionProps {
  kpis: HandlerKpis;
}

function HandlerSection({ kpis }: HandlerSectionProps) {
  const typeDist = Object.entries(kpis.type_distribution ?? {});
  const statusDist = Object.entries(kpis.status_distribution ?? {});

  return (
    <Card data-testid="handler-section">
      <CardHeader className="pb-2">
        <CardTitle className="text-base">Handler (Orchestrator)</CardTitle>
        <CardDescription>Decision KPIs</CardDescription>
      </CardHeader>
      <CardContent className="space-y-4">
        <div className="grid grid-cols-2 gap-4 md:grid-cols-5">
          <Stat
            label="Total decisions"
            value={fmtNum(kpis.total_decisions)}
            testId="handler-total-decisions"
          />
          <Stat
            label="Avg latency (s)"
            value={fmtNum(kpis.avg_latency_secs)}
            testId="handler-avg-latency"
          />
          <Stat
            label="Min latency (s)"
            value={fmtNum(kpis.min_latency_secs)}
            testId="handler-min-latency"
          />
          <Stat
            label="Avg options"
            value={fmtNum(kpis.avg_options_considered)}
            testId="handler-avg-options"
          />
          <Stat
            label="Avg actions"
            value={fmtNum(kpis.avg_actions_per_decision)}
            testId="handler-avg-actions"
          />
        </div>
        <div className="grid grid-cols-1 gap-4 md:grid-cols-2">
          <div data-testid="handler-type-distribution" className="space-y-1">
            <div className="text-xs text-muted-foreground uppercase tracking-wide">
              Type distribution
            </div>
            {typeDist.length === 0 && (
              <span className="text-sm text-muted-foreground">No data</span>
            )}
            {typeDist.map(([name, count]) => (
              <DistRow key={name} name={name} count={count} />
            ))}
          </div>
          <div data-testid="handler-status-distribution" className="space-y-1">
            <div className="text-xs text-muted-foreground uppercase tracking-wide">
              Status distribution
            </div>
            {statusDist.length === 0 && (
              <span className="text-sm text-muted-foreground">No data</span>
            )}
            {statusDist.map(([name, count]) => (
              <DistRow key={name} name={name} count={count} />
            ))}
          </div>
        </div>
      </CardContent>
    </Card>
  );
}

interface GateKeeperSectionProps {
  kpis: GateKeeperKpis;
}

function GateKeeperSection({ kpis }: GateKeeperSectionProps) {
  const verdictDist = kpis.verdict_distribution ?? {};
  const verdictRates = kpis.verdict_rates ?? {};
  const biasFreq = kpis.bias_frequency ?? {};

  return (
    <Card data-testid="gatekeeper-section">
      <CardHeader className="pb-2">
        <CardTitle className="text-base">GateKeeper (Governance)</CardTitle>
        <CardDescription>Governance review KPIs</CardDescription>
      </CardHeader>
      <CardContent className="space-y-4">
        <div className="grid grid-cols-2 gap-4 md:grid-cols-4">
          <Stat
            label="Total reviews"
            value={fmtNum(kpis.total_reviews)}
            testId="gatekeeper-total-reviews"
          />
          <Stat
            label="Avg confidence"
            value={fmtNum(kpis.avg_confidence)}
            testId="gatekeeper-avg-confidence"
          />
          <Stat
            label="Avg blind spots"
            value={fmtNum(kpis.avg_blind_spots)}
            testId="gatekeeper-avg-blind-spots"
          />
          <Stat
            label="Avg risks"
            value={fmtNum(kpis.avg_risks)}
            testId="gatekeeper-avg-risks"
          />
        </div>
        <Stat
          label="Avg decision→governance latency (s)"
          value={fmtNum(kpis.avg_decision_to_governance_latency_secs)}
          testId="gatekeeper-avg-decision-latency"
        />
        <div data-testid="gatekeeper-verdict-distribution" className="space-y-1">
          <div className="text-xs text-muted-foreground uppercase tracking-wide">
            Verdicts
          </div>
          {VERDICTS.map((verdict) => (
            <div
              key={verdict}
              className="flex items-center justify-between text-sm"
              data-testid={`gatekeeper-verdict-${verdict}`}
            >
              <span className="text-muted-foreground">{verdict}</span>
              <span className="tabular-nums font-medium">
                {fmtNum(verdictDist[verdict])} ({fmtPct(verdictRates[verdict])})
              </span>
            </div>
          ))}
        </div>
        <div data-testid="gatekeeper-bias-frequency" className="space-y-1">
          <div className="text-xs text-muted-foreground uppercase tracking-wide">
            Bias frequency
          </div>
          {BIASES.map((bias) => (
            <DistRow key={bias} name={bias} count={biasFreq[bias] ?? 0} />
          ))}
        </div>
      </CardContent>
    </Card>
  );
}

interface LoopHealthSectionProps {
  kpis: LoopHealthKpis;
}

function LoopHealthSection({ kpis }: LoopHealthSectionProps) {
  return (
    <Card data-testid="loop-health-section">
      <CardHeader className="pb-2">
        <CardTitle className="text-base">Loop health</CardTitle>
        <CardDescription>Handler ↔ GateKeeper feedback loop</CardDescription>
      </CardHeader>
      <CardContent>
        <div className="grid grid-cols-2 gap-4 md:grid-cols-4">
          <Stat
            label="Challenge round-trips"
            value={fmtNum(kpis.challenge_round_trips)}
            testId="loop-challenge-round-trips"
          />
          <Stat
            label="Blocking escalations"
            value={fmtNum(kpis.blocking_escalations)}
            testId="loop-blocking-escalations"
          />
          <Stat
            label="Auto-reviewed %"
            value={fmtPct(kpis.auto_reviewed_pct)}
            testId="loop-auto-reviewed-pct"
          />
          <Stat
            label="Decisions w/o governance"
            value={fmtNum(kpis.decisions_without_governance)}
            testId="loop-decisions-without-governance"
          />
        </div>
      </CardContent>
    </Card>
  );
}

export function MetaAgents() {
  const query = useMetaMetrics();

  if (query.isLoading) return <MetaAgentsSkeleton />;

  if (query.isError || !query.data) {
    return (
      <div
        role="alert"
        data-testid="meta-agents-error"
        className="rounded-md border border-red-500/40 bg-red-500/10 p-4 text-red-600"
      >
        Failed to load meta-agent metrics
        {query.error instanceof Error ? `: ${query.error.message}` : '.'}
      </div>
    );
  }

  const report = query.data;
  const handler = report.handler ?? ({} as HandlerKpis);
  const gatekeeper = report.gatekeeper ?? ({} as GateKeeperKpis);
  const loopHealth = report.loop_health ?? ({} as LoopHealthKpis);

  return (
    <motion.div
      initial={{ opacity: 0, y: 6 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.2 }}
      className="space-y-6"
      data-testid="meta-agents-view"
    >
      <HandlerSection kpis={handler} />
      <GateKeeperSection kpis={gatekeeper} />
      <LoopHealthSection kpis={loopHealth} />
    </motion.div>
  );
}

export default MetaAgents;
