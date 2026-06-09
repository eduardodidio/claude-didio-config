import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { basename, join } from 'node:path';
import type { DecisionRecord, GovernanceReport, MetaRunState } from './metaTypes';

const DECISION_REQUIRED_KEYS: (keyof DecisionRecord)[] = [
  'decision_id',
  'type',
  'options_considered',
  'decision',
  'rationale',
  'actions',
  'status',
];

const GOVERNANCE_REQUIRED_KEYS: (keyof GovernanceReport)[] = [
  'verdict',
  'bias_check',
  'blind_spots',
  'risks',
  'recommendation',
  'confidence',
];

function listFiles(dir: string, prefix: string): string[] {
  if (!existsSync(dir)) return [];
  return readdirSync(dir).filter(
    (name) => name.startsWith(prefix) && name.endsWith('.json'),
  );
}

function parseJsonFile(path: string): unknown | null {
  let raw: string;
  try {
    raw = readFileSync(path, 'utf-8');
  } catch (err) {
    console.warn(`metaSources: could not read ${path}: ${(err as Error).message}`);
    return null;
  }

  try {
    return JSON.parse(raw);
  } catch (err) {
    console.warn(`metaSources: skipping malformed JSON ${path}: ${(err as Error).message}`);
    return null;
  }
}

function hasRequiredKeys(value: unknown, keys: readonly string[]): value is Record<string, unknown> {
  if (typeof value !== 'object' || value === null) return false;
  const record = value as Record<string, unknown>;
  return keys.every((key) => key in record);
}

export function loadDecisions(decisionsDir: string): DecisionRecord[] {
  const decisions: DecisionRecord[] = [];

  for (const name of listFiles(decisionsDir, 'D-')) {
    const path = join(decisionsDir, name);
    const parsed = parseJsonFile(path);
    if (parsed === null) continue;

    if (!hasRequiredKeys(parsed, DECISION_REQUIRED_KEYS)) {
      console.warn(`metaSources: skipping ${path} — missing required DecisionRecord keys`);
      continue;
    }

    decisions.push(parsed as unknown as DecisionRecord);
  }

  return decisions;
}

export function loadGovernance(govDir: string): GovernanceReport[] {
  const reports: GovernanceReport[] = [];

  for (const name of listFiles(govDir, 'G-')) {
    const path = join(govDir, name);
    const parsed = parseJsonFile(path);
    if (parsed === null) continue;

    if (!hasRequiredKeys(parsed, GOVERNANCE_REQUIRED_KEYS)) {
      console.warn(`metaSources: skipping ${path} — missing required GovernanceReport keys`);
      continue;
    }

    // File name carries the decision id: G-<decision-id>.json
    const decisionId = basename(name, '.json').replace(/^G-/, '');
    reports.push({ ...(parsed as unknown as GovernanceReport), decision_id: decisionId });
  }

  return reports;
}

export function loadRunState(stateJsonPath: string): MetaRunState[] {
  if (!existsSync(stateJsonPath)) return [];

  const parsed = parseJsonFile(stateJsonPath);
  if (parsed === null) return [];

  if (typeof parsed !== 'object' || parsed === null || !Array.isArray((parsed as Record<string, unknown>).agents)) {
    console.warn(`metaSources: skipping ${stateJsonPath} — missing .agents array`);
    return [];
  }

  const agents = (parsed as { agents: unknown[] }).agents;
  const runs: MetaRunState[] = [];

  for (const agent of agents) {
    if (!hasRequiredKeys(agent, ['role', 'task', 'started_at', 'finished_at', 'exit_code', 'status'])) {
      console.warn(`metaSources: skipping malformed run entry in ${stateJsonPath}`);
      continue;
    }

    const run = agent as unknown as MetaRunState;
    if (run.role === 't800' || run.role === 't1000') {
      runs.push(run);
    }
  }

  return runs;
}
