import { RefreshCw } from 'lucide-react';
import { useBoardState } from '@/hooks/useBoardState';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { ScrollArea } from '@/components/ui/scroll-area';
import { Skeleton } from '@/components/ui/skeleton';
import { cn } from '@/lib/utils';
import type { BoardColumn } from '@/lib/types';

const COLUMNS: BoardColumn[] = ['BACKLOG', 'PLANNING', 'RUNNING', 'REVIEW', 'DONE'];

const columnColors: Record<BoardColumn, string> = {
  BACKLOG: 'bg-muted text-muted-foreground',
  PLANNING: 'bg-primary/20 text-primary',
  RUNNING: 'bg-[hsl(var(--status-warning))]/20 text-[hsl(var(--status-warning))]',
  REVIEW: 'bg-[hsl(var(--status-active))]/20 text-[hsl(var(--status-active))]',
  DONE: 'bg-[hsl(var(--status-active))]/10 text-[hsl(var(--status-active))]',
};

export function BoardMini() {
  const { board, loading, error, refresh } = useBoardState();

  if (loading) {
    return (
      <div className="p-3 space-y-3">
        {[1, 2, 3].map((i) => (
          <Skeleton key={i} className="h-16 w-full rounded-lg" />
        ))}
      </div>
    );
  }

  if (error) {
    return (
      <div className="p-3 text-center">
        <p className="text-sm text-destructive">{error}</p>
        <Button variant="ghost" size="sm" onClick={refresh} className="mt-2">
          Retry
        </Button>
      </div>
    );
  }

  return (
    <div className="flex flex-col h-full">
      {/* Header */}
      <div className="flex items-center justify-between px-3 py-2">
        <div>
          <span className="text-xs font-semibold">Standard Board</span>
          <span className="text-[10px] text-muted-foreground ml-2">
            {board.cards.length} features
          </span>
        </div>
        <Button variant="ghost" size="icon" className="h-7 w-7" onClick={refresh}>
          <RefreshCw className="h-3.5 w-3.5" />
        </Button>
      </div>

      <ScrollArea className="flex-1 px-3">
        {board.cards.length === 0 ? (
          <div className="text-center py-8">
            <p className="text-sm text-muted-foreground">No features on the board.</p>
            <p className="text-xs text-muted-foreground mt-1">
              Promote War Room cards to populate.
            </p>
          </div>
        ) : (
          <div className="space-y-2 pb-3">
            {/* Group by column */}
            {COLUMNS.map((col) => {
              const cards = board.cards.filter((c) => c.column === col);
              if (cards.length === 0) return null;
              return (
                <div key={col}>
                  <div className="flex items-center gap-2 mb-1.5">
                    <Badge variant="secondary" className={cn('text-[10px] px-1.5 py-0', columnColors[col])}>
                      {col}
                    </Badge>
                    <span className="text-[10px] text-muted-foreground">{cards.length}</span>
                  </div>
                  {cards.map((card) => (
                    <div
                      key={card.feature}
                      className="surface-card px-3 py-2 mb-1.5"
                    >
                      <div className="flex items-center justify-between">
                        <span className="text-xs font-mono font-medium truncate">
                          {card.feature}
                        </span>
                        {card.hasBlockage && (
                          <span className="text-[10px] text-destructive font-bold">BLOCKED</span>
                        )}
                      </div>
                      {/* Progress bar */}
                      <div className="mt-1.5 flex items-center gap-2">
                        <div className="flex-1 h-1 bg-muted rounded-full overflow-hidden">
                          <div
                            className={cn(
                              'h-full rounded-full transition-all',
                              card.hasBlockage ? 'bg-destructive' : 'bg-primary'
                            )}
                            style={{ width: `${card.progress}%` }}
                          />
                        </div>
                        <span className="text-[10px] text-muted-foreground font-mono w-10 text-right">
                          {card.taskDone}/{card.taskTotal}
                        </span>
                      </div>
                      {card.currentPhase && (
                        <span className="text-[10px] text-muted-foreground mt-1 block">
                          {card.currentPhase}
                        </span>
                      )}
                    </div>
                  ))}
                </div>
              );
            })}
          </div>
        )}
      </ScrollArea>

      {board.lastUpdated && (
        <div className="px-3 py-1 border-t border-border">
          <span className="text-[10px] text-muted-foreground">
            Updated: {new Date(board.lastUpdated).toLocaleTimeString()}
          </span>
        </div>
      )}
    </div>
  );
}
