import { useQuery } from '@tanstack/react-query';
import { fetchWarroomCards, buildBoardState } from '@/lib/fetchWarroom';
import type { WarRoomBoardState } from '@/lib/warroomTypes';

export function useWarroomState(options?: { refetchInterval?: number }) {
  return useQuery<WarRoomBoardState>({
    queryKey: ['warroom', 'cards'],
    queryFn: async () => {
      const cards = await fetchWarroomCards();
      return buildBoardState(cards);
    },
    refetchInterval: options?.refetchInterval ?? 3000,
    refetchIntervalInBackground: true,
    staleTime: 1500,
  });
}
