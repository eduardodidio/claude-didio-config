// ---------------------------------------------------------------------------
// F31-T08 — WarRoom view
// Assembles warroom columns + triage panel + card creation form.
// ---------------------------------------------------------------------------

import { useState, useCallback, useEffect } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import { Plus, Swords } from 'lucide-react';
import { useWarroomState } from '@/hooks/useWarroomState';
import { useCreateCard } from '@/hooks/useWarroomActions';
import {
  WarroomColumn,
  CardCreateForm,
  TriagePanel,
} from '@/components/warroom';
import { Skeleton } from '@/components/ui/skeleton';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { WARROOM_COLUMNS } from '@/lib/warroomTypes';
import type { CreateCardInput } from '@/lib/warroomTypes';

// ---------------------------------------------------------------------------
// Loading skeleton
// ---------------------------------------------------------------------------

function WarRoomSkeleton() {
  return (
    <div data-testid="warroom-skeleton" className="space-y-6">
      {/* Header skeleton */}
      <div className="space-y-2">
        <Skeleton className="h-8 w-48" />
        <Skeleton className="h-4 w-64" />
      </div>
      {/* Columns skeleton */}
      <div className="flex gap-4 overflow-x-auto pb-4">
        {WARROOM_COLUMNS.map((col) => (
          <div key={col} className="min-w-[280px] w-[280px] space-y-3">
            <Skeleton className="h-8 w-full rounded-lg" />
            <Skeleton className="h-24 w-full rounded-lg" />
            <Skeleton className="h-24 w-full rounded-lg" />
          </div>
        ))}
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// WarRoom
// ---------------------------------------------------------------------------

export function WarRoom() {
  const { data: boardState, isLoading, isError, error, refetch } = useWarroomState();
  const createCard = useCreateCard();

  const [selectedCardId, setSelectedCardId] = useState<string | null>(null);
  const [showCreateForm, setShowCreateForm] = useState(false);

  // Set page title
  useEffect(() => {
    document.title = 'War Room | Dashboard';
    return () => {
      document.title = 'Dashboard';
    };
  }, []);

  // Derived
  const selectedCard =
    selectedCardId && boardState
      ? boardState.cards.find((c) => c.card_id === selectedCardId) ?? null
      : null;

  const incomingCount = boardState?.incoming_count ?? 0;

  // Handlers
  const handleCardSelect = useCallback((cardId: string) => {
    setSelectedCardId(cardId);
  }, []);

  const handleTriagePanelClose = useCallback(() => {
    setSelectedCardId(null);
  }, []);

  const handleCreateSubmit = useCallback(
    (input: CreateCardInput) => {
      createCard.mutate(input, {
        onSuccess: () => {
          setShowCreateForm(false);
        },
      });
    },
    [createCard],
  );

  const handleCreateCancel = useCallback(() => {
    setShowCreateForm(false);
  }, []);

  // -- Loading state --------------------------------------------------------
  if (isLoading) return <WarRoomSkeleton />;

  // -- Error state ----------------------------------------------------------
  if (isError || !boardState) {
    return (
      <div
        role="alert"
        data-testid="warroom-error"
        className="rounded-md border border-red-500/40 bg-red-500/10 p-6 text-red-600 space-y-3"
      >
        <p className="font-semibold">Failed to load War Room</p>
        <p className="text-sm">
          {error instanceof Error ? error.message : 'An unexpected error occurred.'}
        </p>
        <Button
          variant="outline"
          size="sm"
          onClick={() => refetch()}
          data-testid="warroom-retry"
        >
          Retry
        </Button>
      </div>
    );
  }

  // -- Empty state ----------------------------------------------------------
  if (boardState.cards.length === 0 && !showCreateForm) {
    return (
      <motion.div
        initial={{ opacity: 0, y: 6 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.2 }}
        data-testid="warroom-empty"
        className="space-y-6"
      >
        {/* Header */}
        <div className="flex items-center justify-between">
          <div>
            <h1 className="text-2xl font-bold tracking-tight">War Room</h1>
            <p className="text-sm text-muted-foreground">Strategic triage space</p>
          </div>
          <Button
            size="sm"
            onClick={() => setShowCreateForm(true)}
            data-testid="warroom-add-card"
          >
            <Plus className="h-4 w-4 mr-1" />
            Add Card
          </Button>
        </div>

        {/* Empty illustration */}
        <div className="flex flex-col items-center justify-center py-20 text-center space-y-3">
          <Swords className="h-10 w-10 text-muted-foreground" />
          <p className="text-sm text-muted-foreground">
            No cards in the War Room. Add a card to begin triage.
          </p>
        </div>
      </motion.div>
    );
  }

  // -- Main render ----------------------------------------------------------
  return (
    <motion.div
      initial={{ opacity: 0, y: 6 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.2 }}
      data-testid="warroom-view"
      className="flex flex-col h-full space-y-4"
    >
      {/* Header */}
      <div className="flex items-center justify-between shrink-0">
        <div className="flex items-center gap-3">
          <div>
            <h1 className="text-2xl font-bold tracking-tight">War Room</h1>
            <p className="text-sm text-muted-foreground">Strategic triage space</p>
          </div>
          {incomingCount > 0 && (
            <Badge
              variant="secondary"
              className="bg-blue-100 text-blue-700 dark:bg-blue-900 dark:text-blue-300"
              data-testid="warroom-incoming-badge"
            >
              {incomingCount} incoming
            </Badge>
          )}
        </div>
        <Button
          size="sm"
          onClick={() => setShowCreateForm(!showCreateForm)}
          data-testid="warroom-add-card"
        >
          <Plus className="h-4 w-4 mr-1" />
          Add Card
        </Button>
      </div>

      {/* Create form (collapsible above the board) */}
      <AnimatePresence>
        {showCreateForm && (
          <div className="shrink-0">
            <CardCreateForm
              onSubmit={handleCreateSubmit}
              onCancel={handleCreateCancel}
              isSubmitting={createCard.isPending}
            />
          </div>
        )}
      </AnimatePresence>

      {/* Board columns */}
      <div className="flex gap-4 flex-1 overflow-x-auto pb-4">
        <AnimatePresence mode="popLayout">
          {WARROOM_COLUMNS.map((status) => (
            <motion.div
              key={status}
              layout
              initial={{ opacity: 0, scale: 0.95 }}
              animate={{ opacity: 1, scale: 1 }}
              exit={{ opacity: 0, scale: 0.95 }}
              transition={{ duration: 0.2 }}
            >
              <WarroomColumn
                status={status}
                cards={boardState.columns[status]}
                onCardSelect={handleCardSelect}
              />
            </motion.div>
          ))}
        </AnimatePresence>
      </div>

      {/* Triage panel (slide-in from right via portal) */}
      <TriagePanel card={selectedCard} onClose={handleTriagePanelClose} />
    </motion.div>
  );
}

export default WarRoom;
