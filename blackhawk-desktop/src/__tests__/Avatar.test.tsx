import { render, screen } from '@testing-library/react';
import { describe, expect, it } from 'vitest';
import { Avatar } from '../components/Avatar';

describe('Avatar', () => {
  it('renders fallback text when no src', () => {
    render(<Avatar />);
    expect(screen.getByText('BH')).toBeInTheDocument();
  });

  it('renders custom fallback', () => {
    render(<Avatar fallback="A" />);
    expect(screen.getByText('A')).toBeInTheDocument();
  });

  it('renders image when src provided', () => {
    render(<Avatar src="/test.png" />);
    expect(screen.getByAltText('Avatar')).toBeInTheDocument();
  });
});
