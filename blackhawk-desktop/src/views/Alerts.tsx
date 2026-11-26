import { Bell, BellOff, RefreshCw } from 'lucide-react';
import { useAlerts } from '@/hooks/useAlerts';
import { AlertBanner } from '@/components/AlertBanner';
import { Button } from '@/components/ui/button';
import { ScrollArea } from '@/components/ui/scroll-area';
import { Skeleton } from '@/components/ui/skeleton';
import { Separator } from '@/components/ui/separator';

export function Alerts() {
  const { activeAlerts, resolvedAlerts, loading, error, refresh } = useAlerts();

  if (loading) {
    return (
      <div className="p-3 space-y-3">
        {[1, 2].map((i) => (
          <Skeleton key={i} className="h-16 w-full rounded-lg" />
        ))}
      </div>
    );
  }

  return (
    <div className="flex flex-col h-full">
      {/* Header */}
      <div className="flex items-center justify-between px-3 py-2">
        <div className="flex items-center gap-2">
          {activeAlerts.length > 0 ? (
            <Bell className="h-3.5 w-3.5 text-destructive" />
          ) : (
            <BellOff className="h-3.5 w-3.5 text-muted-foreground" />
          )}
          <span className="text-xs font-semibold">
            {activeAlerts.length > 0
              ? `${activeAlerts.length} active alert${activeAlerts.length > 1 ? 's' : ''}`
              : 'All clear'}
          </span>
        </div>
        <Button variant="ghost" size="icon" className="h-7 w-7" onClick={refresh}>
          <RefreshCw className="h-3.5 w-3.5" />
        </Button>
      </div>

      {error && (
        <div className="px-3 py-1 text-xs text-destructive">{error}</div>
      )}

      <ScrollArea className="flex-1 px-3">
        {activeAlerts.length === 0 && resolvedAlerts.length === 0 ? (
          <div className="text-center py-8">
            <div className="w-10 h-10 rounded-full bg-[hsl(var(--status-active))]/10 flex items-center justify-center mx-auto mb-3">
              <BellOff className="h-5 w-5 text-[hsl(var(--status-active))]" />
            </div>
            <p className="text-sm text-muted-foreground">No alerts.</p>
            <p className="text-xs text-muted-foreground mt-1">
              Alerts appear when agents raise flags or encounter blockages.
            </p>
          </div>
        ) : (
          <div className="space-y-2 pb-3">
            {activeAlerts.map((alert) => (
              <AlertBanner key={alert.id} alert={alert} />
            ))}

            {resolvedAlerts.length > 0 && activeAlerts.length > 0 && (
              <Separator className="my-2" />
            )}

            {resolvedAlerts.length > 0 && (
              <>
                <span className="text-[10px] text-muted-foreground font-medium uppercase tracking-wider">
                  Resolved ({resolvedAlerts.length})
                </span>
                {resolvedAlerts.map((alert) => (
                  <AlertBanner key={alert.id} alert={alert} />
                ))}
              </>
            )}
          </div>
        )}
      </ScrollArea>
    </div>
  );
}
