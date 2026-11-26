import { ActionButton } from '@/components/kanban/ActionButton';
import type { ActionType } from '@/lib/kanbanTypes';

export interface ActionBarProps {
  feature: string;
  task?: string | null;
  actions: ActionType[];
  size?: 'sm' | 'default';
}

export function ActionBar({ feature, task, actions, size = 'sm' }: ActionBarProps) {
  if (actions.length === 0) return null;

  return (
    <div className="flex flex-wrap items-center gap-2">
      {actions.map((action) => (
        <ActionButton
          key={action}
          action={action}
          feature={feature}
          task={task}
          size={size}
        />
      ))}
    </div>
  );
}
