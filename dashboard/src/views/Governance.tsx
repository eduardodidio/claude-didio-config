import { motion } from 'framer-motion';
import { AlertTriangle, Shield, Flag, Clock } from 'lucide-react';
import { useGovernance } from '@/hooks/useGovernance';
import {
  Card,
  CardContent,
  CardHeader,
  CardTitle,
  CardDescription,
} from '@/components/ui/card';
import { Skeleton } from '@/components/ui/skeleton';
import type { PipelineRow, TokenBudgetSummary, FlagAnalytics } from '@/lib/governanceHelpers';
import type { HandlerKpis, GateKeeperKpis, MetaMetricsReport } from '@/lib/metaTypes';

// ---------------------------------------------------------------------------
// Utility
// ---------------------------------------------------------------------------

function fmtNum(value: number | null | undefined): string {
  return value === null || value === undefined ? '--' : String(value);
}

function fmtK(value: number): string {
  return value >= 1000 ? `${(value / 1000).toFixed(1)}K` : String(value);
}

// ---------------------------------------------------------------------------
// Skeleton
// ---------------------------------------------------------------------------

function GovernanceSkeleton() {
  return (
    <div data-testid="governance-skeleton" className="space-y-6">
      <Skeleton className="h-48 w-full" />
      <Skeleton className="h-40 w-full" />
      <Skeleton className="h-32 w-full" />
      <Skeleton className="h-40 w-full" />
    </div>
  );
}

// ---------------------------------------------------------------------------
// Section 1 -- Active Pipelines
// ---------------------------------------------------------------------------

interface PipelinesSectionProps {
  rows: PipelineRow[];
}

function PipelinesSection({ rows }: PipelinesSectionProps) {
  if (rows.length === 0) {
    return (
      <Card data-testid="pipelines-section">
        <CardHeader className="pb-2">
          <CardTitle className="text-base">Active Pipelines</CardTitle>
          <CardDescription>No active pipelines</CardDescription>
        </CardHeader>
        <CardContent>
          <p className="text-sm text-muted-foreground">
            No feature pipelines are currently running. Start a feature with{' '}
            <code className="text-xs bg-muted px-1 py-0.5 rounded">/create-feature</code>.
          </p>
        </CardContent>
      </Card>
    );
  }

  return (
    <Card data-testid="pipelines-section">
      <CardHeader className="pb-2">
        <CardTitle className="text-base">Active Pipelines</CardTitle>
        <CardDescription>{rows.length} pipeline(s) tracked</CardDescription>
      </CardHeader>
      <CardContent className="overflow-x-auto">
        {/* Desktop table */}
        <table className="hidden md:table w-full text-sm" data-testid="pipelines-table">
          <thead>
            <tr className="border-b text-left text-muted-foreground text-xs uppercase tracking-wide">
              <th className="pb-2 pr-4">Feature</th>
              <th className="pb-2 pr-4">Phase</th>
              <th className="pb-2 pr-4">Wave</th>
              <th className="pb-2 pr-4">Tasks</th>
              <th className="pb-2 pr-4">Progress</th>
              <th className="pb-2 pr-4">Token Budget</th>
              <th className="pb-2">Flags</th>
            </tr>
          </thead>
          <tbody>
            {rows.map((r) => (
              <tr key={r.feature} className="border-b border-border/50 last:border-0">
                <td className="py-2 pr-4 font-medium">{r.feature}</td>
                <td className="py-2 pr-4">{r.phase}</td>
                <td className="py-2 pr-4 tabular-nums">{r.wave ?? '--'}</td>
                <td className="py-2 pr-4 tabular-nums">
                  {r.completedTasks}/{r.totalTasks}
                </td>
                <td className="py-2 pr-4">
                  <div className="flex items-center gap-2">
                    <div className="h-2 w-20 rounded-full bg-muted overflow-hidden">
                      <div
                        className="h-full rounded-full bg-primary transition-all"
                        style={{ width: `${Math.min(r.progress, 100)}%` }}
                      />
                    </div>
                    <span className="tabular-nums text-xs">{r.progress}%</span>
                  </div>
                </td>
                <td className="py-2 pr-4 tabular-nums">
                  {fmtK(r.tokenUsed)}/{fmtK(r.tokenTotal)}
                </td>
                <td className="py-2 tabular-nums">
                  {r.flagCount > 0 ? (
                    <span className="text-amber-500 font-medium">{r.flagCount}</span>
                  ) : (
                    '0'
                  )}
                </td>
              </tr>
            ))}
          </tbody>
        </table>

        {/* Mobile cards */}
        <div className="md:hidden space-y-3" data-testid="pipelines-cards">
          {rows.map((r) => (
            <div
              key={r.feature}
              className="rounded-lg border border-border/50 p-3 space-y-2"
            >
              <div className="flex items-center justify-between">
                <span className="font-medium">{r.feature}</span>
                <span className="text-xs text-muted-foreground">{r.phase}</span>
              </div>
              <div className="flex items-center gap-2">
                <div className="h-2 flex-1 rounded-full bg-muted overflow-hidden">
                  <div
                    className="h-full rounded-full bg-primary transition-all"
                    style={{ width: `${Math.min(r.progress, 100)}%` }}
                  />
                </div>
                <span className="tabular-nums text-xs">{r.progress}%</span>
              </div>
              <div className="flex gap-4 text-xs text-muted-foreground">
                <span>Wave {r.wave ?? '--'}</span>
                <span>
                  Tasks {r.completedTasks}/{r.totalTasks}
                </span>
                <span>
                  Tokens {fmtK(r.tokenUsed)}/{fmtK(r.tokenTotal)}
                </span>
                {r.flagCount > 0 && (
                  <span className="text-amber-500">{r.flagCount} flag(s)</span>
                )}
              </div>
            </div>
          ))}
        </div>
      </CardContent>
    </Card>
  );
}

