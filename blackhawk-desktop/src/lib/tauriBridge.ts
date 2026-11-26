import { invoke } from '@tauri-apps/api/core';
import { listen, type UnlistenFn } from '@tauri-apps/api/event';
import type {
  ChatMessage, BoardState, Alert, BlackHawkSettings,
  BoardUpdateEvent, AlertUpdateEvent, ChatResponseEvent, TrayUpdateEvent,
} from './types';

// ---- Invoke wrappers (call Rust commands) ----

export async function sendChat(message: string): Promise<ChatMessage> {
  return invoke<ChatMessage>('send_chat', { message });
}

export async function runTriage(): Promise<string> {
  return invoke<string>('run_triage');
}

export async function promoteCard(cardId: string): Promise<string> {
  return invoke<string>('promote_card', { cardId });
}

export async function executeAction(command: string): Promise<string> {
  return invoke<string>('execute_action', { command });
}

export async function getBoardState(): Promise<BoardState> {
  return invoke<BoardState>('get_board_state');
}

export async function getAlerts(): Promise<Alert[]> {
  return invoke<Alert[]>('get_alerts');
}

export async function getSettings(): Promise<BlackHawkSettings> {
  return invoke<BlackHawkSettings>('get_settings');
}

export async function updateSettings(settings: Partial<BlackHawkSettings>): Promise<void> {
  return invoke<void>('update_settings', { settings });
}

export async function getChatHistory(date?: string): Promise<ChatMessage[]> {
  return invoke<ChatMessage[]>('get_chat_history', { date: date ?? null });
}

export async function setSilentMode(enabled: boolean): Promise<void> {
  return invoke<void>('set_silent_mode', { enabled });
}

// ---- Event listeners (Rust -> Frontend) ----

export function onBoardUpdate(callback: (event: BoardUpdateEvent) => void): Promise<UnlistenFn> {
  return listen<BoardUpdateEvent>('board-update', (e) => callback(e.payload));
}

export function onAlertUpdate(callback: (event: AlertUpdateEvent) => void): Promise<UnlistenFn> {
  return listen<AlertUpdateEvent>('alert-update', (e) => callback(e.payload));
}

export function onChatResponse(callback: (event: ChatResponseEvent) => void): Promise<UnlistenFn> {
  return listen<ChatResponseEvent>('chat-response', (e) => callback(e.payload));
}

export function onTrayUpdate(callback: (event: TrayUpdateEvent) => void): Promise<UnlistenFn> {
  return listen<TrayUpdateEvent>('tray-update', (e) => callback(e.payload));
}
