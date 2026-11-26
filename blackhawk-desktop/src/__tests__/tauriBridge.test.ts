import { describe, expect, it, vi, beforeEach, type Mock } from 'vitest';
import { listen } from '@tauri-apps/api/event';
import { onChatExternalUpdate } from '../lib/tauriBridge';

const mockListen = listen as Mock;

describe('tauriBridge — onChatExternalUpdate', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('exports onChatExternalUpdate as a function', () => {
    expect(typeof onChatExternalUpdate).toBe('function');
  });

  it('registers a listener on the chat-external-update event', async () => {
    const unlistenFn = vi.fn();
    mockListen.mockResolvedValueOnce(unlistenFn);

    const callback = vi.fn();
    await onChatExternalUpdate(callback);

    expect(mockListen).toHaveBeenCalledWith('chat-external-update', expect.any(Function));
  });

  it('calls the callback when the event fires', async () => {
    let capturedHandler: (event: { payload: unknown }) => void = () => {};
    mockListen.mockImplementation((_event: string, handler: (event: { payload: unknown }) => void) => {
      capturedHandler = handler;
      return Promise.resolve(vi.fn());
    });

    const callback = vi.fn();
    await onChatExternalUpdate(callback);

    // Simulate the event firing
    capturedHandler({ payload: undefined });

    expect(callback).toHaveBeenCalledTimes(1);
  });

  it('returns an unlisten function that works', async () => {
    const unlistenFn = vi.fn();
    mockListen.mockResolvedValueOnce(unlistenFn);

    const callback = vi.fn();
    const unlisten = await onChatExternalUpdate(callback);

    unlisten();

    expect(unlistenFn).toHaveBeenCalledTimes(1);
  });

  it('does not pass payload to callback (void event)', async () => {
    let capturedHandler: (event: { payload: unknown }) => void = () => {};
    mockListen.mockImplementation((_event: string, handler: (event: { payload: unknown }) => void) => {
      capturedHandler = handler;
      return Promise.resolve(vi.fn());
    });

    const callback = vi.fn();
    await onChatExternalUpdate(callback);

    capturedHandler({ payload: 'some-data' });

    // callback is called with no arguments (the bridge strips payload)
    expect(callback).toHaveBeenCalledWith();
  });
});
