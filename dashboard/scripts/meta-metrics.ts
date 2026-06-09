import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { computeMetaMetrics } from '../src/lib/metaMetrics';
import { loadDecisions, loadGovernance, loadRunState } from '../src/lib/metaSources';
import type { MetaMetricsReport } from '../src/lib/metaTypes';

const HELP = `\
USAGE:
  didio meta-metrics [--root <path>]    Compute KPI report from live logs
  didio meta-metrics --help             Show this help

OUTPUT:
  logs/agents/meta-metrics.json         JSON report (MetaMetricsReport)
  stdout                                Human-readable text report

SOURCES:
  logs/decisions/D-*.json               Gandalf decision records
  logs/governance/G-*.json              Saruman governance reports
  logs/agents/state.json                Agent run state (latency, exit_code)

EXIT CODES:
  0  Success (empty corpus prints zeros — not an error)
  1  Fatal error (could not write output)
`;

function pad(label: string, width: number): string {
  return label.padEnd(width);
}

function printReport(report: MetaMetricsReport): void {
  const { gandalf: g, saruman: s, loop_health: l } = report;

  console.log('\n  ════════════════════════════════════════════════════');
  console.log('  didio meta-metrics — Meta-Agent KPI Report');
  console.log(`  Generated: ${report.generated_at}`);
  console.log('  ════════════════════════════════════════════════════\n');

  console.log('  ── Gandalf (Orchestrator) ─────────────────────────');
  console.log(`  ${pad('Total decisions', 36)} ${g.total_decisions}`);
  console.log(`  ${pad('Avg latency (secs)', 36)} ${g.avg_latency_secs ?? 'n/a'}`);
  console.log(`  ${pad('Min latency (secs)', 36)} ${g.min_latency_secs ?? 'n/a'}`);
  console.log(`  ${pad('Avg options considered', 36)} ${g.avg_options_considered ?? 'n/a'}`);
  console.log(`  ${pad('Avg actions/decision', 36)} ${g.avg_actions_per_decision ?? 'n/a'}`);

  if (Object.keys(g.type_distribution).length > 0) {
    console.log('\n  Type distribution:');
    for (const [type, count] of Object.entries(g.type_distribution)) {
      console.log(`    ${pad(type, 32)} ${count}`);
    }
  }
  if (Object.keys(g.status_distribution).length > 0) {
    console.log('\n  Status distribution:');
    for (const [status, count] of Object.entries(g.status_distribution)) {
      console.log(`    ${pad(status, 32)} ${count}`);
    }
  }

  console.log('\n  ── Saruman (Governance) ───────────────────────────');
  console.log(`  ${pad('Total reviews', 36)} ${s.total_reviews}`);
  console.log(`  ${pad('Avg confidence', 36)} ${s.avg_confidence ?? 'n/a'}`);
  console.log(`  ${pad('Avg blind spots', 36)} ${s.avg_blind_spots ?? 'n/a'}`);
  console.log(`  ${pad('Avg risks', 36)} ${s.avg_risks ?? 'n/a'}`);
  console.log(
    `  ${pad('Avg decision→governance (secs)', 36)} ${s.avg_decision_to_governance_latency_secs ?? 'n/a'}`,
  );

  if (s.total_reviews > 0) {
    console.log('\n  Verdict distribution:');
    console.log(`  ${pad('Verdict', 18)} ${pad('Count', 8)} Rate`);
    console.log(`  ${'-'.repeat(36)}`);
    for (const verdict of ['agree', 'challenge', 'escalate'] as const) {
      const count = s.verdict_distribution[verdict];
      const rate = s.verdict_rates[verdict];
      console.log(`  ${pad(verdict, 18)} ${pad(String(count), 8)} ${rate}`);
    }

    console.log('\n  Bias frequency:');
    for (const [bias, count] of Object.entries(s.bias_frequency)) {
      console.log(`    ${pad(bias, 32)} ${count}`);
    }
  }

  console.log('\n  ── Loop Health ────────────────────────────────────');
  console.log(`  ${pad('Challenge round-trips', 36)} ${l.challenge_round_trips}`);
  console.log(`  ${pad('Blocking escalations', 36)} ${l.blocking_escalations}`);
  console.log(
    `  ${pad('Decisions without governance', 36)} ${l.decisions_without_governance}`,
  );
  console.log(
    `  ${pad('Auto-reviewed %', 36)} ${l.auto_reviewed_pct != null ? `${Math.round(l.auto_reviewed_pct * 100)}%` : 'n/a'}`,
  );

  console.log('\n  ════════════════════════════════════════════════════\n');
}

export async function run(root: string): Promise<MetaMetricsReport> {
  const decisionsDir = join(root, 'logs', 'decisions');
  const govDir = join(root, 'logs', 'governance');
  const stateJsonPath = join(root, 'logs', 'agents', 'state.json');
  const outPath = join(root, 'logs', 'agents', 'meta-metrics.json');
  const configPath = join(root, 'didio.config.json');

  const decisions = loadDecisions(decisionsDir);
  const governance = loadGovernance(govDir);
  const runs = loadRunState(stateJsonPath);

  let autoGovernance = true;
  try {
    const cfg = JSON.parse(readFileSync(configPath, 'utf-8')) as {
      meta_agents?: { t800?: { auto_governance?: boolean } };
    };
    autoGovernance = cfg.meta_agents?.t800?.auto_governance ?? true;
  } catch {
    // config absent or malformed — default to true
  }

  const report = computeMetaMetrics({ decisions, governance, runs, autoGovernance });

  const outDir = dirname(outPath);
  if (!existsSync(outDir)) {
    mkdirSync(outDir, { recursive: true });
  }
  writeFileSync(outPath, JSON.stringify(report, null, 2), 'utf-8');

  return report;
}

// CLI entry point — only runs when vite-node invokes this script directly.
// With vite-node, process.argv[1] is the vite-node binary; vitest runs inside
// a tinypool worker whose argv[1] is the worker entry — never 'vite-node'.
function isCliEntry(): boolean {
  return (process.argv[1] ?? '').includes('vite-node');
}

if (isCliEntry()) {
  // vite-node strips the script name from argv; user args start at index 2
  const args = process.argv.slice(2);

  if (args.includes('--help') || args.includes('-h')) {
    process.stdout.write(HELP);
    process.exit(0);
  }

  let projectRoot = process.cwd();
  const rootIdx = args.indexOf('--root');
  if (rootIdx !== -1 && args[rootIdx + 1]) {
    projectRoot = resolve(args[rootIdx + 1]);
  }

  run(projectRoot)
    .then((report) => {
      printReport(report);
      const outPath = join(projectRoot, 'logs', 'agents', 'meta-metrics.json');
      console.log(`  Written: ${outPath}\n`);
    })
    .catch((err: Error) => {
      console.error(`\n[meta-metrics] fatal: ${err.message}\n`);
      process.exit(1);
    });
}
