import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

import { runBenchmarkSuite } from './benchmark.scale/runtime';
import { checkThreshold, type ThresholdResult } from './benchmark.scale/thresholds';
import type { DatasetBenchmarkResult } from './benchmark.scale/types';

const THIS_DIR = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = resolve(THIS_DIR, '..', '..', '..');

function parseArgs(argv: string[]): { datasets: number[]; out?: string } {
  let datasets: number[] = [1000, 5000, 10000];
  let out: string | undefined;

  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === undefined) {
      continue;
    }
    const nextArg = argv[i + 1];
    if (arg === '--dataset' && nextArg !== undefined) {
      datasets = nextArg.split(',').map((v) => Number(v.trim())).filter((v) => Number.isFinite(v) && v > 0);
      i += 1;
      continue;
    }
    if (arg.startsWith('--dataset=')) {
      const [, rawDatasets = ''] = arg.split('=', 2);
      datasets = rawDatasets.split(',').map((v) => Number(v.trim())).filter((v) => Number.isFinite(v) && v > 0);
      continue;
    }
    if (arg === '--out' && nextArg !== undefined) {
      out = nextArg;
      i += 1;
      continue;
    }
    if (arg.startsWith('--out=')) {
      const [, rawOut = ''] = arg.split('=', 2);
      out = rawOut;
      continue;
    }
  }

  if (datasets.length === 0) datasets = [1000, 5000, 10000];
  return out === undefined ? { datasets } : { datasets, out };
}

function buildReport(started: string, datasets: number[], results: DatasetBenchmarkResult[]) {
  const thresholds: ThresholdResult[] = [];
  for (const r of results) {
    for (const t of r.tools) {
      thresholds.push(checkThreshold(t.tool, r.dataset_size, t.elapsed_ms));
    }
  }
  const thresholdFailures = thresholds.filter((t) => !t.passed);

  return {
    generated_at: started,
    runtime: 'rust' as const,
    datasets,
    results,
    thresholds: {
      total: thresholds.length,
      passed: thresholds.length - thresholdFailures.length,
      failed: thresholdFailures.length,
      failures: thresholdFailures,
    },
    summary: {
      all_metadata_ok: results.every((r) => r.tools.every((t) => t.metadata_ok)),
      all_thresholds_ok: thresholdFailures.length === 0,
      worst_tool_latency_ms: Math.max(...results.map((r) => r.max_tool_elapsed_ms)),
      worst_payload_bytes: Math.max(...results.map((r) => r.max_payload_bytes)),
    },
  };
}

async function main(): Promise<void> {
  const { datasets, out } = parseArgs(process.argv.slice(2));
  const started = new Date().toISOString();
  const results = await runBenchmarkSuite(datasets);
  const report = buildReport(started, datasets, results);
  const json = JSON.stringify(report, null, 2);

  if (out) {
    const outPath = resolve(REPO_ROOT, out);
    mkdirSync(dirname(outPath), { recursive: true });
    writeFileSync(outPath, `${json}\n`, 'utf8');
    console.log(`Wrote benchmark report: ${outPath}`);
  }

  console.log(json);

  // Fail if any tool exceeded its performance budget.
  if (!report.summary.all_thresholds_ok) {
    console.error(
      `\n❌ ${report.thresholds.failed} threshold failure(s):`,
    );
    for (const f of report.thresholds.failures) {
      console.error(
        `  ${f.tool} @ ${f.dataset_size} tasks: ${f.elapsed_ms}ms > ${f.budget_ms}ms budget`,
      );
    }
    process.exitCode = 1;
  }
}

main().catch((error) => {
  console.error(error instanceof Error ? error.stack ?? error.message : String(error));
  process.exitCode = 1;
});
