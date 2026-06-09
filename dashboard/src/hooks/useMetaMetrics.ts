import { useQuery } from '@tanstack/react-query';
import { fetchMetaMetrics } from '@/lib/fetchMetaMetrics';

export function useMetaMetrics() {
  return useQuery({
    queryKey: ['didio-meta-metrics'],
    queryFn: fetchMetaMetrics,
    refetchInterval: 2000,
  });
}
