import type {
  BiasName,
  DecisionRecord,
  GandalfKpis,
  GovernanceReport,
  LoopHealthKpis,
  MetaMetricsReport,
  MetaRunState,
  SarumanKpis,
  Verdict,
} from './metaTypes';

const VERDICTS: readonly Verdict[] = ['agree', 'challenge', 'escalate'];
const BIASES: readonly BiasName[] = [
  'sunk_cost',
  'anchoring',
  'scope_creep',
  'optimism',
  'recency',
];

function round2(value: number): number {
  return Math.round(value * 100) / 100;
}

function avg(values: number[]): number | null {
  if (values.length === 0) return null;
  return round2(values.reduce((sum, v) => sum + v, 0) / values.length);
}

function min(values: number[]): number | null {
  if (values.length === 0) return null;
  return Math.min(...values);
}

function countBy<T extends string>(items: T[]): Record<string, number> {
  const counts: Record<string, number> = {};
  for (const item of items) {
    counts[item] = (counts[item] ?? 0) + 1;
  }
  return counts;
}

function secondsBetween(startIso: string, endIso: string): number {
  return (new Date(endIso).getTime() - new Date(startIso).getTime()) / 1000;
}

function findRunsByDecision(
  runs: MetaRunState[],
  role: string,
  decisionId: string,
): MetaRunState[] {
  return runs.filter((r) => r.role === role && r.task.includes(decisionId));
}

/**
 * Fallback join when no run.task carries the decision id: pick the run of
 * `role` whose `finished_at` is chronologically closest to `anchorIso`
 * (per brief shard 03 §A "fallback: nearest finished_at").
 */
function nearestRunByFinishedAt(
  runs: MetaRunState[],
  role: string,
  anchorIso: string,
): MetaRunState | undefined {
  const anchor = new Date(anchorIso).getTime();
  const candidates = runs.filter((r) => r.role === role && r.finished_at);
  if (candidates.length === 0) return undefined;
  return candidates.reduce((closest, r) => {
    const d = Math.abs(new Date(r.finished_at as string).getTime() - anchor);
    const dClosest = Math.abs(
      new Date(closest.finished_at as string).getTime() - anchor,
    );
    return d < dClosest ? r : closest;
  });
}

export function computeMetaMetrics(input: {
  decisions: DecisionRecord[];
  governance: GovernanceReport[];
  runs: MetaRunState[];
  autoGovernance?: boolean;
  now?: string;
}): MetaMetricsReport {
  const { decisions, governance, runs } = input;
  const autoGovernance = input.autoGovernance ?? true;
  const generated_at = input.now ?? new Date().toISOString();

  const governanceByDecisionId = new Map<string, GovernanceReport>();
  for (const g of governance) {
    if (g.decision_id) governanceByDecisionId.set(g.decision_id, g);
  }

  // ---- Gandalf ----
  const gandalfLatencies: number[] = [];
  for (const d of decisions) {
    const run = findRunsByDecision(runs, 't800', d.decision_id)[0];
    if (run && run.finished_at) {
      gandalfLatencies.push(secondsBetween(run.started_at, run.finished_at));
    }
  }

  const gandalf: GandalfKpis = {
    total_decisions: decisions.length,
    avg_latency_secs: avg(gandalfLatencies),
    min_latency_secs: min(gandalfLatencies),
    avg_options_considered: avg(decisions.map((d) => d.options_considered.length)),
    min_options_considered: min(decisions.map((d) => d.options_considered.length)),
    type_distribution: countBy(decisions.map((d) => d.type)),
    status_distribution: countBy(decisions.map((d) => d.status)),
    avg_actions_per_decision: avg(decisions.map((d) => d.actions.length)),
  };

  // ---- Saruman ----
  const verdict_distribution = Object.fromEntries(
    VERDICTS.map((v) => [v, governance.filter((g) => g.verdict === v).length]),
  ) as Record<Verdict, number>;

  const verdict_rates = Object.fromEntries(
    VERDICTS.map((v) => [
      v,
      governance.length > 0
        ? round2(verdict_distribution[v] / governance.length)
        : 0,
    ]),
  ) as Record<Verdict, number>;

  const bias_frequency = Object.fromEntries(
    BIASES.map((b) => [b, governance.filter((g) => g.bias_check[b]).length]),
  ) as Record<BiasName, number>;

  const sarumanLatencies: number[] = [];
  for (const g of governance) {
    if (!g.decision_id) continue;
    const t800Run = findRunsByDecision(runs, 't800', g.decision_id)[0];
    if (!t800Run || !t800Run.finished_at) continue;
    const t1000Run =
      findRunsByDecision(runs, 't1000', g.decision_id)[0] ??
      nearestRunByFinishedAt(runs, 't1000', t800Run.finished_at);
    if (t1000Run && t1000Run.finished_at) {
      sarumanLatencies.push(
        secondsBetween(t800Run.finished_at, t1000Run.finished_at),
      );
    }
  }

  const saruman: SarumanKpis = {
    total_reviews: governance.length,
    verdict_distribution,
    verdict_rates,
    bias_frequency,
    avg_confidence: avg(governance.map((g) => g.confidence)),
    avg_blind_spots: avg(governance.map((g) => g.blind_spots.length)),
    avg_risks: avg(governance.map((g) => g.risks.length)),
    avg_decision_to_governance_latency_secs: avg(sarumanLatencies),
  };

  // ---- Loop health ----
  const governedDecisions = decisions.filter((d) =>
    governanceByDecisionId.has(d.decision_id),
  );

  // auto_reviewed_pct heuristic: a governed decision counts as "auto" when
  // auto_governance is enabled AND exactly one t1000 run exists for its id —
  // a second, distinct t1000 run signals an on-demand re-review on top of the
  // automatic one, so that decision is treated as on-demand instead.
  let auto_reviewed_pct: number | null = null;
  if (governedDecisions.length > 0) {
    const autoCount = governedDecisions.filter((d) => {
      if (!autoGovernance) return false;
      const t1000Runs = findRunsByDecision(runs, 't1000', d.decision_id);
      return t1000Runs.length <= 1;
    }).length;
    auto_reviewed_pct = round2(autoCount / governedDecisions.length);
  }

  const loop_health: LoopHealthKpis = {
    challenge_round_trips: governance.filter((g) => g.verdict === 'challenge')
      .length,
    blocking_escalations: governance.filter((g) => g.verdict === 'escalate')
      .length,
    auto_reviewed_pct,
    decisions_without_governance: decisions.filter(
      (d) => !governanceByDecisionId.has(d.decision_id),
    ).length,
  };

  return {
    generated_at,
    gandalf,
    saruman,
    loop_health,
  };
}
