import { describe, it, expect, vi } from 'vitest';
import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { CardCreateForm } from './CardCreateForm';

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe('CardCreateForm', () => {
  it('renders with submit button disabled when title and body are empty', () => {
    render(<CardCreateForm onSubmit={vi.fn()} onCancel={vi.fn()} />);

    const submit = screen.getByTestId('card-create-submit');
    expect(submit).toBeDisabled();
  });

  it('enables submit when title and body are filled', async () => {
    render(<CardCreateForm onSubmit={vi.fn()} onCancel={vi.fn()} />);
    const user = userEvent.setup();

    await user.type(screen.getByTestId('card-title-input'), 'My title');
    await user.type(screen.getByTestId('card-body-input'), 'My body text');

    expect(screen.getByTestId('card-create-submit')).not.toBeDisabled();
  });

  it('fires onSubmit with correct CreateCardInput on submit', async () => {
    const onSubmit = vi.fn();
    render(<CardCreateForm onSubmit={onSubmit} onCancel={vi.fn()} />);
    const user = userEvent.setup();

    await user.type(screen.getByTestId('card-title-input'), 'My title');
    await user.type(screen.getByTestId('card-body-input'), 'My body text');
    await user.click(screen.getByTestId('card-create-submit'));

    expect(onSubmit).toHaveBeenCalledTimes(1);
    const input = onSubmit.mock.calls[0][0];
    expect(input.title).toBe('My title');
    expect(input.body).toBe('My body text');
    expect(input.source).toBe('operator');
    expect(input.priority_suggestion).toBeNull();
    expect(input.tags).toEqual([]);
  });

  it('fires onCancel when cancel button is clicked', async () => {
    const onCancel = vi.fn();
    render(<CardCreateForm onSubmit={vi.fn()} onCancel={onCancel} />);
    const user = userEvent.setup();

    await user.click(screen.getByTestId('card-create-cancel'));

    // onCancel is called after a 200ms timeout
    await waitFor(() => expect(onCancel).toHaveBeenCalledTimes(1), { timeout: 500 });
  });

  it('parses tags from comma-separated string', async () => {
    const onSubmit = vi.fn();
    render(<CardCreateForm onSubmit={onSubmit} onCancel={vi.fn()} />);
    const user = userEvent.setup();

    await user.type(screen.getByTestId('card-title-input'), 'Title');
    await user.type(screen.getByTestId('card-body-input'), 'Body');
    await user.type(screen.getByTestId('card-tags-input'), 'a, b, c');

    // Tag chips should be visible
    expect(screen.getByTestId('card-tags-chips')).toBeInTheDocument();

    await user.click(screen.getByTestId('card-create-submit'));

    const input = onSubmit.mock.calls[0][0];
    expect(input.tags).toEqual(['a', 'b', 'c']);
  });

  it('sets priority_suggestion when priority is selected', async () => {
    const onSubmit = vi.fn();
    render(<CardCreateForm onSubmit={onSubmit} onCancel={vi.fn()} />);
    const user = userEvent.setup();

    await user.type(screen.getByTestId('card-title-input'), 'Title');
    await user.type(screen.getByTestId('card-body-input'), 'Body');
    await user.selectOptions(screen.getByTestId('card-priority-select'), 'high');
    await user.click(screen.getByTestId('card-create-submit'));

    const input = onSubmit.mock.calls[0][0];
    expect(input.priority_suggestion).toBe('high');
  });

  it('resets form after successful submit', async () => {
    const onSubmit = vi.fn();
    render(<CardCreateForm onSubmit={onSubmit} onCancel={vi.fn()} />);
    const user = userEvent.setup();

    await user.type(screen.getByTestId('card-title-input'), 'Title');
    await user.type(screen.getByTestId('card-body-input'), 'Body');
    await user.click(screen.getByTestId('card-create-submit'));

    // After submit, fields should be cleared
    expect(screen.getByTestId('card-title-input')).toHaveValue('');
    expect(screen.getByTestId('card-body-input')).toHaveValue('');
  });

  it('shows submitting state when isSubmitting is true', () => {
    render(<CardCreateForm onSubmit={vi.fn()} onCancel={vi.fn()} isSubmitting />);

    const submit = screen.getByTestId('card-create-submit');
    expect(submit).toBeDisabled();
    expect(submit).toHaveTextContent('Adding...');
  });
});
