import { act, cleanup, render, screen, waitFor } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

// Stub framer-motion so AnimatePresence does not gate DOM updates behind
// exit animations (which never resolve under vi.useFakeTimers).
vi.mock('framer-motion', async () => {
  const React = await import('react');
  const passthrough = (tag: string) =>
    React.forwardRef<unknown, Record<string, unknown>>((props, ref) => {
      const {
        initial: _i,
        animate: _a,
        exit: _e,
        transition: _t,
        variants: _v,
        whileHover: _wh,
        whileTap: _wt,
        whileInView: _wiv,
        layout: _l,
        layoutId: _lid,
        ...rest
      } = props as Record<string, unknown>;
      return React.createElement(tag as keyof JSX.IntrinsicElements, { ref, ...rest });
    });
  const motion = new Proxy(
    {},
    {
      get: (_target, tag: string) => passthrough(tag),
    },
  );
  return {
    motion,
    AnimatePresence: ({ children }: { children: React.ReactNode }) =>
      React.createElement(React.Fragment, null, children),
  };
});

import EasterEggs, { normalizeEasterEggs } from './EasterEggs';

type FetchFn = typeof fetch;

function mockFetchJson(body: unknown, ok = true, status = 200) {
  const fn = vi.fn(async () => ({
    ok,
    status,
    json: async () => body,
  }) as Response);
  globalThis.fetch = fn as unknown as FetchFn;
  return fn;
}

function mockFetchReject(err: unknown) {
  const fn = vi.fn(async () => {
    throw err;
  });
  globalThis.fetch = fn as unknown as FetchFn;
  return fn;
}

const oneFranchiseFixture = {
  franchises: {
    mario: {
      emoji: '🍄',
      success: ['phrase-one', 'phrase-two', 'phrase-three', 'phrase-four'],
      failure: ['bowser-fail'],
    },
  },
  role_mapping: {
    developer: ['mario'],
  },
};

const nineFranchiseFixture = {
  franchises: Object.fromEntries(
    Array.from({ length: 9 }).map((_, i) => [
      `franchise_${i}`,
      {
        emoji: '⭐',
        success: [`f${i}-a`, `f${i}-b`, `f${i}-c`, `f${i}-d`],
      },
    ]),
  ),
  role_mapping: {},
};

const shortFranchiseFixture = {
  franchises: {
    mario: {
      emoji: '🍄',
      success: ['only-one', 'only-two'],
    },
  },
  role_mapping: {},
};

afterEach(() => {
  cleanup();
  vi.useRealTimers();
  vi.restoreAllMocks();
});

describe('normalizeEasterEggs', () => {
  it('maps raw record shape to a normalized array with ≤4 phrases', () => {
    const out = normalizeEasterEggs({
      franchises: {
        mario: {
          emoji: '🍄',
          success: ['a', 'b', 'c', 'd', 'e'],
        },
      },
      role_mapping: { developer: ['mario', 'pokemon'] },
    });

    expect(out.franchises).toHaveLength(1);
    expect(out.franchises[0].key).toBe('mario');
    expect(out.franchises[0].name).toBe('Mario');
    expect(out.franchises[0].phrases).toEqual(['a', 'b', 'c', 'd']);
    expect(out.role_mapping.developer).toBe('mario');
  });

  it('falls back gracefully for missing fields', () => {
    const out = normalizeEasterEggs({ franchises: {}, role_mapping: {} });
    expect(out.franchises).toEqual([]);
    expect(out.role_mapping).toEqual({});
  });
});

describe('<EasterEggs /> view', () => {
  beforeEach(() => {
    vi.useFakeTimers({ shouldAdvanceTime: true });
  });

  it('happy: renders first phrase on mount and advances after 2500ms', async () => {
    mockFetchJson(oneFranchiseFixture);

    render(<EasterEggs />);

    // Wait for fetch promise chain to resolve.
    await waitFor(() => {
      expect(screen.getByTestId('phrase-mario')).toHaveTextContent('phrase-one');
    });

    await act(async () => {
      await vi.advanceTimersByTimeAsync(2500);
    });

    expect(screen.getByTestId('phrase-mario')).toHaveTextContent('phrase-two');

    await act(async () => {
      await vi.advanceTimersByTimeAsync(2500);
    });

    expect(screen.getByTestId('phrase-mario')).toHaveTextContent('phrase-three');
  });

  it('edge: franchise with fewer than 4 phrases still cycles what is present', async () => {
    mockFetchJson(shortFranchiseFixture);

    render(<EasterEggs />);

    await waitFor(() => {
      expect(screen.getByTestId('phrase-mario')).toHaveTextContent('only-one');
    });

    await act(async () => {
      await vi.advanceTimersByTimeAsync(2500);
    });

    expect(screen.getByTestId('phrase-mario')).toHaveTextContent('only-two');

    await act(async () => {
      await vi.advanceTimersByTimeAsync(2500);
    });

    // Wraps back to the first of the 2 phrases.
    expect(screen.getByTestId('phrase-mario')).toHaveTextContent('only-one');
  });

  it('error: renders empty state on fetch 404 without crashing', async () => {
    mockFetchJson({}, false, 404);

    render(<EasterEggs />);

    await waitFor(() => {
      expect(screen.getByTestId('phrases-error')).toBeInTheDocument();
    });
    expect(screen.queryByTestId('phrases-view')).not.toBeInTheDocument();
  });

  it('error: renders empty state on fetch rejection', async () => {
    mockFetchReject(new Error('network down'));

    render(<EasterEggs />);

    await waitFor(() => {
      expect(screen.getByTestId('phrases-error')).toBeInTheDocument();
    });
  });

  it('boundary: renders all 9 franchises on the page', async () => {
    mockFetchJson(nineFranchiseFixture);

    render(<EasterEggs />);

    await waitFor(() => {
      expect(screen.getByTestId('phrases-view')).toBeInTheDocument();
    });

    for (let i = 0; i < 9; i += 1) {
      expect(screen.getByTestId(`franchise-franchise_${i}`)).toBeInTheDocument();
    }
  });
});