// ---------------------------------------------------------------------------
// Section 2 -- Token Budget
// ---------------------------------------------------------------------------

interface TokenBudgetSectionProps {
  budget: TokenBudgetSummary | null;
}

function TokenBudgetSection({ budget }: TokenBudgetSectionProps) {
  if (!budget) {
    return (
      <Card data-testid="token-budget-section">
        <CardHeader className="pb-2">
          <CardTitle className="text-base">Token Budget</CardTitle>
          <CardDescription>Data unavailable</CardDescription>
        </CardHeader>
        <CardContent>
          <p className="text-sm text-muted-foreground">
            Pipeline state is not available. Token budget data will appear once pipelines are active.
          </p>
        </CardContent>
      </Card>
    );
  }

  return (
    <Card data-testid="token-budget-section">
      <CardHeader className="pb-2">
        <CardTitle className="text-base flex items-center gap-2">
          Token Budget
          {budget.hasWarning && (
            <span
              data-testid="token-budget-warning"
              className="inline-flex items-center gap-1 rounded-full bg-amber-500/10 px-2 py-0.5 text-xs font-medium text-amber-600"
            >
              <AlertTriangle className="w-3 h-3" />
              Over 80%
            </span>
          )}
        </CardTitle>
        <CardDescription>
          Aggregate across {budget.perFeature.length} pipeline(s)
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-4">
        {/* Global budget bar */}
        <div className="space-y-1">
          <div className="flex items-center justify-between text-sm">
            <span className="text-muted-foreground">
              {fmtK(budget.totalConsumed)} / {fmtK(budget.totalAllocated)} tokens
            </span>
            <span className="tabular-nums font-medium">{budget.pctUsed.toFixed(1)}%</span>
          </div>
          <div className="h-3 w-full rounded-full bg-muted overflow-hidden">
            <div
              data-testid="token-budget-bar"
              className={`h-full rounded-full transition-all ${
                budget.pctUsed >= 80
                  ? 'bg-amber-500'
                  : budget.pctUsed >= 60
                    ? 'bg-yellow-500'
                    : 'bg-primary'
              }`}
              style={{ width: `${Math.min(budget.pctUsed, 100)}%` }}
            />
          </div>
          <div className="text-xs text-muted-foreground">
            {fmtK(budget.remaining)} tokens remaining
          </div>
        </div>

        {/* Per-feature breakdown */}
        {budget.perFeature.length > 1 && (
          <div className="space-y-2" data-testid="token-per-feature">
            <div className="text-xs text-muted-foreground uppercase tracking-wide">
              Per-feature breakdown
            </div>
            {budget.perFeature.map((pf) => (
              <div key={pf.feature} className="space-y-1">
                <div className="flex items-center justify-between text-xs">
                  <span className="font-medium">{pf.feature}</span>
                  <span className="tabular-nums text-muted-foreground">
                    {fmtK(pf.used)}/{fmtK(pf.total)} ({pf.pct.toFixed(0)}%)
                    {pf.pct >= 80 && (
                      <AlertTriangle className="inline w-3 h-3 ml-1 text-amber-500" />
                    )}
                  </span>
                </div>
                <div className="h-1.5 w-full rounded-full bg-muted overflow-hidden">
                  <div
                    className={`h-full rounded-full transition-all ${
                      pf.pct >= 80 ? 'bg-amber-500' : 'bg-primary/70'
                    }`}
                    style={{ width: `${Math.min(pf.pct, 100)}%` }}
                  />
                </div>
              </div>
            ))}
          </div>
        )}
      </CardContent>
    </Card>
  );
}

