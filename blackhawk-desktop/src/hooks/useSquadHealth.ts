import { useCallback, useEffect, useState } from 'react';
import type { SquadReport } from '@/lib/types';
import { getSquadReport, triggerSquadScan } from '@/lib/tauriBridge';

export function useSquadHealth(pollInterval = 10000) {
  const [report, setReport] = useState<SquadReport | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [scanning, setScanning] = useState(false);

  const refresh = useCallback(async () => {
    try {
      const r = await getSquadReport();
      setReport(r);
      setError(null);
    } catch (e) {
      setError(String(e));
    } finally {
      setLoading(false);
    }
  }, []);

  const scan = useCallback(async () => {
    setScanning(true);
    try {
      await triggerSquadScan();
      // Wait a beat for the report to be written, then refresh
      setTimeout(() => {
        refresh();
        setScanning(false);
      }, 2000);
    } catch (e) {
      setError(String(e));
      setScanning(false);
    }
  }, [refresh]);

  // Initial load
  useEffect(() => {
    refresh();
  }, [refresh]);

  // Polling
  useEffect(() => {
    const interval = setInterval(refresh, pollInterval);
    return () => clearInterval(interval);
  }, [refresh, pollInterval]);

  return { report, loading, error, scanning, refresh, scan };
}
