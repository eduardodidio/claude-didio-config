import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';

const hookState: {
  isSuccess: boolean;
  isFetching: boolean;
  isError: boolean;
  dataUpdatedAt: number;
  error: unknown;
} = {
  isSuccess: false,
  isFetching: false,
  isError: false,
  dataUpdatedAt: 0,
  error: null,
};

vi.mock('@/hooks/useDidioState', () => ({
  useDidioState: () => hookState,
}));

import { ConnectionFooter } from './ConnectionFooter';

function renderWithClient() {
  const client = new QueryClient({
    defaultOptions: { queries: { retry: false } },
  });
  return render(
    <QueryClientProvider client={client}>
      <ConnectionFooter />
    </QueryClientProvider>,
  );
}

describe('ConnectionFooter', () => {
  beforeEach(() => {
    hookState.isSuccess = false;
    hookState.isFetching = false;
    hookState.isError = false;
    hookState.dataUpdatedAt = 0;
    hookState.error = null;
  });

  it('renders watching state.json text', () => {
    hookState.isSuccess = true;
    hookState.dataUpdatedAt = Date.now();
    renderWithClient();
    expect(screen.getByText(/watching state\.json/)).toBeInTheDocument();
  });

  it('shows 0s ago immediately after a successful fetch (happy + edge)', () => {
    hookState.isSuccess = true;
    hookState.dataUpdatedAt = Date.now();
    const { container } = renderWithClient();
    expect(container.textContent).toContain('last refresh 0s ago');
    expect(container.querySelector('.bg-green-500')).not.toBeNull();
  });

  it('shows amber dot while fetching', () => {
    hookState.isFetching = true;
    hookState.dataUpdatedAt = Date.now();
    const { container } = renderWithClient();
    expect(container.querySelector('.bg-amber-500')).not.toBeNull();
  });

  it('shows red dot and surfaces error in title attribute', () => {
    hookState.isError = true;
    hookState.error = new Error('boom');
    hookState.dataUpdatedAt = Date.now();
    const { container } = renderWithClient();
    expect(container.querySelector('.bg-red-500')).not.toBeNull();
    const footer = container.querySelector('footer');
    expect(footer?.getAttribute('title')).toBe('boom');
  });

  it('renders —s ago when dataUpdatedAt is 0 (boundary)', () => {
    hookState.isSuccess = true;
    hookState.dataUpdatedAt = 0;
    const { container } = renderWithClient();
    expect(container.textContent).toContain('last refresh —s ago');
    expect(container.textContent).not.toContain('NaN');
  });
});
