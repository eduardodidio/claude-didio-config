import type { AgentRun, DidioState } from './types';

type RawAgent = Omit<AgentRun, 'phrase'> & {
  phrase?: string | null;
  easter_egg?: string | null;
};

function normalize(raw: { generated_at: string; agents: RawAgent[] }): DidioState {
  return {
    generated_at: raw.generated_at,
    agents: (raw.agents ?? []).map((a) => ({
      ...a,
      phrase: a.phrase ?? a.easter_egg ?? null,
    })),
  };
}

export async function fetchState(): Promise<DidioState> {
  const res = await fetch('./state.json', { cache: 'no-store' });
  if (!res.ok) throw new Error(`state.json ${res.status}`);
  const raw = await res.json();
  return normalize(raw);
}
