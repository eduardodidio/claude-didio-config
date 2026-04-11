import { useEffect, useState } from 'react';
import { useDidioState } from '@/hooks/useDidioState';
import { cn } from '@/lib/utils';

export function ConnectionFooter() {
  const { isSuccess, isFetching, isError, dataUpdatedAt, error } = useDidioState();
  const [, setTick] = useState(0);

  useEffect(() => {
    const id = setInterval(() => setTick((t) => t + 1), 1000);
    return () => clearInterval(id);
  }, []);

  const ago =
    dataUpdatedAt === 0
      ? '—'
      : Math.max(0, Math.floor((Date.now() - dataUpdatedAt) / 1000)).toString();

  const dotClass = isError
    ? 'bg-red-500'
    : isFetching
      ? 'bg-amber-500'
      : isSuccess
        ? 'bg-green-500'
        : 'bg-muted-foreground';

  const title = isError
    ? error instanceof Error
      ? error.message
      : 'error'
    : undefined;

  return (
    <footer
      title={title}
      className="flex items-center gap-2 px-4 py-2 text-xs text-muted-foreground border-t border-border"
    >
      <span
        className={cn('inline-block h-2 w-2 rounded-full', dotClass)}
        aria-hidden="true"
      />
      <span>
        watching state.json · last refresh {ago}s ago
      </span>
      <span className="ml-auto font-mono">
        © 2026 Eduardo Rutkoski Didio
      </span>
    </footer>
  );
}

export default ConnectionFooter;
