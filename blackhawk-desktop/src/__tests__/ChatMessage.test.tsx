import { render, screen } from '@testing-library/react';
import { describe, expect, it, vi } from 'vitest';
import { ChatMessage } from '../components/ChatMessage';
import type { ChatMessage as ChatMessageType } from '../lib/types';

const operatorMsg: ChatMessageType = {
  id: 'msg-001',
  role: 'operator',
  content: 'Run triage',
  actions: [],
  timestamp: '2026-11-26T12:00:00Z',
};

const alphaMsg: ChatMessageType = {
  id: 'msg-002',
  role: 'alpha',
  content: 'Roger. Ready to run triage.',
  actions: [
    { label: 'Run Triage', command: 'didio blackhawk triage', confirmed: false },
  ],
  timestamp: '2026-11-26T12:00:01Z',
};

describe('ChatMessage', () => {
  it('renders operator message', () => {
    render(<ChatMessage message={operatorMsg} />);
    expect(screen.getByText('Run triage')).toBeInTheDocument();
    expect(screen.getByText('You')).toBeInTheDocument();
  });

  it('renders alpha message with label', () => {
    render(<ChatMessage message={alphaMsg} />);
    expect(screen.getByText('Roger. Ready to run triage.')).toBeInTheDocument();
    expect(screen.getByText('Alpha')).toBeInTheDocument();
  });

  it('renders action buttons on alpha messages', () => {
    const onAction = vi.fn();
    render(<ChatMessage message={alphaMsg} onAction={onAction} />);
    expect(screen.getByText('Run Triage')).toBeInTheDocument();
  });

  it('does not render actions on operator messages', () => {
    render(<ChatMessage message={operatorMsg} />);
    expect(screen.queryByRole('button')).toBeNull();
  });
});
