import { cpSync, existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterEach, describe, expect, it } from 'vitest';
import { run } from './meta-metrics';

const FIXTURES_ROOT = join(__dirname, '../src/test/fixtures/meta');

describe('meta-metrics CLI (run())', () => {
  const tempDirs: string[] = [];

  function makeTempRoot(): string {
    const dir = join(
      tmpdir(),
      `meta-metrics-test-${Date.now()}-${Math.random().toString(36).slice(2)}`,
    );
    mkdirSync(dir, { recursive: true });
    tempDirs.push(dir);
    return dir;
  }

  afterEach(() => {
    for (const d of tempDirs.splice(0)) {
      rmSync(d, { recursive: true, force: true });
    }
  });

  function seedFixtures(root: string): void {
    const logsAgents = join(root, 'logs', 'agents');
    mkdirSync(logsAgents, { recursive: true });
    cpSync(join(FIXTURES_ROOT, 'state.json'), join(logsAgents, 'state.json'));

    const logsDecisions = join(root, 'logs', 'decisions');
    mkdirSync(logsDecisions, { recursive: true });
    cpSync(join(FIXTURES_ROOT, 'decisions'), logsDecisions, { recursive: true });

    const logsGov = join(root, 'logs', 'governance');
    mkdirSync(logsGov, { recursive: true });
    cpSync(join(FIXTURES_ROOT, 'governance'), logsGov, { recursive: true });
  }

  it('happy path: writes meta-metrics.json whose content matches the returned report', async () => {
    const root = makeTempRoot();
    seedFixtures(root);

    const report = await run(root);

    const outPath = join(root, 'logs', 'agents', 'meta-metrics.json');
    expect(existsSync(outPath)).toBe(true);

    const written = JSON.parse(readFileSync(outPath, 'utf-8'));
    expect(written).toEqual(report);
  });

  it('happy path: full fixture corpus produces the expected KPI counts', async () => {
    const root = makeTempRoot();
    seedFixtures(root);

    const report = await run(root);

    expect(report.gandalf.total_decisions).toBe(4);
    expect(report.saruman.total_reviews).toBe(4);
    expect(report.loop_health.decisions_without_governance).toBe(0);
    // AC3: D-20260101-004 counted despite t800 exit_code=2 on disk
    expect(report.gandalf.type_distribution['block']).toBe(1);
  });

  it('empty corpus: zeros report, file still written, no crash', async () => {
    const root = makeTempRoot();
    mkdirSync(join(root, 'logs', 'decisions'), { recursive: true });
    mkdirSync(join(root, 'logs', 'governance'), { recursive: true });
    mkdirSync(join(root, 'logs', 'agents'), { recursive: true });

    const report = await run(root);

    expect(report.gandalf.total_decisions).toBe(0);
    expect(report.saruman.total_reviews).toBe(0);
    expect(report.gandalf.avg_latency_secs).toBeNull();
    expect(report.saruman.avg_confidence).toBeNull();
    expect(report.loop_health.auto_reviewed_pct).toBeNull();

    const outPath = join(root, 'logs', 'agents', 'meta-metrics.json');
    expect(existsSync(outPath)).toBe(true);

    const written = JSON.parse(readFileSync(outPath, 'utf-8'));
    expect(written.gandalf.total_decisions).toBe(0);
  });

  it('empty corpus: missing log dirs do not crash (dirs not created)', async () => {
    const root = makeTempRoot();
    // Intentionally do NOT create any subdirs

    const report = await run(root);

    expect(report.gandalf.total_decisions).toBe(0);
    expect(report.saruman.total_reviews).toBe(0);
  });

  it('malformed artifact is skipped, run still succeeds with remaining valid artifacts', async () => {
    const root = makeTempRoot();
    seedFixtures(root);

    // Write a malformed JSON into decisions dir
    writeFileSync(join(root, 'logs', 'decisions', 'D-20260101-999.json'), '{invalid', 'utf-8');

    const report = await run(root);

    // Valid decisions still loaded; malformed one skipped
    expect(report.gandalf.total_decisions).toBe(4);
  });

  it('boundary: a single decision with one governance report produces count=1 fields', async () => {
    const root = makeTempRoot();

    mkdirSync(join(root, 'logs', 'agents'), { recursive: true });
    mkdirSync(join(root, 'logs', 'decisions'), { recursive: true });
    mkdirSync(join(root, 'logs', 'governance'), { recursive: true });

    cpSync(
      join(FIXTURES_ROOT, 'decisions', 'D-20260101-001.json'),
      join(root, 'logs', 'decisions', 'D-20260101-001.json'),
    );
    cpSync(
      join(FIXTURES_ROOT, 'governance', 'G-D-20260101-001.json'),
      join(root, 'logs', 'governance', 'G-D-20260101-001.json'),
    );

    const stateOne = {
      generated_at: '2026-01-01T00:03:00Z',
      agents: [
        {
          feature: 'F17',
          role: 't800',
          task: 'D-20260101-001',
          task_file: 'logs/decisions/D-20260101-001.json',
          started_at: '2026-01-01T00:00:00Z',
          finished_at: '2026-01-01T00:02:00Z',
          status: 'completed',
          exit_code: 0,
        },
        {
          feature: 'F17',
          role: 't1000',
          task: 'D-20260101-001',
          task_file: 'logs/governance/G-D-20260101-001.json',
          started_at: '2026-01-01T00:02:30Z',
          finished_at: '2026-01-01T00:03:00Z',
          status: 'completed',
          exit_code: 0,
        },
      ],
    };
    writeFileSync(
      join(root, 'logs', 'agents', 'state.json'),
      JSON.stringify(stateOne, null, 2),
      'utf-8',
    );

    const report = await run(root);

    expect(report.gandalf.total_decisions).toBe(1);
    expect(report.saruman.total_reviews).toBe(1);
    expect(report.loop_health.decisions_without_governance).toBe(0);
    expect(report.gandalf.avg_latency_secs).toBe(120);
    expect(report.saruman.avg_decision_to_governance_latency_secs).toBe(60);
  });
});
