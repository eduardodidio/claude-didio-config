import { NavLink } from 'react-router-dom';
import { LayoutDashboard, Boxes, Activity, Sparkles } from 'lucide-react';
import {
  Sidebar,
  SidebarContent,
  SidebarGroup,
  SidebarGroupContent,
  SidebarHeader,
  SidebarMenu,
  SidebarMenuButton,
  SidebarMenuItem,
} from '@/components/ui/sidebar';

const VERSION = '0.1.0';

const navItems = [
  { to: '/', label: 'Overview', icon: LayoutDashboard, end: true },
  { to: '/features', label: 'Features', icon: Boxes, end: false },
  { to: '/agents', label: 'Agents', icon: Activity, end: false },
  { to: '/phrases', label: 'Phrases', icon: Sparkles, end: false },
];

export function AppSidebar() {
  return (
    <Sidebar collapsible="icon" className="border-r border-border bg-sidebar">
      <SidebarHeader>
        <div className="flex flex-col gap-0.5 px-3 py-2">
          <span className="text-sm font-bold tracking-tight text-primary">
            Didio Agents Dash
          </span>
          <span className="text-[10px] font-mono text-muted-foreground">v{VERSION}</span>
        </div>
      </SidebarHeader>
      <SidebarContent>
        <SidebarGroup>
          <SidebarGroupContent>
            <SidebarMenu className="gap-1">
              {navItems.map((item) => (
                <SidebarMenuItem key={item.to}>
                  <SidebarMenuButton asChild>
                    <NavLink
                      to={item.to}
                      end={item.end}
                      className={({ isActive }) =>
                        `flex items-center gap-3 px-3 py-2 rounded-lg text-sm font-medium transition-all duration-150 ${
                          isActive
                            ? 'didio-glow bg-primary/10 text-primary border border-primary/20'
                            : 'text-sidebar-foreground hover:bg-sidebar-accent hover:text-sidebar-accent-foreground'
                        }`
                      }
                    >
                      <item.icon className="w-4 h-4 flex-shrink-0" />
                      <span>{item.label}</span>
                    </NavLink>
                  </SidebarMenuButton>
                </SidebarMenuItem>
              ))}
            </SidebarMenu>
          </SidebarGroupContent>
        </SidebarGroup>
      </SidebarContent>
    </Sidebar>
  );
}

export default AppSidebar;
