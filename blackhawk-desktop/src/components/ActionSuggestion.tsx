import { Play, Check } from 'lucide-react';
import { useState } from 'react';
import type { ChatAction } from '@/lib/types';
import { Button } from '@/components/ui/button';

interface Props {
  action: ChatAction;
  onExecute: () => void;
}

export function ActionSuggestion({ action, onExecute }: Props) {
  const [executed, setExecuted] = useState(action.confirmed);

  const handleClick = () => {
    if (executed) return;
    setExecuted(true);
    onExecute();
  };

  return (
    <Button
      variant={executed ? 'secondary' : 'outline'}
      size="sm"
      onClick={handleClick}
      disabled={executed}
      className="h-7 text-xs gap-1"
    >
      {executed ? <Check className="h-3 w-3" /> : <Play className="h-3 w-3" />}
      {action.label}
    </Button>
  );
}
