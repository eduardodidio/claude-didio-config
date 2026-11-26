// ---------------------------------------------------------------------------
// F30-T04 — KanbanColumn component
// A vertical lane representing a pipeline phase in the Kanban board.
// ---------------------------------------------------------------------------

import { ScrollArea } from '@/components/ui/scroll-area';
import { Badge } from '@/components/ui/badge';
import { COLUMN_CONFIG } from '@/lib/kanbanHelpers';
import { KanbanCard } from './KanbanCard';
import type { KanbanColumn as KanbanColumnType, KanbanCard as KanbanCardType } from '@/lib/kanbanTypes';

export interface KanbanColumnProps {
  title: KanbanColumnType;
  cards: KanbanCardType[];
  onCardClick?: (feature: string) => void;
}

export function KanbanColumn({ title, cards, onCardClick }: KanbanColumnProps) {
  const config = COLUMN_CONFIG[title];

  return (
    <div
      className={`flex flex-col rounded-lg ${config.bgClass} min-w-[280px] w-[280px]`}
      data-testid={`kanban-column-${title}`}
    >
      {/* Column header */}
      <div className="flex items-center justify-between p-3 pb-2">
        <h3
          className={`text-sm font-semibold ${config.headerClass}`}
          data-testid={`column-title-${title}`}
        >
          {config.label}
        </h3>
        <Badge
          variant="secondary"
          className="text-xs tabular-nums"
          data-testid={`column-count-${title}`}
        >
          {cards.length}
        </Badge>
      </div>

      {/* Scrollable card area */}
      <ScrollArea className="flex-1 px-3 pb-3">
        {cards.length === 0 ? (
          <p
            className="py-8 text-center text-xs text-muted-foreground"
            data-testid={`column-empty-${title}`}
          >
            No features
          </p>
        ) : (
          <div className="space-y-2">
            {cards.map((card) => (
              <KanbanCard
                key={card.feature}
                card={card}
                onClick={onCardClick ? () => onCardClick(card.feature) : undefined}
              />
            ))}
          </div>
        )}
      </ScrollArea>
    </div>
  );
}

export default KanbanColumn;