// ---------------------------------------------------------------------------
// Section 3 -- Flag Analytics
// ---------------------------------------------------------------------------

interface FlagAnalyticsSectionProps {
  analytics: FlagAnalytics;
}

function FlagAnalyticsSection({ analytics }: FlagAnalyticsSectionProps) {
  const typeEntries = Object.entries(analytics.byType);

  return (
    <Card data-testid="flag-analytics-section">
      <CardHeader className="pb-2">
        <CardTitle className="text-base flex items-center gap-2">
          <Flag className="w-4 h-4" />
          Flag Analytics
        </CardTitle>
        <CardDescription>Flags raised during active session</CardDescription>
      </CardHeader>
      <CardContent className="space-y-4">
        <div className="grid grid-cols-2 gap-4 md:grid-cols-4">
          <StatCard
            label="Total flags"
            value={analytics.total}
            testId="flag-total"
          />
          <StatCard
            label="Active"
            value={analytics.active}
            testId="flag-active"
          />
          <StatCard
            label="Critical (active)"
            value={analytics.critical}
            testId="flag-critical"
            highlight={analytics.critical > 0}
          />
          <StatCard
            label="Resolved"
            value={analytics.resolved}
            testId="flag-resolved"
          />
        </div>

        <div className="grid grid-cols-1 gap-4 md:grid-cols-2">
          {/* By severity */}
          <div data-testid="flag-by-severity" className="space-y-1">
            <div className="text-xs text-muted-foreground uppercase tracking-wide">
              By severity
            </div>
            {Object.entries(analytics.bySeverity).map(([severity, count]) => (
              <div
                key={severity}
                className="flex items-center justify-between text-sm"
              >
                <span className="text-muted-foreground">{severity}</span>
                <span className="tabular-nums font-medium">{count}</span>
              </div>
            ))}
          </div>

          {/* By type */}
          <div data-testid="flag-by-type" className="space-y-1">
            <div className="text-xs text-muted-foreground uppercase tracking-wide">
              By type
            </div>
            {typeEntries.length === 0 && (
              <span className="text-sm text-muted-foreground">No flags</span>
            )}
            {typeEntries.map(([type, count]) => (
              <div
                key={type}
                className="flex items-center justify-between text-sm"
              >
                <span className="text-muted-foreground">{type}</span>
                <span className="tabular-nums font-medium">{count}</span>
              </div>
            ))}
          </div>
        </div>
      </CardContent>
    </Card>
  );
}

// ---------------------------------------------------------------------------
// Section 4 -- Decision History
// ---------------------------------------------------------------------------

interface DecisionHistorySectionProps {
  metaMetrics: MetaMetricsReport | undefined;
}

