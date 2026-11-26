import { useMutation, useQueryClient } from '@tanstack/react-query';
import type { ActionType, OperatorAction } from '@/lib/kanbanTypes';

function generateUUID(): string {
  return crypto.randomUUID();
}

async function postAction(action: OperatorAction): Promise<{ ok: boolean }> {
  const res = await fetch('./api/actions', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(action),
  });
  if (!res.ok) throw new Error(`Failed to post action: ${res.status}`);
  return res.json();
}

export function useActions() {
  const queryClient = useQueryClient();

  const mutation = useMutation({
    mutationFn: postAction,
    onSuccess: () => {
      // Invalidate flags and kanban state to trigger re-fetch
      queryClient.invalidateQueries({ queryKey: ['kanban-flags'] });
      queryClient.invalidateQueries({ queryKey: ['kanban-state'] });
    },
  });

  function dispatch(
    action: ActionType,
    feature: string,
    task?: string | null,
    params?: Record<string, unknown>,
  ) {
    const payload: OperatorAction = {
      action_id: generateUUID(),
      action,
      feature,
      task: task ?? null,
      operator: 'user',
      timestamp: new Date().toISOString(),
      params: params ?? {},
    };
    return mutation.mutateAsync(payload);
  }

  return {
    dispatch,
    isPending: mutation.isPending,
    isError: mutation.isError,
    error: mutation.error,
    lastAction: mutation.data,
  };
}
