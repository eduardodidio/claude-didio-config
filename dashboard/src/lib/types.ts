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

export interface DidioState {
  generated_at: string;
  agents: AgentRun[];
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
