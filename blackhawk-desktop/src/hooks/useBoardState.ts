import { useCallback, useEffect, useState } from 'react';
import type { BoardState } from '@/lib/types';
import { getBoardState, onBoardUpdate } from '@/lib/tauriBridge';

export function useBoardState() {
  const [board, setBoard] = useState<BoardState>({ cards: [], lastUpdated: '' });
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const refresh = useCallback(async () => {
    setLoading(true);
    try {
      const state = await getBoardState();
      setBoard(state);
      setError(null);
    } catch (e) {
      setError(String(e));
    } finally {
      setLoading(false);
    }
  }, []);

  // Initial load
  useEffect(() => {
    refresh();
  }, [refresh]);

  // Listen for file-watcher board updates
  useEffect(() => {
    const unlisten = onBoardUpdate((event) => {
      setBoard(event.state);
    });
    return () => {
      unlisten.then((fn) => fn());
    };
  }, []);

  return { board, loading, error, refresh };
}
