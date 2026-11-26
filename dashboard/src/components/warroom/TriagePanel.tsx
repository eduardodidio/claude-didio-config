import * as React from 'react';
import { X, Clock } from 'lucide-react';
import { createPortal } from 'react-dom';
import { cn } from '@/lib/utils';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import type {
  WarRoomCard,
  OverlordRecommendation,
  Priority,
} from '@/lib/warroomTypes';

// ---------------------------------------------------------------------------
// Props
// ---------------------------------------------------------------------------

export interface TriagePanelProps {
  card: WarRoomCard | null;
  onClose: () => void;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const RECOMMENDATION_STYLES: Record<
  OverlordRecommendation,
  { bg: string; text: string; label: string }
> = {
  promote: {
    bg: 'bg-green-100 dark:bg-green-900/40',
    text: 'text-green-800 dark:text-green-300',
    label: 'Promote',
  },
  defer: {
    bg: 'bg-amber-100 dark:bg-amber-900/40',
    text: 'text-amber-800 dark:text-amber-300',
    label: 'Defer',
  },
  archive: {
    bg: 'bg-gray-100 dark:bg-gray-800/60',
    text: 'text-gray-700 dark:text-gray-300',
    label: 'Archive',
  },
  needs_input: {
    bg: 'bg-blue-100 dark:bg-blue-900/40',
    text: 'text-blue-800 dark:text-blue-300',
    label: 'Needs Input',
  },
};

const PRIORITY_COLORS: Record<Priority, string> = {
  low: 'text-slate-500',
  medium: 'text-yellow-600 dark:text-yellow-400',
  high: 'text-orange-600 dark:text-orange-400',
  max: 'text-red-600 dark:text-red-400',
};

function formatRelativeTime(iso: string): string {
  const diff = Date.now() - new Date(iso).getTime();
  const minutes = Math.floor(diff / 60_000);
  if (minutes < 1) return 'just now';
  if (minutes < 60) return `${minutes}m ago`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours}h ago`;
  const days = Math.floor(hours / 24);
  return `${days}d ago`;
}

function formatAbsoluteTime(iso: string): string {
  return new Date(iso).toLocaleString();
}

// ---------------------------------------------------------------------------
// Recommendation Badge
// ---------------------------------------------------------------------------

function RecommendationBadge({
  recommendation,
}: {
  recommendation: OverlordRecommendation;
}) {
  const style = RECOMMENDATION_STYLES[recommendation];
  return (
    <span
      data-testid="recommendation-badge"
      className={cn(
        'inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-semibold',
        style.bg,
        style.text,
      )}
    >
      {style.label}
    </span>
  );
}

// ---------------------------------------------------------------------------
// Priority Indicator
// ---------------------------------------------------------------------------

function PriorityIndicator({ priority }: { priority: Priority }) {
  return (
    <span
      data-testid="priority-indicator"
      className={cn('font-semibold text-sm capitalize', PRIORITY_COLORS[priority])}
    >
      {priority}
    </span>
  );
}

// ---------------------------------------------------------------------------
// Component
// ---------------------------------------------------------------------------

export function TriagePanel({ card, onClose }: TriagePanelProps) {
  const [visible, setVisible] = React.useState(false);
  const isOpen = card !== null;

  React.useEffect(() => {
    if (isOpen) {
      const frame = requestAnimationFrame(() => setVisible(true));
      return () => cancelAnimationFrame(frame);
    }
    setVisible(false);
  }, [isOpen]);

  // Escape key
  React.useEffect(() => {
    if (!isOpen) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onClose();
    };
    document.addEventListener('keydown', onKey);
    return () => document.removeEventListener('keydown', onKey);
  }, [isOpen, onClose]);

  // ----- Empty state: no card selected -----
  if (!isOpen) {
    return (
      <div
        data-testid="triage-panel-placeholder"
        className="flex items-center justify-center h-full text-muted-foreground text-sm"
      >
        Select a card to view details
      </div>
    );
  }

  const assessment = card.overlord_assessment;

  const panel = (
    <>
      {/* Backdrop */}
      <div
        data-testid="triage-panel-backdrop"
        className={cn(
          'fixed inset-0 z-[50] bg-black/40 transition-opacity duration-200',
          visible ? 'opacity-100' : 'opacity-0',
        )}
        onClick={onClose}
      />

      {/* Slide-in panel */}
      <div
        data-testid="triage-panel"
        role="dialog"
        aria-modal="true"
        aria-label="Triage panel"
        className={cn(
          'fixed top-0 right-0 z-[51] h-full w-full max-w-lg bg-background border-l shadow-xl transition-transform duration-200 ease-out overflow-y-auto',
          visible ? 'translate-x-0' : 'translate-x-full',
        )}
      >
        {/* Header */}
        <div className="sticky top-0 bg-background z-10 flex items-center justify-between border-b p-4">
          <div className="flex items-center gap-2 min-w-0">
            <code className="text-xs text-muted-foreground font-mono shrink-0">
              {card.card_id}
            </code>
            <Badge variant="outline" className="text-xs capitalize shrink-0">
              {card.status}
            </Badge>
            <Badge variant="secondary" className="text-xs capitalize shrink-0">
              {card.source}
            </Badge>
          </div>
          <Button
            variant="ghost"
            size="icon"
            onClick={onClose}
            data-testid="triage-panel-close"
            aria-label="Close panel"
          >
            <X className="h-4 w-4" />
          </Button>
        </div>

        {/* Body */}
        <div className="p-4 space-y-6">
          {/* Title */}
          <h2 data-testid="triage-panel-title" className="text-lg font-semibold">
            {card.title}
          </h2>

          {/* Body text */}
          <div
            data-testid="triage-panel-body"
            className="text-sm whitespace-pre-line leading-relaxed text-muted-foreground"
          >
            {card.body}
          </div>

          {/* Metadata row */}
          <div className="flex flex-wrap items-center gap-3 text-xs text-muted-foreground">
            <span data-testid="triage-panel-created">
              {formatAbsoluteTime(card.created_at)} ({formatRelativeTime(card.created_at)})
            </span>
            {card.tags.length > 0 && (
              <div data-testid="triage-panel-tags" className="flex flex-wrap gap-1">
                {card.tags.map((tag) => (
                  <Badge key={tag} variant="secondary" className="text-xs">
                    {tag}
                  </Badge>
                ))}
              </div>
            )}
          </div>

          {/* Priority suggestion */}
          {card.priority_suggestion && (
            <div className="flex items-center gap-2">
              <span className="text-sm text-muted-foreground">Suggested priority:</span>
              <PriorityIndicator priority={card.priority_suggestion} />
            </div>
          )}

          {/* ---- Black Hawk Alpha Assessment ---- */}
          <div className="border-t pt-4">
            <h3 className="text-sm font-semibold mb-3">Black Hawk Alpha Assessment</h3>

            {assessment ? (
              <div
                data-testid="triage-assessment"
                className="space-y-3 rounded-md border p-4 bg-muted/30"
              >
                {/* Assessed at */}
                <div className="text-xs text-muted-foreground">
                  Assessed: {formatAbsoluteTime(assessment.assessed_at)} (
                  {formatRelativeTime(assessment.assessed_at)})
                </div>

                {/* Recommendation + Priority row */}
                <div className="flex items-center gap-3">
                  <RecommendationBadge recommendation={assessment.recommendation} />
                  <span className="text-muted-foreground text-xs">Priority:</span>
                  <PriorityIndicator priority={assessment.priority} />
                </div>

                {/* Rationale */}
                <blockquote
                  data-testid="triage-rationale"
                  className="border-l-4 border-muted-foreground/30 pl-3 text-sm text-muted-foreground italic"
                >
                  {assessment.rationale}
                </blockquote>

                {/* Promoted as */}
                {assessment.promoted_as && (
                  <div className="text-sm">
                    <span className="text-muted-foreground">Promoted as: </span>
                    <span
                      data-testid="triage-promoted-as"
                      className="font-medium text-primary"
                    >
                      {assessment.promoted_as}
                    </span>
                  </div>
                )}
              </div>
            ) : (
              <div
                data-testid="triage-no-assessment"
                className="flex items-center gap-2 text-sm text-muted-foreground py-4"
              >
                <Clock className="h-4 w-4" />
                <span>Not yet triaged by Black Hawk Alpha</span>
              </div>
            )}
          </div>
        </div>
      </div>
    </>
  );

  if (typeof document === 'undefined') return null;
  return createPortal(panel, document.body);
}
