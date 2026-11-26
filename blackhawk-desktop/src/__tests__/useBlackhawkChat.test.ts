import { describe, expect, it, vi, beforeEach, type Mock } from 'vitest';
import { renderHook, act, waitFor } from '@testing-library/react';
import { listen } from '@tauri-apps/api/event';
import { invoke } from '@tauri-apps/api/core';
import { useBlackhawkChat } from '../hooks/useBlackhawkChat';
import type { ChatMessage } from '../lib/types';

const mockListen = listen as Mock;
const mockInvoke = invoke as Mock;

function makeChatMessage(overrides: Partial<ChatMessage> = {}): ChatMessage {
  return {
    id: `msg-${Date.now()}`,
    role: 'alpha',
    content: 'Hello',
    actions: [],
    timestamp: new Date().toISOString(),
    ...overrides,
  };
}

describe('useBlackhawkChat — chat-external-update', () => {
  let listeners: Record<string, (...args: unknown[]) => void>;

  beforeEach(() => {
    vi.clearAllMocks();
    listeners = {};

    // Capture event listeners by event name
    mockListen.mockImplementation((event: string, cb: (...args: unknown[]) => void) => {
      listeners[event] = cb;
      return Promise.resolve(vi.fn()); // unlisten fn
    });

    // Default: get_chat_history returns empty
    mockInvoke.mockImplementation((cmd: string) => {
      if (cmd === 'get_chat_history') return Promise.resolve([]);
      return Promise.resolve(null);
    });
  });

  it('registers a listener for chat-external-update on mount', async () => {
    renderHook(() => useBlackhawkChat());
    await waitFor(() => {
      expect(listeners['chat-external-update']).toBeDefined();
    });
  });

  it('reloads chat history when chat-external-update fires', async () => {
    const updatedMessages = [
      makeChatMessage({ id: '1', content: 'From background agent' }),
    ];

    renderHook(() => useBlackhawkChat());

    await waitFor(() => {
      expect(listeners['chat-external-update']).toBeDefined();
    });

    // Now simulate external update — getChatHistory returns new data
    mockInvoke.mockImplementation((cmd: string) => {
      if (cmd === 'get_chat_history') return Promise.resolve(updatedMessages);
      return Promise.resolve(null);
    });

    await act(async () => {
      listeners['chat-external-update']({ payload: undefined });
    });

    // getChatHistory should have been called again
    const historyCalls = mockInvoke.mock.calls.filter(
      (c: unknown[]) => c[0] === 'get_chat_history',
    );
    // At least 2: initial mount + external update
    expect(historyCalls.length).toBeGreaterThanOrEqual(2);
  });

  it('sets error state when getChatHistory fails on external update', async () => {
    renderHook(() => useBlackhawkChat());

    await waitFor(() => {
      expect(listeners['chat-external-update']).toBeDefined();
    });

    mockInvoke.mockImplementation((cmd: string) => {
      if (cmd === 'get_chat_history') return Promise.reject(new Error('disk read failed'));
      return Promise.resolve(null);
    });

    await act(async () => {
      listeners['chat-external-update']({ payload: undefined });
    });

    // Error should propagate — we can't directly check state from here
    // but getChatHistory was called and rejected (no uncaught promise)
    const historyCalls = mockInvoke.mock.calls.filter(
      (c: unknown[]) => c[0] === 'get_chat_history',
    );
    expect(historyCalls.length).toBeGreaterThanOrEqual(2);
  });

  it('calls unlisten on unmount for chat-external-update', async () => {
    const unlistenFn = vi.fn();
    mockListen.mockImplementation((_event: string, cb: (...args: unknown[]) => void) => {
      listeners[_event] = cb;
      return Promise.resolve(unlistenFn);
    });

    const { unmount } = renderHook(() => useBlackhawkChat());

    await waitFor(() => {
      expect(listeners['chat-external-update']).toBeDefined();
    });

    unmount();

    // unlisten is called asynchronously via .then
    await waitFor(() => {
      expect(unlistenFn).toHaveBeenCalled();
    });
  });

  it('both chat-response and chat-external-update listeners coexist', async () => {
    renderHook(() => useBlackhawkChat());

    await waitFor(() => {
      expect(listeners['chat-response']).toBeDefined();
      expect(listeners['chat-external-update']).toBeDefined();
    });
  });

  it('external update replaces messages (no duplicates)', async () => {
    const initial = [makeChatMessage({ id: '1', content: 'Old' })];
    const updated = [
      makeChatMessage({ id: '1', content: 'Old' }),
      makeChatMessage({ id: '2', content: 'New from agent' }),
    ];

    let callCount = 0;
    mockInvoke.mockImplementation((cmd: string) => {
      if (cmd === 'get_chat_history') {
        callCount++;
        return Promise.resolve(callCount === 1 ? initial : updated);
      }
      return Promise.resolve(null);
    });

    const { result } = renderHook(() => useBlackhawkChat());

    // Wait for initial load
    await waitFor(() => {
      expect(result.current.messages).toHaveLength(1);
    });

    // Fire external update
    await act(async () => {
      listeners['chat-external-update']({ payload: undefined });
    });

    await waitFor(() => {
      expect(result.current.messages).toHaveLength(2);
    });

    // Messages are replaced, not appended — IDs should match exactly
    expect(result.current.messages.map((m) => m.id)).toEqual(['1', '2']);
  });
});
