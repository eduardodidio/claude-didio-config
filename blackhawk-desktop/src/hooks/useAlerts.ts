import { useCallback, useEffect, useState } from 'react';
import type { Alert } from '@/lib/types';
import { getAlerts, onAlertUpdate } from '@/lib/tauriBridge';

export function useAlerts() {
  const [alerts, setAlerts] = useState<Alert[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const refresh = useCallback(async () => {
    setLoading(true);
    try {
      const data = await getAlerts();
      setAlerts(data);
      setError(null);
    } catch (e) {
      setError(String(e));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    refresh();
  }, [refresh]);

  useEffect(() => {
    const unlisten = onAlertUpdate((event) => {
      setAlerts(event.alerts);
    });
    return () => {
      unlisten.then((fn) => fn());
    };
  }, []);

  const activeAlerts = alerts.filter((a) => a.status === 'active');
  const resolvedAlerts = alerts.filter((a) => a.status === 'resolved');

  return { alerts, activeAlerts, resolvedAlerts, loading, error, refresh };
}
