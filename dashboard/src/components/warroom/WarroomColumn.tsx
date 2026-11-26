// ---------------------------------------------------------------------------
// F31-T04 -- WarroomColumn component
// A vertical lane representing one War Room status in the board.
// ---------------------------------------------------------------------------

import { ScrollArea } from '@/components/ui/scroll-area';
import { Badge } from '@/components/ui/badge';
import { WARROOM_COLUMN_LABELS } from '@/lib/warroomTypes';
import { WarroomCard } from './WarroomCard';
import type { WarRoomStatus, WarRoomCard as WarRoomCardType } from '@/lib/warroomTypes';

// ---------------------------------------------------------------------------
// Props
// ---------------------------------------------------------------------------

export interface WarroomColumnProps {
  status: WarRoomStatus;
  cards: WarRoomCardType[];
  onCardSelect?: (cardId: string) => void;
}

// ---------------------------------------------------------------------------
// Column color configuration
// ---------------------------------------------------------------------------

interface ColumnColors {
  bgClass: string;
  headerClass: string;
  countClass: string;
}

const COLUMN_COLORS: Record<WarRoomStatus, ColumnColors> = {
  incoming: {
    bgClass: 'bg-blue-50/60 dark:bg-blue-950/30',
    headerClass: 'text-blue-700 dark:text-blue-300',
    countClass: 'bg-blue-100 text-blue-700 dark:bg-blue-900 dark:text-blue-300',
  },
  triaging: {
    bgClass: 'bg-amber-50/60 dark:bg-amber-950/30',
    headerClass: 'text-amber-700 dark:text-amber-300',
    countClass: 'bg-amber-100 text-amber-700 dark:bg-amber-900 dark:text-amber-300',
  },
  promoted: {
    bgClass: 'bg-green-50/60 dark:bg-green-950/30',
    headerClass: 'text-green-700 dark:text-green-300',
    countClass: 'bg-green-100 text-green-700 dark:bg-green-900 dark:text-green-300',
  },
  deferred: {
    bgClass: 'bg-gray-50/60 dark:bg-gray-950/30',
    headerClass: 'text-gray-600 dark:text-gray-400',
    countClass: 'bg-gray-100 text-gray-600 dark:bg-gray-800 dark:text-gray-400',
  },
  archived: {
    bgClass: 'bg-slate-50/60 dark:bg-slate-950/30',
    headerClass: 'text-slate-500 dark:text-slate-400',
    countClass: 'bg-slate-100 text-slate-500 dark:bg-slate-800 dark:text-slate-400',
  },
};

// ---------------------------------------------------------------------------
// Component
// ---------------------------------------------------------------------------

export function WarroomColumn({ status, cards, onCardSelect }: WarroomColumnProps) {
  const colors = COLUMN_COLORS[status];
  const label = WARROOM_COLUMN_LABELS[status];

  return (
    <div
      className={`flex flex-col rounded-lg ${colors.bgClass} min-w-[280px] w-[280px]`}
      data-testid={`warroom-column-${status}`}
    >
      {/* Column header */}
      <div className="flex items-center justify-between p-3 pb-2">
        <h3
          className={`text-sm font-semibold ${colors.headerClass}`}
          data-testid={`warroom-column-title-${status}`}
        >
          {label}
        </h3>
        <Badge
          variant="secondary"
          className={`text-xs tabular-nums ${colors.countClass}`}
          data-testid={`warroom-column-count-${status}`}
        >
          {cards.length}
        </Badge>
      </div>

      {/* Scrollable card area */}
      <ScrollArea className="flex-1 px-3 pb-3">
        {cards.length === 0 ? (
          <p
            className="py-8 text-center text-xs text-muted-foreground"
            data-testid={`warroom-column-empty-${status}`}
          >
            No cards
          </p>
        ) : (
          <div className="space-y-2">
            {cards.map((card) => (
              <WarroomCard
                key={card.card_id}
                card={card}
                onSelect={onCardSelect}
              />
            ))}
          </div>
        )}
      </ScrollArea>
    </div>
  );
}

export default WarroomColumn;
