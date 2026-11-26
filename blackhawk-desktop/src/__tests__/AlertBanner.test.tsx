import { render, screen } from '@testing-library/react';
import { describe, expect, it } from 'vitest';
import { AlertBanner } from '../components/AlertBanner';
import type { Alert } from '../lib/types';

const criticalAlert: Alert = {
  id: 'alert-001',
  feature: 'F32',
  task: 'T05',
  severity: 'critical',
  status: 'active',
  message: 'Build failed in developer agent',
  created_at: '2026-11-26T10:00:00Z',
  resolved_at: null,
};

const resolvedAlert: Alert = {
  ...criticalAlert,
  id: 'alert-002',
  status: 'resolved',
  resolved_at: '2026-11-26T10:30:00Z',
};

describe('AlertBanner', () => {
  it('renders critical active alert', () => {
    render(<AlertBanner alert={criticalAlert} />);
    expect(screen.getByText('CRITICAL')).toBeInTheDocument();
    expect(screen.getByText('Build failed in developer agent')).toBeInTheDocument();
    expect(screen.getByText('F32')).toBeInTheDocument();
  });

  it('renders resolved alert with RESOLVED label', () => {
    render(<AlertBanner alert={resolvedAlert} />);
    expect(screen.getByText('RESOLVED')).toBeInTheDocument();
  });
});
