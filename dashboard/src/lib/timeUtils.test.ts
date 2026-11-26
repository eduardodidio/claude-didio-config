import { describe, it, expect, vi, afterEach } from 'vitest';
import { relativeTime } from './timeUtils';

afterEach(() => {
  vi.useRealTimers();
});

describe('relativeTime', () => {
  const NOW = new Date('2026-11-26T12:00:00Z').getTime();

  function withFakeTime(fn: () => void) {
    vi.useFakeTimers();
    vi.setSystemTime(NOW);
    fn();
  }

  it('returns "just now" for < 1 min', () => {
    withFakeTime(() => {
      // 30 seconds ago
      const iso = new Date(NOW - 30_000).toISOString();
      expect(relativeTime(iso)).toBe('just now');
    });
  });

  it('returns "1m ago" for exactly 1 minute', () => {
    withFakeTime(() => {
      const iso = new Date(NOW - 60_000).toISOString();
      expect(relativeTime(iso)).toBe('1m ago');
    });
  });

  it('returns "5m ago" for 5 minutes', () => {
    withFakeTime(() => {
      const iso = new Date(NOW - 5 * 60_000).toISOString();
      expect(relativeTime(iso)).toBe('5m ago');
    });
  });

  it('returns "59m ago" for 59 minutes', () => {
    withFakeTime(() => {
      const iso = new Date(NOW - 59 * 60_000).toISOString();
      expect(relativeTime(iso)).toBe('59m ago');
    });
  });

  it('returns "1h ago" for 60 minutes', () => {
    withFakeTime(() => {
      const iso = new Date(NOW - 60 * 60_000).toISOString();
      expect(relativeTime(iso)).toBe('1h ago');
    });
  });

  it('returns "2h ago" for 2 hours', () => {
    withFakeTime(() => {
      const iso = new Date(NOW - 2 * 60 * 60_000).toISOString();
      expect(relativeTime(iso)).toBe('2h ago');
    });
  });

  it('returns "23h ago" for 23 hours', () => {
    withFakeTime(() => {
      const iso = new Date(NOW - 23 * 60 * 60_000).toISOString();
      expect(relativeTime(iso)).toBe('23h ago');
    });
  });

  it('returns "1d ago" for 24 hours', () => {
    withFakeTime(() => {
      const iso = new Date(NOW - 24 * 60 * 60_000).toISOString();
      expect(relativeTime(iso)).toBe('1d ago');
    });
  });

  it('returns "3d ago" for 3 days', () => {
    withFakeTime(() => {
      const iso = new Date(NOW - 3 * 24 * 60 * 60_000).toISOString();
      expect(relativeTime(iso)).toBe('3d ago');
    });
  });

  it('returns "just now" for dates in the future (diff < 0)', () => {
    withFakeTime(() => {
      const iso = new Date(NOW + 60_000).toISOString();
      // Math.floor of negative diff / 60000 -> negative mins -> < 1
      expect(relativeTime(iso)).toBe('just now');
    });
  });
});
