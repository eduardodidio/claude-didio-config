import type { AgentFlag, PipelineStatus } from './kanbanTypes';

export async function fetchFlags(): Promise<AgentFlag[]> {
  const res = await fetch('./flags.json', { cache: 'no-store' });
  if (!res.ok) throw new Error(`flags.json ${res.status}`);
  const raw = await res.json();
  if (!Array.isArray(raw)) return [];
  return raw.filter(isValidFlag);
}

export async function fetchPipelineState(): Promise<PipelineStatus[]> {
  const res = await fetch('./pipeline-state.json', { cache: 'no-store' });
  if (!res.ok) throw new Error(`pipeline-state.json ${res.status}`);
  const raw = await res.json();
  if (!Array.isArray(raw)) return [];
  return raw;
}

function isValidFlag(obj: unknown): obj is AgentFlag {
  if (typeof obj !== 'object' || obj === null) return false;
  const f = obj as Record<string, unknown>;
  return (
    typeof f.flag_id === 'string' &&
    typeof f.type === 'string' &&
    typeof f.feature === 'string' &&
    typeof f.severity === 'string' &&
    typeof f.reason === 'string'
  );
}
