// Per-provider JSONL event normalization (F01-T11).
//
// TS mirror of bin/didio-events-lib.py's mapping table, used by
// AgentRunDialog to color/label raw JSONL lines for both providers.
// Keep the `kind` mapping table identical between the two implementations.

export type EventKind =
  | 'assistant'
  | 'tool'
  | 'result'
  | 'error'
  | 'rate_limit'
  | 'usage'
  | 'raw';

export type EventProvider = 'claude' | 'codex' | string;

export interface NormalizedEvent {
  kind: EventKind;
  isError: boolean;
  text?: string;
}

function hasToolError(parsed: Record<string, unknown>): boolean {
  const message = parsed.message as Record<string, unknown> | undefined;
  const content = message?.content;
  if (!Array.isArray(content)) return false;
  return content.some(
    (c) =>
      typeof c === 'object' &&
      c !== null &&
      (c as Record<string, unknown>).type === 'tool_result' &&
      Boolean((c as Record<string, unknown>).is_error),
  );
}

function mapClaudeEvent(parsed: Record<string, unknown>): NormalizedEvent {
  const type = parsed.type as string | undefined;
  const toolError = hasToolError(parsed);

  if (type === 'result') {
    const isError = Boolean(parsed.is_error);
    const resultText = String(parsed.result ?? '');
    const apiStatus = String(parsed.api_error_status ?? '');
    let kind: EventKind = 'result';
    if (isError) {
      kind =
        resultText.includes('hit your limit') ||
        resultText.includes('rate_limit') ||
        apiStatus === '429'
          ? 'rate_limit'
          : 'error';
    }
    return { kind, isError, text: resultText };
  }

  if (type === 'assistant') {
    return { kind: toolError ? 'error' : 'assistant', isError: toolError };
  }

  if (type === 'usage') {
    return { kind: 'usage', isError: false };
  }

  return { kind: 'raw', isError: toolError };
}

function mapCodexEvent(parsed: Record<string, unknown>): NormalizedEvent {
  const msg = parsed.msg as Record<string, unknown> | undefined;
  if (!msg || typeof msg !== 'object') {
    return { kind: 'raw', isError: false };
  }

  const mtype = msg.type as string | undefined;

  if (mtype === 'agent_message') {
    return { kind: 'assistant', isError: false, text: String(msg.message ?? '') };
  }

  if (mtype === 'error') {
    const text = String(msg.message ?? '');
    const isRateLimit = text.toLowerCase().includes('rate limit') || text.includes('429');
    return { kind: isRateLimit ? 'rate_limit' : 'error', isError: true, text };
  }

  if (mtype === 'exec_command_end') {
    const exitCode = msg.exit_code;
    const isError = Boolean(exitCode);
    return { kind: isError ? 'error' : 'tool', isError };
  }

  if (mtype === 'token_count') {
    return { kind: 'usage', isError: false };
  }

  if (mtype === 'task_complete') {
    return { kind: 'result', isError: false, text: '' };
  }

  // Unsupported Codex event type — degrade to "raw" (AC4).
  return { kind: 'raw', isError: false };
}

export function normalizeEvent(
  parsed: Record<string, unknown>,
  provider: EventProvider = 'claude',
): NormalizedEvent {
  if (provider === 'codex') return mapCodexEvent(parsed);
  return mapClaudeEvent(parsed);
}
