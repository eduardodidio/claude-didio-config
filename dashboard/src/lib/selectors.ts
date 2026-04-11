import type {
  AgentRole,
  AgentRun,
  DidioState,
  FeatureGroup,
  OverviewStats,
} from './types';

export function computeOverviewStats(state: DidioState): OverviewStats {
  const features = new Set<string>();
  let running = 0;
  let completed = 0;
  let failed = 0;
  for (const run of state.agents) {
    features.add(run.feature);
    if (run.status === 'running') running++;
    else if (run.status === 'completed') completed++;
    else if (run.status === 'failed') failed++;
  }
  return {
    activeFeatures: features.size,
    running,
    completed,
    failed,
  };
}

export function groupByFeature(state: DidioState): FeatureGroup[] {
  const map = new Map<string, FeatureGroup>();
  for (const run of state.agents) {
    let group = map.get(run.feature);
    if (!group) {
      group = { feature: run.feature, runs: [] };
      map.set(run.feature, group);
    }
    group.runs.push(run);
  }
  for (const group of map.values()) {
    group.runs.sort((a, b) => a.started_at.localeCompare(b.started_at));
  }
  return Array.from(map.values()).sort((a, b) =>
    a.feature.localeCompare(b.feature),
  );
}

export function latestPhrase(
  state: DidioState,
): { role: AgentRole; phrase: string } | null {
  const withPhrase = state.agents.filter(
    (r): r is AgentRun & { phrase: string } =>
      typeof r.phrase === 'string' && r.phrase.length > 0,
  );
  if (withPhrase.length === 0) return null;
  withPhrase.sort((a, b) => b.started_at.localeCompare(a.started_at));
  const top = withPhrase[0];
  return { role: top.role, phrase: top.phrase };
}

