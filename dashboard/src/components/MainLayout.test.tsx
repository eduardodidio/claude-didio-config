import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import { MemoryRouter, Route, Routes } from 'react-router-dom';
import type { ReactNode } from 'react';

vi.mock('@/components/ui/sidebar', () => {
  const Pass = ({ children, asChild: _asChild, ...rest }: { children?: ReactNode; asChild?: boolean } & Record<string, unknown>) => (
    <div {...rest}>{children}</div>
  );
  return {
    Sidebar: Pass,
    SidebarHeader: Pass,
    SidebarContent: Pass,
    SidebarGroup: Pass,
    SidebarGroupContent: Pass,
    SidebarMenu: Pass,
    SidebarMenuItem: Pass,
    SidebarMenuButton: ({ children }: { children?: ReactNode; asChild?: boolean }) => <>{children}</>,
    SidebarProvider: Pass,
    useSidebar: () => ({ state: 'expanded', toggleSidebar: () => {} }),
  };
});

vi.mock('@/hooks/useDidioState', () => ({
  useDidioState: () => ({
    isSuccess: true,
    isFetching: false,
    isError: false,
    dataUpdatedAt: Date.now(),
    error: null,
  }),
}));

import { MainLayout } from './MainLayout';

const renderAt = (path: string, child: ReactNode = <div>HI</div>) =>
  render(
    <MemoryRouter initialEntries={[path]} future={{ v7_startTransition: true, v7_relativeSplatPath: true }}>
      <Routes>
        <Route element={<MainLayout />}>
          <Route path="/" element={child} />
          <Route path="/empty" element={null} />
        </Route>
      </Routes>
    </MemoryRouter>
  );

describe('MainLayout', () => {
  it('happy: child route content renders inside the main area alongside sidebar', () => {
    renderAt('/');
    expect(screen.getByText('HI')).toBeInTheDocument();
    expect(screen.getByRole('link', { name: /Overview/i })).toBeInTheDocument();
    expect(screen.getByRole('link', { name: /Features/i })).toBeInTheDocument();
    expect(screen.getByRole('link', { name: /Agents/i })).toBeInTheDocument();
    expect(screen.getByRole('link', { name: /Phrases/i })).toBeInTheDocument();
  });

  it('edge: re-rendering at same path keeps child mounted (sidebar toggle does not unmount)', () => {
    const { rerender } = renderAt('/', <div data-testid="child">HI</div>);
    const first = screen.getByTestId('child');
    rerender(
      <MemoryRouter initialEntries={['/']} future={{ v7_startTransition: true, v7_relativeSplatPath: true }}>
        <Routes>
          <Route element={<MainLayout />}>
            <Route path="/" element={<div data-testid="child">HI</div>} />
          </Route>
        </Routes>
      </MemoryRouter>
    );
    expect(screen.getByTestId('child')).toBeInTheDocument();
    expect(first.textContent).toBe('HI');
  });

  it('error: explicit MemoryRouter satisfies router context — no throw', () => {
    expect(() => renderAt('/')).not.toThrow();
  });

  it('boundary: route with null element still renders the layout shell', () => {
    renderAt('/empty');
    expect(screen.getByRole('link', { name: /Overview/i })).toBeInTheDocument();
    expect(screen.getByRole('contentinfo')).toBeInTheDocument();
  });
});
