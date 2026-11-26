import { useCallback, useEffect, useRef, useState } from 'react';
import type { ChatMessage } from '@/lib/types';
import { getChatHistory, onChatResponse, sendChat } from '@/lib/tauriBridge';

export function useBlackhawkChat() {
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const scrollRef = useRef<HTMLDivElement>(null);

  // Load today's chat history on mount
  useEffect(() => {
    getChatHistory()
      .then(setMessages)
      .catch((e) => setError(String(e)));
  }, []);

  // Listen for chat responses from Rust backend
  useEffect(() => {
    const unlisten = onChatResponse((event) => {
      setMessages((prev) => {
        // Avoid duplicates by checking ID
        if (prev.some((m) => m.id === event.message.id)) return prev;
        return [...prev, event.message];
      });
    });
    return () => {
      unlisten.then((fn) => fn());
    };
  }, []);

  // Auto-scroll to bottom on new messages
  useEffect(() => {
    scrollRef.current?.scrollTo({
      top: scrollRef.current.scrollHeight,
      behavior: 'smooth',
    });
  }, [messages]);

  const send = useCallback(async (text: string) => {
    if (!text.trim()) return;

    setLoading(true);
    setError(null);

    // Optimistic: add operator message immediately
    const optimistic: ChatMessage = {
      id: `temp-${Date.now()}`,
      role: 'operator',
      content: text,
      actions: [],
      timestamp: new Date().toISOString(),
    };
    setMessages((prev) => [...prev, optimistic]);

    try {
      const response = await sendChat(text);
      // Replace optimistic operator msg + add alpha response
      setMessages((prev) => {
        const withoutOptimistic = prev.filter((m) => m.id !== optimistic.id);
        // The backend returns the alpha response; the operator msg was already persisted
        // Re-fetch to get the real operator msg ID
        return [...withoutOptimistic.filter((m) => m.id !== response.id), response];
      });
      // Simpler: just reload history to be in sync
      const history = await getChatHistory();
      setMessages(history);
    } catch (e) {
      setError(String(e));
    } finally {
      setLoading(false);
    }
  }, []);

  return { messages, loading, error, send, scrollRef };
}
