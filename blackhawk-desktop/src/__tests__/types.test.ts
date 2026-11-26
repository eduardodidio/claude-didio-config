import { describe, expect, it } from 'vitest';
import type {
  ChatMessage,
  Alert,
  BoardCard,
  BlackHawkSettings,
  TrayState,
} from '../lib/types';

describe('F32 TypeScript types', () => {
  it('ChatMessage shape is valid', () => {
    const msg: ChatMessage = {
      id: 'test-001',
      role: 'alpha',
      content: 'Hello',
      actions: [{ label: 'Go', command: 'run', confirmed: false }],
      timestamp: '2026-11-26T00:00:00Z',
    };
    expect(msg.role).toBe('alpha');
    expect(msg.actions).toHaveLength(1);
  });

  it('Alert shape is valid', () => {
    const alert: Alert = {
      id: 'a-001',
      feature: 'F32',
      task: null,
      severity: 'critical',
      status: 'active',
      message: 'test',
      created_at: '2026-11-26T00:00:00Z',
      resolved_at: null,
    };
    expect(alert.severity).toBe('critical');
  });

  it('BoardCard shape is valid', () => {
    const card: BoardCard = {
      feature: 'F32-blackhawk-desktop',
      column: 'RUNNING',
      progress: 60,
      taskTotal: 14,
      taskDone: 8,
      hasBlockage: false,
      currentPhase: 'developer',
    };
    expect(card.column).toBe('RUNNING');
  });

  it('BlackHawkSettings shape is valid', () => {
    const settings: BlackHawkSettings = {
      silentMode: false,
      autoLaunch: true,
      notificationSound: true,
      avatarPath: '',
      chatHistoryDays: 30,
      triageIntervalMinutes: 15,
      desktopWidth: 400,
      desktopHeight: 600,
      desktopPosition: 'bottom-right',
    };
    expect(settings.desktopPosition).toBe('bottom-right');
  });

  it('TrayState shape is valid', () => {
    const state: TrayState = {
      status: 'nominal',
      tooltip: 'All clear',
      alertCount: 0,
    };
    expect(state.status).toBe('nominal');
  });
});
