import { useQuery } from '@tanstack/react-query';
import { fetchFlags } from '@/lib/fetchKanban';

export function useFlags() {
  return useQuery({
    queryKey: ['kanban-flags'],
    queryFn: fetchFlags,
    refetchInterval: 2000,
    refetchIntervalInBackground: true,
    staleTime: 1000,
  });
}
