import { describe, it, expect } from 'vitest';
import { normalizeEvent } from './eventNormalize';

describe('normalizeEvent (claude)', () => {
  it('maps assistant text to assistant', () => {
    const ev = normalizeEvent({
      type: 'assistant',
      message: { role: 'assistant', content: [{ type: 'text', text: 'hi' }] },
    });
    expect(ev.kind).toBe('assistant');
    expect(ev.isError).toBe(false);
  });

  it('maps a tool_result error to error', () => {
    const ev = normalizeEvent({
      type: 'assistant',
      message: {
        role: 'assistant',
        content: [{ type: 'tool_result', tool_use_id: 't2', is_error: true }],
      },
    });
    expect(ev.kind).toBe('error');
    expect(ev.isError).toBe(true);
  });

  it('maps a successful result event', () => {
    const ev = normalizeEvent({ type: 'result', is_error: false, result: 'done' });
    expect(ev.kind).toBe('result');
    expect(ev.isError).toBe(false);
  });

  it('maps a rate-limited result event', () => {
    const ev = normalizeEvent({
      type: 'result',
      is_error: true,
      result: 'You have hit your limit',
      api_error_status: '429',
    });
    expect(ev.kind).toBe('rate_limit');
  });

  it('maps a real-error result event', () => {
    const ev = normalizeEvent({ type: 'result', is_error: true, result: 'boom' });
    expect(ev.kind).toBe('error');
  });

  it('degrades unknown event types to raw', () => {
    const ev = normalizeEvent({ type: 'system', subtype: 'init' });
    expect(ev.kind).toBe('raw');
  });
});

describe('normalizeEvent (codex)', () => {
  it('maps agent_message to assistant', () => {
    const ev = normalizeEvent({ msg: { type: 'agent_message', message: 'hi' } }, 'codex');
    expect(ev.kind).toBe('assistant');
    expect(ev.text).toBe('hi');
  });

  it('maps error to error', () => {
    const ev = normalizeEvent({ msg: { type: 'error', message: 'boom' } }, 'codex');
    expect(ev.kind).toBe('error');
    expect(ev.isError).toBe(true);
  });

  it('maps a rate-limit error to rate_limit', () => {
    const ev = normalizeEvent(
      { msg: { type: 'error', message: 'hit your usage rate limit (429)' } },
      'codex',
    );
    expect(ev.kind).toBe('rate_limit');
  });

  it('maps exec_command_end exit codes', () => {
    const ok = normalizeEvent({ msg: { type: 'exec_command_end', exit_code: 0 } }, 'codex');
    expect(ok.kind).toBe('tool');
    expect(ok.isError).toBe(false);

    const bad = normalizeEvent({ msg: { type: 'exec_command_end', exit_code: 1 } }, 'codex');
    expect(bad.kind).toBe('error');
    expect(bad.isError).toBe(true);
  });

  it('degrades unsupported event types to raw', () => {
    const ev = normalizeEvent({ msg: { type: 'some_new_event' } }, 'codex');
    expect(ev.kind).toBe('raw');
  });

  it('degrades events without msg to raw', () => {
    const ev = normalizeEvent({ no_msg: true }, 'codex');
    expect(ev.kind).toBe('raw');
  });
});
