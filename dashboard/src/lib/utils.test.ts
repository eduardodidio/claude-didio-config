import { describe, it, expect } from 'vitest';
import { cn } from './utils';

describe('cn', () => {
  it('merges multiple class strings', () => {
    expect(cn('a', 'b')).toBe('a b');
  });

  it('deduplicates conflicting Tailwind classes (twMerge)', () => {
    expect(cn('p-2', 'p-4')).toBe('p-4');
  });

  it('handles falsy inputs', () => {
    expect(cn(null, undefined, false)).toBe('');
  });

  it('passes a single string through', () => {
    expect(cn('text-sm')).toBe('text-sm');
  });
});
