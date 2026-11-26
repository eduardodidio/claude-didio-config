import { useMemo } from 'react';
import { useDidioState } from './useDidioState';
import { useFlags } from './useFlags';
import { usePipelineState } from './usePipelineState';
import { deriveColumn } from '@/lib/kanbanHelpers';
import type { KanbanBoardState, KanbanCard } from '@/lib/kanbanTypes';
import type { FeatureProgress, AgentRun } from '@/lib/types';

export function useKanbanState() {
  const didioQuery = useDidioState();
  const flagsQuery = useFlags();
  const pipelineQuery = usePipelineState();

  const isLoading =
    didioQuery.isLoading || flagsQuery.isLoading || pipelineQuery.isLoading;
  const isError = didioQuery.isError || flagsQuery.isError;
  // Pipeline may not exist yet -- graceful degradation
  const error = didioQuery.error || flagsQuery.error;

  const boardState = useMemo((): KanbanBoardState | null => {
    if (!didioQuery.data) return null;

    const flags = flagsQuery.data ?? [];
    const features: FeatureProgress[] = didioQuery.data.features ?? [];
    const agents: AgentRun[] = didioQuery.data.agents ?? [];

    const cards: KanbanCard[] = features.map((fp) => {
      const featureFlags = flags.filter(
        (f) => f.feature === fp.feature && !f.resolved_at,
      );
      const isBlocked = featureFlags.some((f) => f.type === 'blocked');

      return {
        feature: fp.feature,
        column: deriveColumn(fp, flags, agents),
        progress: fp.percent,
        taskCount: fp.total,
        completedTasks: fp.completed,
        currentPhase: fp.current_task ? guessPhase(fp, agents) : null,
        currentTask: fp.current_task,
        flags: featureFlags,
        isBlocked,
        priority: 'medium' as const,
      };
    });

    return {
      cards,
      flags,
      generated_at: didioQuery.data.generated_at,
    };
  }, [didioQuery.data, flagsQuery.data, pipelineQuery.data]);

  return { data: boardState, isLoading, isError, error };
}

function guessPhase(fp: FeatureProgress, agents: AgentRun[]): string {
  const running = agents.find(
    (a) => a.feature === fp.feature && a.status === 'running',
  );
  return running?.role ?? 'unknown';
}
