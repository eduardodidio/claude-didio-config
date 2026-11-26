import { MessageSquare, LayoutDashboard, Bell, Settings } from "lucide-react";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Separator } from "@/components/ui/separator";
import { Avatar } from "@/components/Avatar";
import { Chat } from "@/views/Chat";
import { BoardMini } from "@/views/BoardMini";
import { Alerts } from "@/views/Alerts";
import { Settings as SettingsView } from "@/views/Settings";
import { useAlerts } from "@/hooks/useAlerts";

function App() {
  const { activeAlerts } = useAlerts();

  return (
    <div className="min-h-screen bg-background text-foreground flex flex-col">
      {/* Header */}
      <header className="flex items-center gap-2 px-4 py-3 border-b border-border">
        <Avatar size="sm" className="didio-glow-pulse" />
        <h1 className="text-sm font-semibold tracking-tight">Black Hawk Desktop</h1>
        <div className="ml-auto flex items-center gap-1.5">
          {activeAlerts.length > 0 ? (
            <>
              <div className="w-2 h-2 rounded-full bg-destructive animate-pulse" />
              <span className="text-[10px] text-destructive font-mono">{activeAlerts.length}</span>
            </>
          ) : (
            <>
              <div className="w-2 h-2 rounded-full bg-[hsl(var(--status-active))]" />
              <span className="text-[10px] text-muted-foreground">OK</span>
            </>
          )}
        </div>
      </header>

      {/* Main content with tabs */}
      <Tabs defaultValue="chat" className="flex-1 flex flex-col">
        <div className="px-2 pt-2">
          <TabsList className="w-full grid grid-cols-4">
            <TabsTrigger value="chat" className="gap-1 text-xs">
              <MessageSquare className="h-3.5 w-3.5" />
              Chat
            </TabsTrigger>
            <TabsTrigger value="board" className="gap-1 text-xs">
              <LayoutDashboard className="h-3.5 w-3.5" />
              Board
            </TabsTrigger>
            <TabsTrigger value="alerts" className="gap-1 text-xs relative">
              <Bell className="h-3.5 w-3.5" />
              Alerts
              {activeAlerts.length > 0 && (
                <span className="absolute -top-1 -right-1 w-4 h-4 rounded-full bg-destructive text-[9px] text-destructive-foreground flex items-center justify-center font-bold">
                  {activeAlerts.length}
                </span>
              )}
            </TabsTrigger>
            <TabsTrigger value="settings" className="gap-1 text-xs">
              <Settings className="h-3.5 w-3.5" />
              Config
            </TabsTrigger>
          </TabsList>
        </div>

        <Separator className="mt-2" />

        <TabsContent value="chat" className="flex-1 m-0">
          <Chat />
        </TabsContent>

        <TabsContent value="board" className="flex-1 m-0">
          <BoardMini />
        </TabsContent>

        <TabsContent value="alerts" className="flex-1 m-0">
          <Alerts />
        </TabsContent>

        <TabsContent value="settings" className="flex-1 m-0 overflow-y-auto">
          <SettingsView />
        </TabsContent>
      </Tabs>
    </div>
  );
}

export default App;
