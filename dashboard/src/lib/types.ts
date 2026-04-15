export type AgentStatus = 'running' | 'completed' | 'failed' | 'blocked';

export type AgentRole =
  | 'architect'
  | 'developer'
  | 'qa'
  | 'security'
  | 'reviewer'
  | 'devops'
  | 'docs';

export interface AgentRun {
  feature: string;
  role: AgentRole;
  task: string;
  task_file: string;
  started_at: string;
  finished_at: string | null;
  status: AgentStatus;
  exit_code: number | null;
  pid: number;
  log: string;
  phrase: string | null;
}

export type TrailStatus = 'completed' | 'running' | 'failed' | 'planned';

export interface TrailItem {
  task: string;
  wave: number | null;
  status: TrailStatus;
}

export interface FeatureProgress {
  feature: string;
  total: number;
  completed: number;
  running: number;
  failed: number;
  percent: number;
  current_wave: number | null;
  current_task: string | null;
  trail: TrailItem[];
}

export interface DidioState {
  generated_at: string;
  agents: AgentRun[];
  features?: FeatureProgress[];
}

export interface EasterEggFranchise {
  emoji?: string;
  tags?: string[];
  success?: string[];
  failure?: string[];
}

export interface EasterEggVillain {
  name: string;
  franchise: string;
  severity: string;
  line: string;
}

export interface EasterEggsFile {
  version?: number;
  description?: string;
  franchises: Record<string, EasterEggFranchise>;
  role_mapping: Record<string, string[]>;
  critical_failure_villains?: EasterEggVillain[];
}

export interface FeatureGroup {
  feature: string;
  runs: AgentRun[];
}

export interface OverviewStats {
  activeFeatures: number;
  running: number;
  completed: number;
  failed: number;
}
