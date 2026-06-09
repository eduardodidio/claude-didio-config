export type DecisionType =
  | 'feature_start'
  | 'wave_proceed'
  | 'quality_gate'
  | 'block'
  | 'priority_change'
  | 'batch_plan';

export type DecisionStatus =
  | 'pending'
  | 'executed'
  | 'blocked'
  | 'partial'
  | 'escalated'
  | 'reviewed'
  | 'ratified';

export interface DecisionRecord {
  decision_id: string;
  type: DecisionType;
  options_considered: string[];
  decision: string;
  rationale: string;
  actions: string[];
  status: DecisionStatus;
  governance?: unknown;
}

export type Verdict = 'agree' | 'challenge' | 'escalate';

export type BiasName =
  | 'sunk_cost'
  | 'anchoring'
  | 'scope_creep'
  | 'optimism'
  | 'recency';

export interface GovernanceReport {
  decision_id?: string;
  verdict: Verdict;
  bias_check: Record<BiasName, boolean>;
  blind_spots: string[];
  risks: string[];
  recommendation: string;
  confidence: number;
}

export interface MetaRunState {
  role: string;
  task: string;
  started_at: string;
  finished_at: string | null;
  exit_code: number | null;
  status: string;
}

export interface GandalfKpis {
  total_decisions: number;
  avg_latency_secs: number | null;
  min_latency_secs: number | null;
  avg_options_considered: number | null;
  min_options_considered: number | null;
  type_distribution: Record<string, number>;
  status_distribution: Record<string, number>;
  avg_actions_per_decision: number | null;
}

export interface SarumanKpis {
  total_reviews: number;
  verdict_distribution: Record<Verdict, number>;
  verdict_rates: Record<Verdict, number>;
  bias_frequency: Record<BiasName, number>;
  avg_confidence: number | null;
  avg_blind_spots: number | null;
  avg_risks: number | null;
  avg_decision_to_governance_latency_secs: number | null;
}

export interface LoopHealthKpis {
  challenge_round_trips: number;
  blocking_escalations: number;
  auto_reviewed_pct: number | null;
  decisions_without_governance: number;
}

export interface MetaMetricsReport {
  generated_at: string;
  gandalf: GandalfKpis;
  saruman: SarumanKpis;
  loop_health: LoopHealthKpis;
}

const VERDICTS: readonly Verdict[] = ['agree', 'challenge', 'escalate'];

export function isVerdict(value: string): value is Verdict {
  return (VERDICTS as readonly string[]).includes(value);
}
