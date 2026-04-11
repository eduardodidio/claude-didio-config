import { render, screen } from '@testing-library/react';
import { describe, it, expect } from 'vitest';
import { Button } from './button';
import { Badge } from './badge';
import { Card, CardContent } from './card';

describe('ui primitives smoke test', () => {
  it('renders a Button with text', () => {
    render(<Button>click</Button>);
    const btn = screen.getByRole('button', { name: 'click' });
    expect(btn.tagName).toBe('BUTTON');
    expect(btn.textContent).toBe('click');
  });

  it('renders a Badge with outline variant', () => {
    const { container } = render(<Badge variant="outline">x</Badge>);
    const badge = container.firstChild as HTMLElement;
    expect(badge.textContent).toBe('x');
    expect(badge.className).toContain('text-foreground');
  });

  it('renders a Card with CardContent', () => {
    render(
      <Card>
        <CardContent>c</CardContent>
      </Card>,
    );
    expect(screen.getByText('c').textContent).toBe('c');
  });

  it('renders an empty Card without children', () => {
    const { container } = render(<Card />);
    expect(container.firstChild).not.toBeNull();
  });
});
