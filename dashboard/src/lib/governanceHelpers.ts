import type { FeatureProgress, DidioState } from './types';
import type { PipelineStatus, AgentFlag, FlagSeverity } from './kanbanTypes';

// ---------------------------------------------------------------------------
// Pipeline table
// ---------------------------------------------------------------------------

export interface PipelineRow {
  feature: string;
  phase: string;
  wave: number | null;
  totalTasks: number;
  completedTasks: number;
  progress: number;
  tokenUsed: number;
  tokenTotal: number;
  flagCount: number;
}

export function derivePipelineTable(
  didio: DidioState | undefined,
  pipelines: PipelineStatus[] | undefined,
  flags: AgentFlag[] | undefined,
): PipelineRow[] {
  const pipelineMap = new Map<string, PipelineStatus>();
  for (const p of pipelines ?? []) {
    pipelineMap.set(p.feature, p);
  }

  const flagCountMap = new Map<string, number>();
  for (const f of flags ?? []) {
    if (!f.resolved_at) {
      flagCountMap.set(f.feature, (flagCountMap.get(f.feature) ?? 0) + 1);
    }
  }

  const features: FeatureProgress[] = didio?.features ?? [];

  if (features.length === 0 && pipelineMap.size > 0) {
    return Array.from(pipelineMap.values()).map((p) => ({
      feature: p.feature,
      phase: p.phase,
      wave: p.current_wave,
      totalTasks: 0,
      completedTasks: 0,
      progress: 0,
      tokenUsed: p.token_budget_used,
      tokenTotal: p.token_budget_total,
      flagCount: flagCountMap.get(p.feature) ?? 0,
    }));
  }

  return features.map((fp) => {
    const ps = pipelineMap.get(fp.feature);
    return {
      feature: fp.feature,
      phase: ps?.phase ?? 'unknown',
      wave: fp.current_wave ?? ps?.current_wave ?? null,
      totalTasks: fp.total,
      completedTasks: fp.completed,
      progress: fp.percent,
      tokenUsed: ps?.token_budget_used ?? 0,
      tokenTotal: ps?.token_budget_total ?? 0,
      flagCount: flagCountMap.get(fp.feature) ?? 0,
    };
  });
}

// ---------------------------------------------------------------------------
// Token budget
// ---------------------------------------------------------------------------

export interface TokenBudgetSummary {
  totalAllocated: number;
  totalConsumed: number;
  remaining: number;
  pctUsed: number;
  hasWarning: boolean;
  perFeature: { feature: string; used: number; total: number; pct: number }[];
}

export function deriveTokenBudget(
  pipelines: PipelineStatus[] | undefined,
): TokenBudgetSummary | null {
  if (!pipelines || pipelines.length === 0) return null;

  let totalAllocated = 0;
  let totalConsumed = 0;
  let hasWarning = false;

  const perFeature = pipelines.map((p) => {
    totalAllocated += p.token_budget_total;
    totalConsumed += p.token_budget_used;
    const pct = p.token_budget_total > 0
      ? (p.token_budget_used / p.token_budget_total) * 100
      : 0;
    if (pct >= 80) hasWarning = true;
    return {
      feature: p.feature,
      used: p.token_budget_used,
      total: p.token_budget_total,
      pct,
    };
  });

  const remaining = totalAllocated - totalConsumed;
  const pctUsed = totalAllocated > 0
    ? (totalConsumed / totalAllocated) * 100
    : 0;

  return { totalAllocated, totalConsumed, remaining, pctUsed, hasWarning, perFeature };
}

// ---------------------------------------------------------------------------
// Flag analytics
// ---------------------------------------------------------------------------

export interface FlagAnalytics {
  total: number;
  active: number;
  resolved: number;
  critical: number;
  bySeverity: Record<FlagSeverity, number>;
  byType: Record<string, number>;
}

export function deriveFlagAnalytics(
  flags: AgentFlag[] | undefined,
): FlagAnalytics {
  const result: FlagAnalytics = {
    total: 0,
    active: 0,
    resolved: 0,
    critical: 0,
    bySeverity: { critical: 0, warning: 0, info: 0 },
    byType: {},
  };

  if (!flags) return result;

  for (const f of flags) {
    result.total++;
    if (f.resolved_at) {
      result.resolved++;
    } else {
      result.active++;
    }
    if (f.severity === 'critical' && !f.resolved_at) {
      result.critical++;
    }
    result.bySeverity[f.severity] = (result.bySeverity[f.severity] ?? 0) + 1;
    result.byType[f.type] = (result.byType[f.type] ?? 0) + 1;
  }

  return result;
}
