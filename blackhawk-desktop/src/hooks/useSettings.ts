import { useCallback, useEffect, useState } from 'react';
import type { BlackHawkSettings } from '@/lib/types';
import { getSettings, updateSettings as updateSettingsBridge, setSilentMode } from '@/lib/tauriBridge';

const DEFAULT_SETTINGS: BlackHawkSettings = {
  silentMode: false,
  autoLaunch: false,
  notificationSound: true,
  avatarPath: '',
  chatHistoryDays: 30,
  triageIntervalMinutes: 15,
  desktopWidth: 400,
  desktopHeight: 600,
  desktopPosition: 'bottom-right',
};

export function useSettings() {
  const [settings, setSettings] = useState<BlackHawkSettings>(DEFAULT_SETTINGS);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    getSettings()
      .then((s) => {
        setSettings(s);
        setLoading(false);
      })
      .catch((e) => {
        setError(String(e));
        setLoading(false);
      });
  }, []);

  const update = useCallback(async (partial: Partial<BlackHawkSettings>) => {
    try {
      await updateSettingsBridge(partial);
      setSettings((prev) => ({ ...prev, ...partial }));
      setError(null);
    } catch (e) {
      setError(String(e));
    }
  }, []);

  const toggleSilent = useCallback(async () => {
    const newVal = !settings.silentMode;
    try {
      await setSilentMode(newVal);
      setSettings((prev) => ({ ...prev, silentMode: newVal }));
    } catch (e) {
      setError(String(e));
    }
  }, [settings.silentMode]);

  return { settings, loading, error, update, toggleSilent };
}
