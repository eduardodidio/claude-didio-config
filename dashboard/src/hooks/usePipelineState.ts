import { useQuery } from '@tanstack/react-query';
import { fetchPipelineState } from '@/lib/fetchKanban';

export function usePipelineState() {
  return useQuery({
    queryKey: ['kanban-pipeline'],
    queryFn: fetchPipelineState,
    refetchInterval: 2000,
    refetchIntervalInBackground: true,
    staleTime: 1000,
  });
}