function DecisionHistorySection({ metaMetrics }: DecisionHistorySectionProps) {
  const handler: HandlerKpis | undefined = metaMetrics?.handler;
  const gatekeeper: GateKeeperKpis | undefined = metaMetrics?.gatekeeper;
  const hasData =
    (handler && handler.total_decisions > 0) ||
    (gatekeeper && gatekeeper.total_reviews > 0);

  if (!hasData) {
    return (
      <Card data-testid="decision-history-section">
        <CardHeader className="pb-2">
          <CardTitle className="text-base flex items-center gap-2">
            <Clock className="w-4 h-4" />
            Decision History
          </CardTitle>
          <CardDescription>No data</CardDescription>
        </CardHeader>
        <CardContent>
          <p className="text-sm text-muted-foreground">
            No Handler/GateKeeper decisions have been recorded yet.
          </p>
        </CardContent>
      </Card>
    );
  }

  const typeDist = Object.entries(handler?.type_distribution ?? {});
  const statusDist = Object.entries(handler?.status_distribution ?? {});
  const verdictDist = Object.entries(gatekeeper?.verdict_distribution ?? {});

  return (
    <Card data-testid="decision-history-section">
      <CardHeader className="pb-2">
        <CardTitle className="text-base flex items-center gap-2">
          <Clock className="w-4 h-4" />
          Decision History
        </CardTitle>
        <CardDescription>Recent Handler / GateKeeper activity</CardDescription>
      </CardHeader>
      <CardContent className="space-y-4">
        <div className="grid grid-cols-2 gap-4 md:grid-cols-4">
          <StatCard
            label="Handler decisions"
            value={handler?.total_decisions ?? 0}
            testId="decision-handler-total"
          />
          <StatCard
            label="GateKeeper reviews"
            value={gatekeeper?.total_reviews ?? 0}
            testId="decision-gatekeeper-total"
          />
          <StatCard
            label="Avg handler latency (s)"
            value={handler?.avg_latency_secs ?? '--'}
            testId="decision-handler-latency"
          />
          <StatCard
            label="Avg confidence"
            value={gatekeeper?.avg_confidence ?? '--'}
            testId="decision-gatekeeper-confidence"
          />
        </div>

        <div className="grid grid-cols-1 gap-4 md:grid-cols-3">
          <div data-testid="decision-type-dist" className="space-y-1">
            <div className="text-xs text-muted-foreground uppercase tracking-wide">
              Decision types
            </div>
            {typeDist.length === 0 && (
              <span className="text-sm text-muted-foreground">No data</span>
            )}
            {typeDist.map(([name, count]) => (
              <div key={name} className="flex items-center justify-between text-sm">
                <span className="text-muted-foreground">{name}</span>
                <span className="tabular-nums font-medium">{count}</span>
              </div>
            ))}
          </div>

          <div data-testid="decision-status-dist" className="space-y-1">
            <div className="text-xs text-muted-foreground uppercase tracking-wide">
              Decision status
            </div>
            {statusDist.length === 0 && (
              <span className="text-sm text-muted-foreground">No data</span>
            )}
            {statusDist.map(([name, count]) => (
              <div key={name} className="flex items-center justify-between text-sm">
                <span className="text-muted-foreground">{name}</span>
                <span className="tabular-nums font-medium">{count}</span>
              </div>
            ))}
          </div>

          <div data-testid="decision-verdict-dist" className="space-y-1">
            <div className="text-xs text-muted-foreground uppercase tracking-wide">
              GateKeeper verdicts
            </div>
            {verdictDist.length === 0 && (
              <span className="text-sm text-muted-foreground">No data</span>
            )}
            {verdictDist.map(([name, count]) => (
              <div key={name} className="flex items-center justify-between text-sm">
                <span className="text-muted-foreground">{name}</span>
                <span className="tabular-nums font-medium">{count}</span>
              </div>
            ))}
          </div>
        </div>
      </CardContent>
    </Card>
  );
}

// ---------------------------------------------------------------------------
// Stat helper
// ---------------------------------------------------------------------------

interface StatCardProps {
  label: string;
  value: number | string;
  testId: string;
  highlight?: boolean;
}

function StatCard({ label, value, testId, highlight }: StatCardProps) {
  return (
    <div data-testid={testId} className="space-y-1">
      <div className="text-xs text-muted-foreground">{label}</div>
      <div
        className={`text-2xl font-semibold tabular-nums ${
          highlight ? 'text-red-500' : ''
        }`}
      >
        {typeof value === 'number' ? fmtNum(value) : value}
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Main component
// ---------------------------------------------------------------------------

export function Governance() {
  const gov = useGovernance();

  if (gov.isLoading) return <GovernanceSkeleton />;

  if (gov.isError) {
    return (
      <div
        role="alert"
        data-testid="governance-error"
        className="rounded-md border border-red-500/40 bg-red-500/10 p-4 text-red-600"
      >
        Failed to load governance data
        {gov.error ? `: ${gov.error.message}` : '.'}
      </div>
    );
  }

  return (
    <motion.div
      initial={{ opacity: 0, y: 6 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.2 }}
      className="space-y-6"
      data-testid="governance-view"
    >
      <div className="flex items-center gap-2 mb-2">
        <Shield className="w-5 h-5 text-primary" />
        <h1 className="text-lg font-semibold">Governance</h1>
      </div>

      <PipelinesSection rows={gov.pipelines} />
      <TokenBudgetSection budget={gov.tokenBudget} />
      <FlagAnalyticsSection analytics={gov.flagAnalytics} />
      <DecisionHistorySection metaMetrics={gov.metaMetrics} />
    </motion.div>
  );
}

export default Governance;
