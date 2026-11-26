import { useBlackhawkChat } from '@/hooks/useBlackhawkChat';
import { ChatMessage } from '@/components/ChatMessage';
import { ChatInput } from '@/components/ChatInput';
import { Avatar } from '@/components/Avatar';
import { ScrollArea } from '@/components/ui/scroll-area';
import { executeAction } from '@/lib/tauriBridge';

export function Chat() {
  const { messages, loading, error, send, scrollRef } = useBlackhawkChat();

  const handleAction = async (command: string) => {
    try {
      await executeAction(command);
    } catch (e) {
      console.error('[blackhawk-chat] action failed:', e);
    }
  };

  return (
    <div className="flex flex-col h-full">
      {/* Chat header */}
      <div className="flex items-center gap-2 px-3 py-2">
        <Avatar size="sm" />
        <div>
          <span className="text-xs font-semibold">Black Hawk Alpha</span>
          <span className="text-[10px] text-muted-foreground ml-1.5">Commander</span>
        </div>
        <div className="ml-auto flex items-center gap-1">
          <div className="w-1.5 h-1.5 rounded-full bg-[hsl(var(--status-active))]" />
          <span className="text-[10px] text-muted-foreground">Online</span>
        </div>
      </div>

      {/* Messages */}
      <ScrollArea className="flex-1 px-3" ref={scrollRef}>
        <div className="flex flex-col gap-3 py-3">
          {messages.length === 0 && !loading && (
            <div className="text-center py-8">
              <Avatar size="lg" className="mx-auto mb-3 didio-glow" />
              <p className="text-sm text-muted-foreground">
                Black Hawk Alpha standing by.
              </p>
              <p className="text-xs text-muted-foreground mt-1">
                Try: "triage", "status", "promote WR-..."
              </p>
            </div>
          )}
          {messages.map((msg) => (
            <ChatMessage key={msg.id} message={msg} onAction={handleAction} />
          ))}
          {loading && (
            <div className="self-start flex items-center gap-2 px-3 py-2 bg-secondary rounded-xl rounded-tl-sm">
              <div className="flex gap-1">
                <div className="w-1.5 h-1.5 rounded-full bg-muted-foreground animate-bounce" />
                <div className="w-1.5 h-1.5 rounded-full bg-muted-foreground animate-bounce [animation-delay:150ms]" />
                <div className="w-1.5 h-1.5 rounded-full bg-muted-foreground animate-bounce [animation-delay:300ms]" />
              </div>
            </div>
          )}
        </div>
      </ScrollArea>

      {/* Error display */}
      {error && (
        <div className="px-3 py-1 text-xs text-destructive bg-destructive/10 border-t border-destructive/20">
          {error}
        </div>
      )}

      {/* Input */}
      <ChatInput onSend={send} disabled={loading} />
    </div>
  );
}
