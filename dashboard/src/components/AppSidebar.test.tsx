import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
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

import { AppSidebar } from './AppSidebar';

const renderAt = (path: string) =>
  render(
    <MemoryRouter initialEntries={[path]} future={{ v7_startTransition: true, v7_relativeSplatPath: true }}>
      <AppSidebar />
    </MemoryRouter>
  );

describe('AppSidebar', () => {
  it('happy: renders all 4 nav items with correct hrefs', () => {
    renderAt('/');
    const expected: Array<[string, string]> = [
      ['Overview', '/'],
      ['Features', '/features'],
      ['Agents', '/agents'],
      ['Phrases', '/phrases'],
    ];
    for (const [label, href] of expected) {
      const link = screen.getByRole('link', { name: new RegExp(label, 'i') });
      expect(link).toBeInTheDocument();
      expect(link).toHaveAttribute('href', href);
    }
  });

  it('edge: navigating to /agents marks that link active with didio-glow', () => {
    renderAt('/agents');
    const link = screen.getByRole('link', { name: /Agents/i });
    expect(link).toHaveClass('didio-glow');
    expect(link.className).toMatch(/didio-glow|active/);
  });

  it('error: renders without a real SidebarProvider (stub used)', () => {
    expect(() => renderAt('/')).not.toThrow();
    expect(screen.getByText('Didio Agents Dash')).toBeInTheDocument();
  });

  it('boundary: all 4 nav icons render even in collapsed-style stub', () => {
    const { container } = renderAt('/');
    const svgs = container.querySelectorAll('a svg');
    expect(svgs.length).toBe(4);
  });
});
