// ---------------------------------------------------------------------------
// F30-T05 — FlagPanel sidebar component
// Displays active agent flags grouped by severity with action buttons.
// ---------------------------------------------------------------------------

import { useState } from 'react';
import type { AgentFlag, ActionType, FlagSeverity } from '@/lib/kanbanTypes';
import { relativeTime } from '@/lib/timeUtils';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { ScrollArea } from '@/components/ui/scroll-area';
import { Tabs, TabsList, TabsTrigger, TabsContent } from '@/components/ui/tabs';
import { Skeleton } from '@/components/ui/skeleton';
import { cn } from '@/lib/utils';

// ---------------------------------------------------------------------------
// Action mapping
// ---------------------------------------------------------------------------

type ButtonVariant = 'default' | 'destructive' | 'outline' | 'secondary' | 'ghost' | 'link';

const ACTION_MAP: Record<
  string,
  { action: ActionType; label: string; variant: ButtonVariant }
> = {
  auto_resolve: { action: 'unblock', label: 'Unblock', variant: 'default' },
  manual_review: { action: 'approve', label: 'Approve', variant: 'outline' },
  skip_task: { action: 'skip', label: 'Skip', variant: 'destructive' },
  pause_pipeline: { action: 'pause', label: 'Pause', variant: 'outline' },
  resume_pipeline: { action: 'resume', label: 'Resume', variant: 'default' },
  cancel_feature: { action: 'cancel', label: 'Cancel', variant: 'destructive' },
};

// ---------------------------------------------------------------------------
// Severity helpers
// ---------------------------------------------------------------------------

const SEVERITY_ORDER: Record<FlagSeverity, number> = {
  critical: 0,
  warning: 1,
  info: 2,
};

const SEVERITY_BORDER: Record<FlagSeverity, string> = {
  critical: 'border-l-red-500',
  warning: 'border-l-amber-500',
  info: 'border-l-blue-500',
};

const SEVERITY_BADGE_CLASS: Record<FlagSeverity, string> = {
  critical: 'bg-red-500/15 text-red-600 border-red-500/30',
  warning: 'bg-amber-500/15 text-amber-600 border-amber-500/30',
  info: 'bg-blue-500/15 text-blue-600 border-blue-500/30',
};

function sortBySeverity(flags: AgentFlag[]): AgentFlag[] {
  return [...flags].sort(
    (a, b) => SEVERITY_ORDER[a.severity] - SEVERITY_ORDER[b.severity],
  );
}

// ---------------------------------------------------------------------------
// FlagCard
// ---------------------------------------------------------------------------

interface FlagCardProps {
  flag: AgentFlag;
  onAction: (action: ActionType, flag: AgentFlag) => void;
  dimmed?: boolean;
}

function FlagCard({ flag, onAction, dimmed = false }: FlagCardProps) {
  const [expanded, setExpanded] = useState(false);

  const taskRef = flag.task ? ` / ${flag.task}` : '';
  const actionEntries = flag.suggested_actions
    .map((key) => ACTION_MAP[key])
    .filter(Boolean);

  return (
    <div
      data-testid={`flag-card-${flag.flag_id}`}
      className={cn(
        'rounded-md border border-l-4 p-3 space-y-2',
        SEVERITY_BORDER[flag.severity],
        dimmed && 'opacity-50',
      )}
    >
      {/* Header row */}
      <div className="flex items-center justify-between gap-2 flex-wrap">
        <div className="flex items-center gap-2">
          <Badge
            className={cn('text-[10px] uppercase', SEVERITY_BADGE_CLASS[flag.severity])}
          >
            {flag.type.replace('_', ' ')}
          </Badge>
          <span className="text-xs text-muted-foreground">
            {flag.feature}{taskRef}
          </span>
        </div>
        <Badge variant="outline" className="text-[10px]">
          {flag.severity}
        </Badge>
      </div>

      {/* Reason */}
      <button
        type="button"
        className="text-sm text-left w-full"
        onClick={() => setExpanded((v) => !v)}
        data-testid={`flag-reason-${flag.flag_id}`}
      >
        <span className={cn(!expanded && 'line-clamp-2')}>
          {flag.reason}
        </span>
      </button>

      {/* Timestamp */}
      <div className="text-xs text-muted-foreground">
        {flag.resolved_at ? `Resolved ${relativeTime(flag.resolved_at)}` : `Created ${relativeTime(flag.created_at)}`}
      </div>

      {/* Action buttons */}
      {!dimmed && (
        <div className="flex flex-wrap gap-1.5 pt-1" data-testid={`flag-actions-${flag.flag_id}`}>
          {actionEntries.map((entry) => (
            <Button
              key={entry.action}
              variant={entry.variant}
              size="sm"
              className="h-7 text-xs px-2"
              onClick={() => onAction(entry.action, flag)}
            >
              {entry.label}
            </Button>
          ))}
          {/* Fallback dismiss button always present */}
          <Button
            variant="ghost"
            size="sm"
            className="h-7 text-xs px-2"
            onClick={() => onAction('approve', flag)}
          >
            Dismiss
          </Button>
        </div>
      )}
    </div>
  );
}

