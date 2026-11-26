// ---------------------------------------------------------------------------
// F30-T04 — KanbanCardDetail component
// A dialog that opens when clicking a card, showing full feature info.
// ---------------------------------------------------------------------------

import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
} from '@/components/ui/dialog';
import { Progress } from '@/components/ui/progress';
import { Badge } from '@/components/ui/badge';
import { flagDotClass } from '@/lib/kanbanHelpers';
import type { KanbanCard } from '@/lib/kanbanTypes';

export interface KanbanCardDetailProps {
  card: KanbanCard | null;
  open: boolean;
  onOpenChange: (open: boolean) => void;
}

export function KanbanCardDetail({
  card,
  open,
  onOpenChange,
}: KanbanCardDetailProps) {
  if (!card) return null;

  const unresolvedFlags = card.flags.filter((f) => !f.resolved_at);
  const resolvedFlags = card.flags.filter((f) => f.resolved_at);

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent
        className="max-w-lg"
        onClose={() => onOpenChange(false)}
        data-testid={`card-detail-${card.feature}`}
      >
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <span className="font-mono">{card.feature}</span>
            {card.isBlocked && (
              <Badge variant="destructive" data-testid="detail-blocked-badge">
                BLOCKED
              </Badge>
            )}
            <Badge variant="outline" className="ml-auto capitalize">
              {card.column}
            </Badge>
          </DialogTitle>
          <DialogDescription>
            {card.currentPhase
              ? `Current phase: ${card.currentPhase}${card.currentTask ? ` / ${card.currentTask}` : ''}`
              : 'No active phase'}
          </DialogDescription>
        </DialogHeader>

        {/* Progress section */}
        <div className="space-y-2" data-testid="detail-progress">
          <div className="flex items-center justify-between text-sm">
            <span className="text-muted-foreground">Progress</span>
            <span className="tabular-nums font-medium">
              {card.completedTasks}/{card.taskCount} tasks ({card.progress}%)
            </span>
          </div>
          <Progress value={card.progress} />
        </div>

        {/* Priority */}
        <div className="flex items-center gap-2 text-sm">
          <span className="text-muted-foreground">Priority:</span>
          <Badge
            variant="secondary"
            className="capitalize"
            data-testid="detail-priority"
          >
            {card.priority}
          </Badge>
        </div>

        {/* Active flags */}
        {unresolvedFlags.length > 0 && (
          <div className="space-y-2" data-testid="detail-active-flags">
            <h4 className="text-sm font-semibold">
              Active flags ({unresolvedFlags.length})
            </h4>
            <div className="space-y-2">
              {unresolvedFlags.map((flag) => (
                <div
                  key={flag.flag_id}
                  className="flex items-start gap-2 rounded-md border p-2 text-sm"
                  data-testid={`detail-flag-${flag.flag_id}`}
                >
                  <span
                    className={`mt-1 inline-block h-2.5 w-2.5 shrink-0 rounded-full ${flagDotClass(flag.severity, flag.type)}`}
                  />
                  <div className="min-w-0 flex-1">
                    <div className="flex items-center gap-1.5">
                      <span className="font-medium capitalize">{flag.type}</span>
                      <Badge variant="outline" className="text-[10px] capitalize">
                        {flag.severity}
                      </Badge>
                    </div>
                    <p className="text-muted-foreground mt-0.5 break-words">
                      {flag.reason}
                    </p>
                    {flag.suggested_actions.length > 0 && (
                      <ul className="mt-1 list-disc pl-4 text-xs text-muted-foreground">
                        {flag.suggested_actions.map((action, i) => (
                          <li key={i}>{action}</li>
                        ))}
                      </ul>
                    )}
                  </div>
                </div>
              ))}
            </div>
          </div>
        )}

        {/* Resolved flags */}
        {resolvedFlags.length > 0 && (
          <div className="space-y-2" data-testid="detail-resolved-flags">
            <h4 className="text-sm font-semibold text-muted-foreground">
              Resolved flags ({resolvedFlags.length})
            </h4>
            <div className="space-y-1">
              {resolvedFlags.map((flag) => (
                <div
                  key={flag.flag_id}
                  className="flex items-center gap-2 text-xs text-muted-foreground"
                >
                  <span className="inline-block h-2 w-2 rounded-full bg-muted-foreground/30" />
                  <span className="capitalize">{flag.type}</span>
                  <span>-</span>
                  <span className="truncate">{flag.reason}</span>
                </div>
              ))}
            </div>
          </div>
        )}

        {/* Empty flags state */}
        {card.flags.length === 0 && (
          <p
            className="text-sm text-muted-foreground"
            data-testid="detail-no-flags"
          >
            No flags for this feature.
          </p>
        )}
      </DialogContent>
    </Dialog>
  );
}

export default KanbanCardDetail;
