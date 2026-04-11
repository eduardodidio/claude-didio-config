import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { fetchState } from './fetchState';
import type { DidioState } from './types';

const sampleState: DidioState = {
  generated_at: '2026-04-11T10:00:00Z',
  agents: [
    {
      feature: 'F01',
      role: 'developer',
      task: 'F01-T06',
      task_file: 'tasks/features/F01-dashboard/F01-T06.md',
      started_at: '2026-04-11T09:00:00Z',
      finished_at: null,
      status: 'running',
      exit_code: null,
      pid: 1,
      log: 'logs/agents/F01-T06.jsonl',
      phrase: null,
    },
  ],
};

describe('fetchState', () => {
  beforeEach(() => {
    vi.stubGlobal('fetch', vi.fn());
  });
  afterEach(() => {
    vi.unstubAllGlobals();
    vi.restoreAllMocks();
  });

  it('resolves with typed DidioState on 200', async () => {
    (globalThis.fetch as unknown as ReturnType<typeof vi.fn>).mockResolvedValue({
      ok: true,
      status: 200,
      json: async () => sampleState,
    });
    const result = await fetchState();
    expect(result.agents).toHaveLength(1);
    expect(result.agents[0].role).toBe('developer');
    expect(globalThis.fetch).toHaveBeenCalledWith('./state.json', {
      cache: 'no-store',
    });
  });

  it('throws on non-ok response', async () => {
    (globalThis.fetch as unknown as ReturnType<typeof vi.fn>).mockResolvedValue({
      ok: false,
      status: 500,
      json: async () => ({}),
    });
    await expect(fetchState()).rejects.toThrow('state.json 500');
  });

  it('throws on 404', async () => {
    (globalThis.fetch as unknown as ReturnType<typeof vi.fn>).mockResolvedValue({
      ok: false,
      status: 404,
      json: async () => ({}),
    });
    await expect(fetchState()).rejects.toThrow('state.json 404');
  });
});
