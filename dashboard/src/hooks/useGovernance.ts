import { useMemo } from 'react';
import { useDidioState } from './useDidioState';
import { useFlags } from './useFlags';
import { usePipelineState } from './usePipelineState';
import { useMetaMetrics } from './useMetaMetrics';
import {
  derivePipelineTable,
  deriveTokenBudget,
  deriveFlagAnalytics,
  type PipelineRow,
  type TokenBudgetSummary,
  type FlagAnalytics,
} from '@/lib/governanceHelpers';
import type { MetaMetricsReport } from '@/lib/metaTypes';

export interface GovernanceData {
  pipelines: PipelineRow[];
  tokenBudget: TokenBudgetSummary | null;
  flagAnalytics: FlagAnalytics;
  metaMetrics: MetaMetricsReport | undefined;
  isLoading: boolean;
  isError: boolean;
  error: Error | null;
}

export function useGovernance(): GovernanceData {
  const didioState = useDidioState();
  const flags = useFlags();
  const pipeline = usePipelineState();
  const metaMetrics = useMetaMetrics();

  return useMemo(
    () => ({
      pipelines: derivePipelineTable(didioState.data, pipeline.data, flags.data),
      tokenBudget: deriveTokenBudget(pipeline.data),
      flagAnalytics: deriveFlagAnalytics(flags.data),
      metaMetrics: metaMetrics.data,
      isLoading: didioState.isLoading || flags.isLoading || pipeline.isLoading,
      isError: didioState.isError || flags.isError || pipeline.isError,
      error: (didioState.error ?? flags.error ?? pipeline.error) as Error | null,
    }),
    [
      didioState.data,
      didioState.isLoading,
      didioState.isError,
      didioState.error,
      flags.data,
      flags.isLoading,
      flags.isError,
      flags.error,
      pipeline.data,
      pipeline.isLoading,
      pipeline.isError,
      pipeline.error,
      metaMetrics.data,
    ],
  );
}
