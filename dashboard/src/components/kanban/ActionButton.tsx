import React, { useState, useCallback } from 'react';
import {
  LockOpen,
  Check,
  SkipForward,
  Pause,
  Play,
  X,
  Loader2,
} from 'lucide-react';
import { Button } from '@/components/ui/button';
import { useActions } from '@/hooks/useActions';
import type { ActionType } from '@/lib/kanbanTypes';
import { cn } from '@/lib/utils';

const ACTION_ICONS: Record<ActionType, React.ElementType> = {
  unblock: LockOpen,
  approve: Check,
  skip: SkipForward,
  pause: Pause,
  resume: Play,
  cancel: X,
};

const ACTION_LABELS: Record<ActionType, string> = {
  unblock: 'Unblock',
  approve: 'Approve',
  skip: 'Skip',
  pause: 'Pause',
  resume: 'Resume',
  cancel: 'Cancel',
};

const DESTRUCTIVE_ACTIONS: Set<ActionType> = new Set(['cancel', 'skip']);

export interface ActionButtonProps {
  action: ActionType;
  feature: string;
  task?: string | null;
  label?: string;
  variant?: 'default' | 'outline' | 'destructive' | 'ghost';
  size?: 'sm' | 'default';
  disabled?: boolean;
  onDispatched?: () => void;
}

export function ActionButton({
  action,
  feature,
  task,
  label,
  variant,
  size = 'sm',
  disabled = false,
  onDispatched,
}: ActionButtonProps) {
  const { dispatch } = useActions();
  const [pending, setPending] = useState(false);
  const [flash, setFlash] = useState<'success' | 'error' | null>(null);

  const Icon = ACTION_ICONS[action];
  const displayLabel = label ?? ACTION_LABELS[action];

  const resolvedVariant =
    variant ?? (DESTRUCTIVE_ACTIONS.has(action) ? 'destructive' : 'outline');

  const handleClick = useCallback(async () => {
    // Confirmation for destructive actions
    if (DESTRUCTIVE_ACTIONS.has(action)) {
      const target = task ? `${feature}/${task}` : feature;
      const confirmed = window.confirm(
        `Are you sure you want to ${action} ${target}?`,
      );
      if (!confirmed) return;
    }

    setPending(true);
    setFlash(null);

    try {
      await dispatch(action, feature, task);
      setFlash('success');
      onDispatched?.();
      // Clear success flash after a short delay
      setTimeout(() => setFlash(null), 1200);
    } catch {
      setFlash('error');
      setTimeout(() => setFlash(null), 2000);
    } finally {
      setPending(false);
    }
  }, [action, feature, task, dispatch, onDispatched]);

  return (
    <Button
      variant={resolvedVariant}
      size={size}
      disabled={disabled || pending}
      onClick={handleClick}
      className={cn(
        'transition-all duration-200',
        flash === 'success' && 'ring-2 ring-green-500 ring-offset-1',
        flash === 'error' && 'ring-2 ring-red-500 ring-offset-1',
      )}
    >
      {pending ? (
        <Loader2 className="animate-spin" />
      ) : (
        <Icon />
      )}
      {displayLabel}
    </Button>
  );
}
