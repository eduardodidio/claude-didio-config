import { render, screen } from '@testing-library/react';
import { describe, it, expect } from 'vitest';
import { Progress } from './progress';

describe('Progress', () => {
  it('renders with role="progressbar"', () => {
    render(<Progress value={75} />);
    expect(screen.getByRole('progressbar')).toBeInTheDocument();
  });

  it('sets aria-valuenow to the value prop', () => {
    render(<Progress value={75} />);
    expect(screen.getByRole('progressbar')).toHaveAttribute('aria-valuenow', '75');
  });

  it('renders with default value of 0', () => {
    render(<Progress />);
    const bar = screen.getByRole('progressbar');
    expect(bar).toHaveAttribute('aria-valuenow', '0');
  });

  it('renders with value={100}', () => {
    render(<Progress value={100} />);
    expect(screen.getByRole('progressbar')).toHaveAttribute('aria-valuenow', '100');
  });

  it('renders with value={0} without error', () => {
    render(<Progress value={0} />);
    expect(screen.getByRole('progressbar')).toHaveAttribute('aria-valuenow', '0');
  });

  it('renders with negative value without throwing (Radix handles clamping)', () => {
    expect(() => render(<Progress value={-10} />)).not.toThrow();
  });

  it('applies custom className to the root element', () => {
    render(<Progress value={50} className="h-3 custom-root" />);
    const bar = screen.getByRole('progressbar');
    expect(bar).toHaveClass('h-3');
    expect(bar).toHaveClass('custom-root');
  });

  it('default root has h-1.5 and bg-muted classes', () => {
    render(<Progress value={50} />);
    const bar = screen.getByRole('progressbar');
    expect(bar).toHaveClass('h-1.5');
    expect(bar).toHaveClass('bg-muted');
    expect(bar).toHaveClass('rounded-full');
    expect(bar).toHaveClass('overflow-hidden');
  });

  it('applies indicatorClassName to the indicator element', () => {
    const { container } = render(
      <Progress value={50} indicatorClassName="bg-destructive custom-indicator" />,
    );
    // The indicator is the motion.div inside the Indicator primitive
    const indicator = container.querySelector('.bg-destructive');
    expect(indicator).toBeInTheDocument();
    expect(indicator).toHaveClass('custom-indicator');
  });

  it('indicator has bg-primary class by default', () => {
    const { container } = render(<Progress value={50} />);
    const indicator = container.querySelector('.bg-primary');
    expect(indicator).toBeInTheDocument();
  });
});
