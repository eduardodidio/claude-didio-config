import '@testing-library/jest-dom';

// Polyfill ResizeObserver for jsdom (required by @radix-ui/react-scroll-area)
if (typeof globalThis.ResizeObserver === 'undefined') {
  globalThis.ResizeObserver = class ResizeObserver {
    observe() {}
    unobserve() {}
    disconnect() {}
  } as unknown as typeof ResizeObserver;
}
