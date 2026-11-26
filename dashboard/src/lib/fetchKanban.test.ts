import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { fetchFlags, fetchPipelineState } from './fetchKanban';

beforeEach(() => {
  vi.stubGlobal('fetch', vi.fn());
});

afterEach(() => {
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
});

// ---------------------------------------------------------------------------
// fetchFlags
// ---------------------------------------------------------------------------

describe('fetchFlags', () => {
  it('parses valid response', async () => {
    const flags = [
      {
        flag_id: 'f1',
        type: 'blocked',
        feature: 'F01',
        severity: 'critical',
        reason: 'dep missing',
        task: null,
        suggested_actions: [],
        created_at: '2026-11-01T10:00:00Z',
        resolved_at: null,
      },
    ];
    (globalThis.fetch as ReturnType<typeof vi.fn>).mockResolvedValue({
      ok: true,
      json: async () => flags,
    });

    const result = await fetchFlags();
    expect(result).toHaveLength(1);
    expect(result[0].flag_id).toBe('f1');
  });

  it('filters invalid entries', async () => {
    const mixed = [
      {
        flag_id: 'f1',
        type: 'blocked',
        feature: 'F01',
        severity: 'critical',
        reason: 'valid',
      },
      { invalid: true },
      null,
      42,
      'string',
    ];
    (globalThis.fetch as ReturnType<typeof vi.fn>).mockResolvedValue({
      ok: true,
      json: async () => mixed,
    });

    const result = await fetchFlags();
    expect(result).toHaveLength(1);
    expect(result[0].flag_id).toBe('f1');
  });

  it('returns [] on empty response', async () => {
    (globalThis.fetch as ReturnType<typeof vi.fn>).mockResolvedValue({
      ok: true,
      json: async () => [],
    });

    const result = await fetchFlags();
    expect(result).toEqual([]);
  });

  it('returns [] when response is not an array', async () => {
    (globalThis.fetch as ReturnType<typeof vi.fn>).mockResolvedValue({
      ok: true,
      json: async () => ({ not: 'array' }),
    });

    const result = await fetchFlags();
    expect(result).toEqual([]);
  });

  it('throws on non-ok response', async () => {
    (globalThis.fetch as ReturnType<typeof vi.fn>).mockResolvedValue({
      ok: false,
      status: 500,
    });

    await expect(fetchFlags()).rejects.toThrow('flags.json 500');
  });
});

// ---------------------------------------------------------------------------
// fetchPipelineState
// ---------------------------------------------------------------------------

describe('fetchPipelineState', () => {
  it('parses valid response', async () => {
    const pipelines = [
      {
        feature: 'F30',
        phase: 'wave_1',
        started_at: '2026-11-01T08:00:00Z',
        token_budget_used: 1000,
        token_budget_total: 5000,
        agent_count: 2,
        current_wave: 1,
      },
    ];
    (globalThis.fetch as ReturnType<typeof vi.fn>).mockResolvedValue({
      ok: true,
      json: async () => pipelines,
    });

    const result = await fetchPipelineState();
    expect(result).toHaveLength(1);
    expect(result[0].feature).toBe('F30');
  });

  it('returns [] when response is not an array', async () => {
    (globalThis.fetch as ReturnType<typeof vi.fn>).mockResolvedValue({
      ok: true,
      json: async () => null,
    });

    const result = await fetchPipelineState();
    expect(result).toEqual([]);
  });

  it('throws on non-ok response', async () => {
    (globalThis.fetch as ReturnType<typeof vi.fn>).mockResolvedValue({
      ok: false,
      status: 404,
    });

    await expect(fetchPipelineState()).rejects.toThrow('pipeline-state.json 404');
  });
});
