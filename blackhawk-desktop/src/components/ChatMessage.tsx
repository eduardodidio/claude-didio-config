import type { ChatMessage as ChatMessageType } from '@/lib/types';
import { cn } from '@/lib/utils';
import { ActionSuggestion } from './ActionSuggestion';

interface Props {
  message: ChatMessageType;
  onAction?: (command: string) => void;
}

export function ChatMessage({ message, onAction }: Props) {
  const isAlpha = message.role === 'alpha';
  const time = new Date(message.timestamp).toLocaleTimeString([], {
    hour: '2-digit',
    minute: '2-digit',
  });

  return (
    <div className={cn('flex flex-col gap-1 max-w-[85%]', isAlpha ? 'self-start' : 'self-end')}>
      <div className="flex items-center gap-1.5 px-1">
        <span className="text-[10px] font-medium text-muted-foreground uppercase tracking-wider">
          {isAlpha ? 'Alpha' : 'You'}
        </span>
        <span className="text-[10px] text-muted-foreground">{time}</span>
      </div>
      <div
        className={cn(
          'rounded-xl px-3 py-2 text-sm leading-relaxed',
          isAlpha
            ? 'bg-secondary text-secondary-foreground rounded-tl-sm'
            : 'bg-primary text-primary-foreground rounded-tr-sm'
        )}
      >
        {message.content}
      </div>
      {isAlpha && message.actions.length > 0 && (
        <div className="flex flex-wrap gap-1 px-1">
          {message.actions.map((action, i) => (
            <ActionSuggestion
              key={i}
              action={action}
              onExecute={() => onAction?.(action.command)}
            />
          ))}
        </div>
      )}
    </div>
  );
}
