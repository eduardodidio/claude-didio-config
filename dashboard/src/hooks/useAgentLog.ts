import { useEffect, useRef, useState } from 'react';

export interface LogEntry {
  raw: string;
  parsed: Record<string, unknown> | null;
  ts?: string;
  type?: string;
}

interface UseAgentLogResult {
  entries: LogEntry[];
  error: string | null;
  loading: boolean;
}

function parseJsonl(text: string): LogEntry[] {
  return text
    .split('\n')
    .filter((line) => line.trim().length > 0)
    .map((raw) => {
      try {
        const parsed = JSON.parse(raw) as Record<string, unknown>;
        return {
          raw,
          parsed,
          ts: typeof parsed.ts === 'string' ? parsed.ts : undefined,
          type: typeof parsed.type === 'string' ? parsed.type : undefined,
        };
      } catch {
        return { raw, parsed: null };
      }
    });
}

export function useAgentLog(
  task: string | null,
  isRunning: boolean,
): UseAgentLogResult {
  const [entries, setEntries] = useState<LogEntry[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const cancelledRef = useRef(false);

  useEffect(() => {
    if (!task) {
      setEntries([]);
      setError(null);
      setLoading(false);
      return;
    }

    cancelledRef.current = false;
    setLoading(true);
    setError(null);

    const url = `./logs/agents/${encodeURIComponent(task)}.jsonl`;

    const fetchOnce = async () => {
      try {
        const res = await fetch(url, { cache: 'no-store' });
        if (!res.ok) {
          throw new Error(`HTTP ${res.status}`);
        }
        const text = await res.text();
        if (cancelledRef.current) return;
        setEntries(parseJsonl(text));
        setError(null);
      } catch (e) {
        if (cancelledRef.current) return;
        setError(e instanceof Error ? e.message : String(e));
      } finally {
        if (!cancelledRef.current) setLoading(false);
      }
    };

    fetchOnce();

    let intervalId: ReturnType<typeof setInterval> | null = null;
    if (isRunning) {
      intervalId = setInterval(fetchOnce, 1000);
    }

    return () => {
      cancelledRef.current = true;
      if (intervalId) clearInterval(intervalId);
    };
  }, [task, isRunning]);

  return { entries, error, loading };
}
