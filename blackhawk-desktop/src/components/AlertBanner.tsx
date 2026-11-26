import { AlertTriangle, CheckCircle, Info } from 'lucide-react';
import type { Alert } from '@/lib/types';
import { cn } from '@/lib/utils';

interface Props {
  alert: Alert;
}

const severityConfig = {
  critical: {
    icon: AlertTriangle,
    bg: 'bg-destructive/10 border-destructive/30',
    text: 'text-destructive',
    label: 'CRITICAL',
  },
  warning: {
    icon: AlertTriangle,
    bg: 'bg-[hsl(var(--status-warning))]/10 border-[hsl(var(--status-warning))]/30',
    text: 'text-[hsl(var(--status-warning))]',
    label: 'WARNING',
  },
  info: {
    icon: Info,
    bg: 'bg-primary/10 border-primary/30',
    text: 'text-primary',
    label: 'INFO',
  },
};

export function AlertBanner({ alert }: Props) {
  const config = severityConfig[alert.severity as keyof typeof severityConfig] ?? severityConfig.info;
  const Icon = alert.status === 'resolved' ? CheckCircle : config.icon;
  const isResolved = alert.status === 'resolved';

  return (
    <div
      className={cn(
        'flex items-start gap-2 rounded-lg border px-3 py-2',
        isResolved ? 'bg-secondary/50 border-border opacity-60' : config.bg
      )}
    >
      <Icon className={cn('h-4 w-4 mt-0.5 shrink-0', isResolved ? 'text-muted-foreground' : config.text)} />
      <div className="flex-1 min-w-0">
        <div className="flex items-center gap-2">
          <span className={cn('text-[10px] font-bold tracking-wider', isResolved ? 'text-muted-foreground' : config.text)}>
            {isResolved ? 'RESOLVED' : config.label}
          </span>
          {alert.feature && (
            <span className="text-[10px] text-muted-foreground font-mono">{alert.feature}</span>
          )}
        </div>
        <p className="text-xs text-foreground leading-relaxed mt-0.5">{alert.message}</p>
        <span className="text-[10px] text-muted-foreground mt-1 block">
          {new Date(alert.created_at).toLocaleString()}
        </span>
      </div>
    </div>
  );
}
