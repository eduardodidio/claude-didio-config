import { useQuery } from '@tanstack/react-query';
import { fetchState } from '@/lib/fetchState';

export function useDidioState() {
  return useQuery({
    queryKey: ['didio-state'],
    queryFn: fetchState,
    refetchInterval: 1000,
    refetchIntervalInBackground: true,
    staleTime: 500,
  });
}
