import { describe, it, expect, vi, afterEach } from 'vitest';
import path from 'node:path';
import { loadDecisions, loadGovernance, loadRunState } from './metaSources';

const FIXTURES_DIR = path.resolve(__dirname, '../test/fixtures/meta');
const DECISIONS_DIR = path.join(FIXTURES_DIR, 'decisions');
const GOVERNANCE_DIR = path.join(FIXTURES_DIR, 'governance');
const MALFORMED_DIR = path.join(FIXTURES_DIR, 'malformed');
const STATE_JSON_PATH = path.join(FIXTURES_DIR, 'state.json');
const MISSING_DIR = path.join(FIXTURES_DIR, 'does-not-exist');
const MISSING_STATE_PATH = path.join(FIXTURES_DIR, 'does-not-exist', 'state.json');

describe('metaSources', () => {
  afterEach(() => {
    vi.restoreAllMocks();
  });

  describe('loadDecisions', () => {
    it('happy path: loads the full fixture corpus', () => {
      const decisions = loadDecisions(DECISIONS_DIR);

      expect(decisions).toHaveLength(4);
      expect(decisions.map((d) => d.decision_id).sort()).toEqual([
        'D-20260101-001',
        'D-20260101-002',
        'D-20260101-003',
        'D-20260101-004',
      ]);
    });

    it('edge: missing dir returns []', () => {
      expect(loadDecisions(MISSING_DIR)).toEqual([]);
    });

    it('error: malformed JSON is skipped with a warning, not thrown', () => {
      const warn = vi.spyOn(console, 'warn').mockImplementation(() => {});

      expect(() => loadDecisions(MALFORMED_DIR)).not.toThrow();
      const decisions = loadDecisions(MALFORMED_DIR);

      expect(decisions).toEqual([]);
      expect(warn).toHaveBeenCalled();
    });

    it('boundary (AC3): D-20260101-004 is loaded even though its t800 run recorded exit_code 2', () => {
      const decisions = loadDecisions(DECISIONS_DIR);
      const decision = decisions.find((d) => d.decision_id === 'D-20260101-004');

      expect(decision).toBeDefined();
      expect(decision?.status).toBe('executed');
    });
  });

  describe('loadGovernance', () => {
    it('happy path: loads the full fixture corpus and derives decision_id from the filename', () => {
      const reports = loadGovernance(GOVERNANCE_DIR);

      expect(reports).toHaveLength(4);
      expect(reports.map((r) => r.decision_id).sort()).toEqual([
        'D-20260101-001',
        'D-20260101-002',
        'D-20260101-003',
        'D-20260101-004',
      ]);
    });

    it('edge: missing dir returns []', () => {
      expect(loadGovernance(MISSING_DIR)).toEqual([]);
    });

    it('boundary (AC3): governance for D-20260101-004 is still loaded', () => {
      const reports = loadGovernance(GOVERNANCE_DIR);
      const report = reports.find((r) => r.decision_id === 'D-20260101-004');

      expect(report).toBeDefined();
      expect(report?.verdict).toBe('escalate');
    });
  });

  describe('loadRunState', () => {
    it('happy path: loads all 8 run entries (4 t800 + 4 t1000)', () => {
      const runs = loadRunState(STATE_JSON_PATH);

      expect(runs).toHaveLength(8);
      expect(runs.filter((r) => r.role === 't800')).toHaveLength(4);
      expect(runs.filter((r) => r.role === 't1000')).toHaveLength(4);
    });

    it('edge: missing state.json returns []', () => {
      expect(loadRunState(MISSING_STATE_PATH)).toEqual([]);
    });

    it('boundary (AC3): the t800 run for D-20260101-004 is loaded despite exit_code 2', () => {
      const runs = loadRunState(STATE_JSON_PATH);
      const run = runs.find((r) => r.role === 't800' && r.task === 'D-20260101-004');

      expect(run).toBeDefined();
      expect(run?.exit_code).toBe(2);
    });
  });
});
