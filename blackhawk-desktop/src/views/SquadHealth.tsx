import { Shield, RefreshCw, Activity, Eye, Lock } from 'lucide-react';
import { useSquadHealth } from '@/hooks/useSquadHealth';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { ScrollArea } from '@/components/ui/scroll-area';
import { Skeleton } from '@/components/ui/skeleton';
import { cn } from '@/lib/utils';
import type { ScannerStatus, SquadCorrelation } from '@/lib/types';

const statusColors: Record<ScannerStatus, string> = {
  ok: 'bg-[hsl(var(--status-active))] text-[hsl(var(--status-active))]',
  warning: 'bg-[hsl(var(--status-warning))] text-[hsl(var(--status-warning))]',
  critical: 'bg-destructive text-destructive',
  disabled: 'bg-muted text-muted-foreground',
};

const statusDotColors: Record<ScannerStatus, string> = {
  ok: 'bg-[hsl(var(--status-active))]',
  warning: 'bg-[hsl(var(--status-warning))]',
  critical: 'bg-destructive animate-pulse',
  disabled: 'bg-muted-foreground',
};

const scannerIcons: Record<string, typeof Shield> = {
  bravo: Activity,
  charlie: Eye,
  delta: Lock,
};

const scannerLabels: Record<string, string> = {
  bravo: 'Bravo (CI/CD)',
  charlie: 'Charlie (Monitor)',
  delta: 'Delta (Security)',
};

function StatusDot({ status }: { status: ScannerStatus }) {
  return <div className={cn('w-2.5 h-2.5 rounded-full', statusDotColors[status])} />;
}

function ScannerCard({ name, status }: { name: string; status: ScannerStatus }) {
  const Icon = scannerIcons[name] ?? Shield;
  const label = scannerLabels[name] ?? name;

  return (
    <div className="flex items-center gap-3 p-3 rounded-lg border border-border">
      <Icon className="h-4 w-4 text-muted-foreground" />
      <div className="flex-1">
        <p className="text-xs font-medium">{label}</p>
      </div>
      <div className="flex items-center gap-1.5">
        <StatusDot status={status} />
        <Badge variant="outline" className={cn('text-[10px] uppercase', statusColors[status])}>
          {status}
        </Badge>
      </div>
    </div>
  );
}

function CorrelationItem({ correlation }: { correlation: SquadCorrelation }) {
  return (
    <div className="p-2.5 rounded-md border border-destructive/30 bg-destructive/5">
      <div className="flex items-center gap-1.5 mb-1">
        <Badge variant="destructive" className="text-[9px]">
          {correlation.severity}
        </Badge>
        <span className="text-[10px] text-muted-foreground">
          {correlation.scanners.join(' + ')}
        </span>
      </div>
      <p className="text-xs">{correlation.detail}</p>
    </div>
  );
}

export function SquadHealth() {
  const { report, loading, error, scanning, scan } = useSquadHealth();

  if (loading) {
    return (
      <div className="p-3 space-y-3">
        {[1, 2, 3].map((i) => (
          <Skeleton key={i} className="h-14 w-full rounded-lg" />
        ))}
      </div>
    );
  }

  if (error && !report) {
    return (
      <div className="p-4 text-center text-sm text-muted-foreground">
        <p>Squad health unavailable</p>
        <p className="text-xs mt-1">{error}</p>
        <Button variant="outline" size="sm" className="mt-3" onClick={scan}>
          Run Scan
        </Button>
      </div>
    );
  }

  return (
    <ScrollArea className="h-full">
      <div className="p-3 space-y-3">
        {/* Header with overall status + scan button */}
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-2">
            <Shield className="h-4 w-4" />
            <span className="text-sm font-semibold">Squad Health</span>
            {report && (
              <Badge variant="outline" className={cn('text-[10px]', statusColors[report.overall_status])}>
                {report.overall_status}
              </Badge>
            )}
          </div>
          <Button
            variant="ghost"
            size="sm"
            className="h-7 w-7 p-0"
            onClick={scan}
            disabled={scanning}
          >
            <RefreshCw className={cn('h-3.5 w-3.5', scanning && 'animate-spin')} />
          </Button>
        </div>

        {/* Scanner statuses */}
        {report ? (
          <>
            <div className="space-y-2">
              <ScannerCard name="bravo" status={report.squad_status.bravo} />
              <ScannerCard name="charlie" status={report.squad_status.charlie} />
              <ScannerCard name="delta" status={report.squad_status.delta} />
            </div>

            {/* Correlations */}
            {report.correlations.length > 0 && (
              <Card>
                <CardHeader className="py-2 px-3">
                  <CardTitle className="text-xs font-medium">
                    Correlations ({report.correlations.length})
                  </CardTitle>
                </CardHeader>
                <CardContent className="px-3 pb-3 space-y-2">
                  {report.correlations.map((c, i) => (
                    <CorrelationItem key={i} correlation={c} />
                  ))}
                </CardContent>
              </Card>
            )}

            {/* Report timestamp */}
            <p className="text-[10px] text-muted-foreground text-center">
              Last scan: {report.timestamp.replace('T', ' ').replace('Z', ' UTC')}
            </p>
          </>
        ) : (
          <div className="text-center text-sm text-muted-foreground py-6">
            <p>No squad report yet</p>
            <Button variant="outline" size="sm" className="mt-3" onClick={scan}>
              Run First Scan
            </Button>
          </div>
        )}
      </div>
    </ScrollArea>
  );
}
