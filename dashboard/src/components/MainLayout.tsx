import { Outlet } from 'react-router-dom';
import { SidebarProvider } from '@/components/ui/sidebar';
import { AppSidebar } from './AppSidebar';
import { ConnectionFooter } from './ConnectionFooter';

export function MainLayout() {
  return (
    <SidebarProvider>
      <div className="flex min-h-screen w-full surface-card">
        <AppSidebar />
        <main className="flex-1 flex flex-col bg-background text-foreground">
          <div className="flex-1 overflow-auto p-6">
            <Outlet />
          </div>
          <ConnectionFooter />
        </main>
      </div>
    </SidebarProvider>
  );
}

export default MainLayout;
