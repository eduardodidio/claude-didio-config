import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, it, vi } from 'vitest';
import { ActionSuggestion } from '../components/ActionSuggestion';

const action = {
  label: 'Run Triage',
  command: 'didio blackhawk triage',
  confirmed: false,
};

describe('ActionSuggestion', () => {
  it('renders action label', () => {
    render(<ActionSuggestion action={action} onExecute={() => {}} />);
    expect(screen.getByText('Run Triage')).toBeInTheDocument();
  });

  it('calls onExecute when clicked', async () => {
    const onExecute = vi.fn();
    render(<ActionSuggestion action={action} onExecute={onExecute} />);
    await userEvent.click(screen.getByText('Run Triage'));
    expect(onExecute).toHaveBeenCalledOnce();
  });

  it('disables button after click', async () => {
    render(<ActionSuggestion action={action} onExecute={() => {}} />);
    const btn = screen.getByRole('button');
    await userEvent.click(btn);
    expect(btn).toBeDisabled();
  });

  it('renders as confirmed when action.confirmed is true', () => {
    render(<ActionSuggestion action={{ ...action, confirmed: true }} onExecute={() => {}} />);
    expect(screen.getByRole('button')).toBeDisabled();
  });
});
