import { describe, it, expect } from 'vitest';
import {
  STATUS_STYLE,
  getStatusDot,
  getTrailChipClasses,
  getTrailGlyph,
  getAggregateDot,
} from './statusStyles';
import type { AgentRun, AgentStatus, TrailStatus } from './types';

function makeRun(status: AgentStatus): AgentRun {
  return {
    feature: 'F01',
    role: 'developer',
    task: 'F01-T01',
    task_file: 'tasks/features/F01/F01-T01.md',
    started_at: '2026-01-01T00:00:00Z',
    finished_at: null,
    status,
    exit_code: null,
    pid: 1234,
    log: '',
    phrase: null,
  };
}

describe('STATUS_STYLE', () => {
  const allStatuses: (AgentStatus | TrailStatus)[] = [
    'running',
    'completed',
    'failed',
    'blocked',
    'planned',
  ];

  it('has an entry for every AgentStatus and TrailStatus', () => {
    for (const s of allStatuses) {
      expect(STATUS_STYLE).toHaveProperty(s);
    }
  });

  it('each entry has dot, chip, and glyph fields', () => {
    for (const entry of Object.values(STATUS_STYLE)) {
      expect(typeof entry.dot).toBe('string');
      expect(typeof entry.chip).toBe('string');
      expect(typeof entry.glyph).toBe('string');
    }
  });
});

describe('getStatusDot', () => {
  it('returns correct dot for each status', () => {
    expect(getStatusDot('completed')).toBe('bg-emerald-500');
    expect(getStatusDot('running')).toBe('bg-amber-500');
    expect(getStatusDot('failed')).toBe('bg-red-500');
    expect(getStatusDot('blocked')).toBe('bg-orange-500');
    expect(getStatusDot('planned')).toBe('bg-muted');
  });

  it('falls back to bg-muted for unknown status', () => {
    expect(getStatusDot('unknown-status')).toBe('bg-muted');
  });
});

describe('getTrailChipClasses', () => {
  it('returns chip classes for each TrailStatus', () => {
    expect(getTrailChipClasses('completed')).toContain('emerald');
    expect(getTrailChipClasses('running')).toContain('animate-pulse');
    expect(getTrailChipClasses('failed')).toContain('red');
    expect(getTrailChipClasses('planned')).toBe(
      'bg-muted text-muted-foreground border-border',
    );
  });

  it('matches exact classes from Features.tsx for completed', () => {
    expect(getTrailChipClasses('completed')).toBe(
      'bg-emerald-500/15 text-emerald-500 border-emerald-500/30',
    );
  });

  it('matches exact classes from Features.tsx for running', () => {
    expect(getTrailChipClasses('running')).toBe(
      'bg-amber-500/15 text-amber-500 border-amber-500/40 animate-pulse',
    );
  });

  it('matches exact classes from Features.tsx for failed', () => {
    expect(getTrailChipClasses('failed')).toBe(
      'bg-red-500/15 text-red-500 border-red-500/40',
    );
  });
});

describe('getTrailGlyph', () => {
  it('returns correct glyph for each TrailStatus', () => {
    expect(getTrailGlyph('completed')).toBe('✓');
    expect(getTrailGlyph('running')).toBe('▶');
    expect(getTrailGlyph('failed')).toBe('✗');
    expect(getTrailGlyph('planned')).toBe('·');
  });
});

describe('getAggregateDot', () => {
  it('returns emerald when all runs are completed', () => {
    expect(getAggregateDot([makeRun('completed'), makeRun('completed')])).toBe(
      'bg-emerald-500',
    );
  });

  it('returns emerald for empty array', () => {
    expect(getAggregateDot([])).toBe('bg-emerald-500');
  });

  it('returns amber when any run is running and none failed', () => {
    expect(getAggregateDot([makeRun('completed'), makeRun('running')])).toBe(
      'bg-amber-500',
    );
  });

  it('returns red when any run is failed', () => {
    expect(getAggregateDot([makeRun('completed'), makeRun('failed')])).toBe(
      'bg-red-500',
    );
  });

  it('failed wins over running', () => {
    expect(
      getAggregateDot([makeRun('running'), makeRun('failed'), makeRun('completed')]),
    ).toBe('bg-red-500');
  });

  it('single-element: completed → emerald', () => {
    expect(getAggregateDot([makeRun('completed')])).toBe('bg-emerald-500');
  });

  it('single-element: running → amber', () => {
    expect(getAggregateDot([makeRun('running')])).toBe('bg-amber-500');
  });

  it('single-element: failed → red', () => {
    expect(getAggregateDot([makeRun('failed')])).toBe('bg-red-500');
  });

  it('single-element: blocked → emerald (blocked is not failed/running)', () => {
    expect(getAggregateDot([makeRun('blocked')])).toBe('bg-emerald-500');
  });
});

describe('blocked status boundary', () => {
  it('getStatusDot returns orange for blocked', () => {
    expect(getStatusDot('blocked')).toBe('bg-orange-500');
  });

  it('STATUS_STYLE blocked has correct glyph', () => {
    expect(STATUS_STYLE['blocked'].glyph).toBe('⊘');
  });

  it('STATUS_STYLE blocked chip contains orange', () => {
    expect(STATUS_STYLE['blocked'].chip).toContain('orange');
  });
});

describe('planned status boundary', () => {
  it('getStatusDot returns muted for planned', () => {
    expect(getStatusDot('planned')).toBe('bg-muted');
  });

  it('getTrailGlyph returns · for planned', () => {
    expect(getTrailGlyph('planned')).toBe('·');
  });
});
