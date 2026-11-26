// ---------------------------------------------------------------------------
// F30-T08 — KanbanBoard view
// Assembles kanban columns + flag panel with routing integration.
// ---------------------------------------------------------------------------

import { useState, useCallback } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import { useKanbanState } from '@/hooks/useKanbanState';
import { useActions } from '@/hooks/useActions';
import { KanbanColumn, KanbanCardDetail } from '@/components/kanban';
import { FlagPanel } from '@/components/kanban/FlagPanel';
import { Skeleton } from '@/components/ui/skeleton';
import { KANBAN_COLUMNS } from '@/lib/kanbanTypes';
import type { KanbanCard, KanbanColumn as KanbanColumnType, ActionType, AgentFlag } from '@/lib/kanbanTypes';

// ---------------------------------------------------------------------------
// Loading skeleton
// ---------------------------------------------------------------------------

function KanbanBoardSkeleton() {
  return (
    <div data-testid="kanban-board-skeleton" className="flex gap-4 h-full">
      {/* Column skeletons */}
      <div className="flex gap-4 flex-1 overflow-x-auto pb-4">
        {KANBAN_COLUMNS.map((col) => (
          <div key={col} className="min-w-[280px] w-[280px] space-y-3">
            <Skeleton className="h-8 w-full rounded-lg" />
            <Skeleton className="h-24 w-full rounded-lg" />
            <Skeleton className="h-24 w-full rounded-lg" />
            <Skeleton className="h-24 w-full rounded-lg" />
          </div>
        ))}
      </div>
      {/* Flag panel skeleton */}
      <div className="hidden xl:block w-[320px] shrink-0 space-y-3">
        <Skeleton className="h-6 w-24" />
        <Skeleton className="h-10 w-full" />
        <Skeleton className="h-24 w-full" />
        <Skeleton className="h-24 w-full" />
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// KanbanBoard
// ---------------------------------------------------------------------------

export function KanbanBoard() {
  const { data: boardState, isLoading, isError, error } = useKanbanState();
  const actions = useActions();

  const [selectedFeature, setSelectedFeature] = useState<string | null>(null);
  const [detailOpen, setDetailOpen] = useState(false);

  const handleCardClick = useCallback((feature: string) => {
    setSelectedFeature(feature);
    setDetailOpen(true);
  }, []);

  const handleFlagAction = useCallback(
    (action: ActionType, flag: AgentFlag) => {
      actions.dispatch(action, flag.feature, flag.task);
    },
    [actions],
  );

  // -- Loading state --------------------------------------------------------
  if (isLoading) return <KanbanBoardSkeleton />;

  // -- Error state ----------------------------------------------------------
  if (isError || !boardState) {
    return (
      <div
        role="alert"
        data-testid="kanban-board-error"
        className="rounded-md border border-red-500/40 bg-red-500/10 p-4 text-red-600"
      >
        Failed to load kanban board
        {error instanceof Error ? `: ${error.message}` : '.'}
      </div>
    );
  }

  // -- Empty state ----------------------------------------------------------
  if (boardState.cards.length === 0) {
    return (
      <motion.div
        initial={{ opacity: 0, y: 6 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.2 }}
        data-testid="kanban-board-empty"
        className="flex flex-col items-center justify-center py-20 text-center space-y-3"
      >
        <svg
          xmlns="http://www.w3.org/2000/svg"
          className="h-10 w-10 text-muted-foreground"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          strokeWidth={1.5}
          strokeLinecap="round"
          strokeLinejoin="round"
          aria-hidden="true"
        >
          <rect x="3" y="3" width="7" height="7" />
          <rect x="14" y="3" width="7" height="7" />
          <rect x="3" y="14" width="7" height="7" />
          <rect x="14" y="14" width="7" height="7" />
        </svg>
        <p className="text-sm text-muted-foreground">
          No features in the pipeline. Create a feature to get started.
        </p>
      </motion.div>
    );
  }

  // -- Group cards by column ------------------------------------------------
  const cardsByColumn: Record<KanbanColumnType, KanbanCard[]> = {
    BACKLOG: [],
    PLANNING: [],
    RUNNING: [],
    REVIEW: [],
    DONE: [],
  };
  for (const card of boardState.cards) {
    cardsByColumn[card.column].push(card);
  }

  const selectedCard =
    selectedFeature
      ? boardState.cards.find((c) => c.feature === selectedFeature) ?? null
      : null;

  // -- Render ---------------------------------------------------------------
  return (
    <motion.div
      initial={{ opacity: 0, y: 6 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.2 }}
      className="flex gap-4 h-full"
      data-testid="kanban-board-view"
    >
      {/* Columns */}
      <div className="flex gap-4 flex-1 overflow-x-auto pb-4">
        <AnimatePresence mode="popLayout">
          {KANBAN_COLUMNS.map((col) => (
            <motion.div
              key={col}
              layout
              initial={{ opacity: 0, scale: 0.95 }}
              animate={{ opacity: 1, scale: 1 }}
              exit={{ opacity: 0, scale: 0.95 }}
              transition={{ duration: 0.2 }}
            >
              <KanbanColumn
                title={col}
                cards={cardsByColumn[col]}
                onCardClick={handleCardClick}
              />
            </motion.div>
          ))}
        </AnimatePresence>
      </div>

      {/* Flag Panel — visible on xl+ screens */}
      <div className="hidden xl:flex w-[320px] shrink-0 border-l">
        <FlagPanel
          flags={boardState.flags}
          onAction={handleFlagAction}
          isLoading={false}
        />
      </div>

      {/* Card detail dialog */}
      <KanbanCardDetail
        card={selectedCard}
        open={detailOpen}
        onOpenChange={setDetailOpen}
      />
    </motion.div>
  );
}

export default KanbanBoard;
