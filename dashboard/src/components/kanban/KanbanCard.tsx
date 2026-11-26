// ---------------------------------------------------------------------------
// F30-T04 — KanbanCard component
// A card representing a single feature within a Kanban column.
// ---------------------------------------------------------------------------

import { motion } from 'framer-motion';
import { Card, CardContent } from '@/components/ui/card';
import { Progress } from '@/components/ui/progress';
import { Badge } from '@/components/ui/badge';
import { flagDotClass } from '@/lib/kanbanHelpers';
import type { KanbanCard as KanbanCardType } from '@/lib/kanbanTypes';

export interface KanbanCardProps {
  card: KanbanCardType;
  onClick?: () => void;
}

export function KanbanCard({ card, onClick }: KanbanCardProps) {
  const unresolvedFlags = card.flags.filter((f) => !f.resolved_at);

  return (
    <motion.div
      whileHover={{ scale: 1.02 }}
      transition={{ duration: 0.15 }}
      className="cursor-pointer"
      data-testid={`kanban-card-${card.feature}`}
    >
      <Card
        className={`relative overflow-hidden transition-shadow hover:shadow-md ${
          card.isBlocked ? 'opacity-60' : ''
        }`}
        onClick={onClick}
      >
        {/* Blocked overlay badge */}
        {card.isBlocked && (
          <Badge
            variant="destructive"
            className="absolute right-2 top-2 z-10"
            data-testid={`blocked-badge-${card.feature}`}
          >
            BLOCKED
          </Badge>
        )}

        <CardContent className="p-3 space-y-2">
          {/* Feature ID + current phase */}
          <div className="flex items-center justify-between gap-2">
            <span
              className="font-bold font-mono text-sm"
              data-testid={`card-feature-id-${card.feature}`}
            >
              {card.feature}
            </span>
            {card.currentPhase && (
              <span className="text-xs text-muted-foreground truncate">
                {card.currentPhase}
                {card.currentTask ? ` / ${card.currentTask}` : ''}
              </span>
            )}
          </div>

          {/* Progress bar */}
          <Progress
            value={card.progress}
            className="h-1.5"
            data-testid={`card-progress-${card.feature}`}
          />

          {/* Task count + flag dots */}
          <div className="flex items-center justify-between">
            <span
              className="text-xs text-muted-foreground tabular-nums"
              data-testid={`card-task-count-${card.feature}`}
            >
              {card.completedTasks}/{card.taskCount} tasks
            </span>

            {/* Flag indicator dots */}
            {unresolvedFlags.length > 0 && (
              <div
                className="flex items-center gap-1"
                data-testid={`card-flags-${card.feature}`}
              >
                {unresolvedFlags.map((flag) => (
                  <span
                    key={flag.flag_id}
                    className={`inline-block h-2 w-2 rounded-full ${flagDotClass(flag.severity, flag.type)}`}
                    title={`${flag.type} (${flag.severity})`}
                    data-testid={`flag-dot-${flag.flag_id}`}
                  />
                ))}
              </div>
            )}
          </div>
        </CardContent>
      </Card>
    </motion.div>
  );
}

export default KanbanCard;