// ---------------------------------------------------------------------------
// FlagPanel
// ---------------------------------------------------------------------------

export interface FlagPanelProps {
  flags: AgentFlag[];
  onAction: (action: ActionType, flag: AgentFlag) => void;
  isLoading?: boolean;
}

export function FlagPanel({ flags, onAction, isLoading }: FlagPanelProps) {
  const [resolvedOpen, setResolvedOpen] = useState(false);

  const activeFlags = flags.filter((f) => f.resolved_at === null);
  const resolvedFlags = flags.filter((f) => f.resolved_at !== null);

  const filterByTab = (tab: string, list: AgentFlag[]): AgentFlag[] => {
    if (tab === 'all') return sortBySeverity(list);
    return sortBySeverity(list.filter((f) => f.severity === tab));
  };

  if (isLoading) {
    return (
      <div data-testid="flag-panel-skeleton" className="space-y-3 p-4">
        <Skeleton className="h-6 w-24" />
        <Skeleton className="h-10 w-full" />
        <Skeleton className="h-24 w-full" />
        <Skeleton className="h-24 w-full" />
      </div>
    );
  }

  return (
    <div data-testid="flag-panel" className="flex flex-col h-full">
      {/* Header */}
      <div className="flex items-center gap-2 px-4 py-3 border-b">
        <h2 className="text-sm font-semibold">Flags</h2>
        {activeFlags.length > 0 && (
          <Badge variant="secondary" className="text-xs" data-testid="flag-count-badge">
            {activeFlags.length}
          </Badge>
        )}
      </div>

      {/* Tabs + Content */}
      <Tabs defaultValue="all" className="flex-1 flex flex-col min-h-0">
        <div className="px-4 pt-3">
          <TabsList className="w-full">
            <TabsTrigger value="all" className="flex-1 text-xs">All</TabsTrigger>
            <TabsTrigger value="critical" className="flex-1 text-xs">Critical</TabsTrigger>
            <TabsTrigger value="warning" className="flex-1 text-xs">Warning</TabsTrigger>
            <TabsTrigger value="info" className="flex-1 text-xs">Info</TabsTrigger>
          </TabsList>
        </div>

        {(['all', 'critical', 'warning', 'info'] as const).map((tab) => (
          <TabsContent key={tab} value={tab} className="flex-1 min-h-0 mt-0">
            <ScrollArea className="h-full">
              <div className="space-y-2 p-4">
                {filterByTab(tab, activeFlags).length === 0 ? (
                  <EmptyState />
                ) : (
                  filterByTab(tab, activeFlags).map((flag) => (
                    <FlagCard key={flag.flag_id} flag={flag} onAction={onAction} />
                  ))
                )}
              </div>
            </ScrollArea>
          </TabsContent>
        ))}
      </Tabs>

      {/* Resolved section */}
      {resolvedFlags.length > 0 && (
        <div className="border-t" data-testid="resolved-section">
          <button
            type="button"
            className="flex items-center justify-between w-full px-4 py-2 text-xs text-muted-foreground hover:bg-muted/50 transition-colors"
            onClick={() => setResolvedOpen((v) => !v)}
            data-testid="resolved-toggle"
          >
            <span>Resolved ({resolvedFlags.length})</span>
            <span className={cn('transition-transform', resolvedOpen && 'rotate-180')}>
              &#9660;
            </span>
          </button>
          {resolvedOpen && (
            <div className="space-y-2 px-4 pb-3" data-testid="resolved-list">
              {sortBySeverity(resolvedFlags).map((flag) => (
                <FlagCard key={flag.flag_id} flag={flag} onAction={onAction} dimmed />
              ))}
            </div>
          )}
        </div>
      )}
    </div>
  );
}

// ---------------------------------------------------------------------------
// EmptyState
// ---------------------------------------------------------------------------

function EmptyState() {
  return (
    <div
      data-testid="flag-panel-empty"
      className="flex flex-col items-center justify-center py-12 text-center space-y-2"
    >
      <svg
        xmlns="http://www.w3.org/2000/svg"
        className="h-8 w-8 text-green-500"
        viewBox="0 0 24 24"
        fill="none"
        stroke="currentColor"
        strokeWidth={2}
        strokeLinecap="round"
        strokeLinejoin="round"
        aria-hidden="true"
      >
        <path d="M22 11.08V12a10 10 0 1 1-5.93-9.14" />
        <polyline points="22 4 12 14.01 9 11.01" />
      </svg>
      <p className="text-sm text-muted-foreground">
        No active flags. All systems operational.
      </p>
    </div>
  );
}

export default FlagPanel;
