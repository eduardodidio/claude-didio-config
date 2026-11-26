import { useMutation, useQueryClient } from '@tanstack/react-query';
import {
  createWarroomCard,
  updateWarroomCard,
  postWarroomCard,
  fetchWarroomCards,
} from '@/lib/fetchWarroom';
import type { WarRoomCard, CreateCardInput } from '@/lib/warroomTypes';

/**
 * Mutation hook to create a new War Room card.
 * Fetches existing cards to generate a sequential card_id,
 * then posts the new card and invalidates the warroom query cache.
 */
export function useCreateCard() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async (input: CreateCardInput) => {
      const existing = await fetchWarroomCards();
      return createWarroomCard(input, existing);
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['warroom'] });
    },
  });
}

/**
 * Mutation hook to update an existing War Room card.
 * Used for status changes, adding assessments, editing fields, etc.
 */
export function useUpdateCard() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async (card: WarRoomCard) => {
      await updateWarroomCard(card);
      return card;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['warroom'] });
    },
  });
}

/**
 * Mutation hook to request triage of a card.
 * Posts the card with status set to 'triaging' so the Overlord agent picks it up.
 */
export function useTriageCard() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async (card: WarRoomCard) => {
      const triageCard: WarRoomCard = {
        ...card,
        status: 'triaging',
        updated_at: new Date().toISOString(),
      };
      await postWarroomCard(triageCard);
      return triageCard;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['warroom'] });
    },
  });
}
