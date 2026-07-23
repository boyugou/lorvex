import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

test('MCP scale benchmark keeps the CLI entry thin and delegates dataset/runtime logic to a support tree', () => {
  const benchmarkEntrySource = fs.readFileSync(
    path.join(repoRoot, 'scripts/tests/mcp/benchmark.scale.ts'),
    'utf8',
  );
  const typesSource = fs.readFileSync(
    path.join(repoRoot, 'scripts/tests/mcp/benchmark.scale/types.ts'),
    'utf8',
  );
  const datasetSource = fs.readFileSync(
    path.join(repoRoot, 'scripts/tests/mcp/benchmark.scale/dataset.ts'),
    'utf8',
  );
  const metadataSource = fs.readFileSync(
    path.join(repoRoot, 'scripts/tests/mcp/benchmark.scale/metadata.ts'),
    'utf8',
  );
  const runtimeSource = fs.readFileSync(
    path.join(repoRoot, 'scripts/tests/mcp/benchmark.scale/runtime.ts'),
    'utf8',
  );

  assert.match(benchmarkEntrySource, /^import { runBenchmarkSuite } from '\.\/benchmark\.scale\/runtime';$/m);
  assert.match(benchmarkEntrySource, /^import type { DatasetBenchmarkResult } from '\.\/benchmark\.scale\/types';$/m);
  assert.match(benchmarkEntrySource, /\nfunction parseArgs\(argv: string\[]\): \{ datasets: number\[]; out\?: string \} \{/);
  assert.match(benchmarkEntrySource, /\nfunction buildReport\(started: string, datasets: number\[], results: DatasetBenchmarkResult\[]\)/);
  assert.doesNotMatch(
    benchmarkEntrySource,
    /function seedScaleDataset\(|async function createHarness\(|function evaluateMetadata\(/,
    'benchmark.scale.ts should stay a CLI composition root after subsystem extraction',
  );

  assert.match(typesSource, /\nexport interface ToolBenchmarkResult \{/);
  assert.match(typesSource, /\nexport interface DatasetBenchmarkResult \{/);

  assert.match(datasetSource, /\nexport function seedScaleDataset\(dbPath: string, total: number, listId = 'list-scale'\): void \{/);
  assert.match(datasetSource, /\nfunction daysFromTodayYmd\(offsetDays = 0\): string \{/);
  assert.match(datasetSource, /date\.setUTCDate\(date\.getUTCDate\(\) \+ offsetDays\);/);

  assert.match(metadataSource, /\nexport function evaluateMetadata\(caseName: string, payload: Record<string, unknown>\): \{/);
  assert.match(metadataSource, /caseName === 'get_todays_tasks'/);
  assert.match(metadataSource, /caseName === 'get_upcoming_tasks'/);

  assert.match(runtimeSource, /^import { seedScaleDataset } from '\.\/dataset';$/m);
  assert.match(runtimeSource, /^import { evaluateMetadata } from '\.\/metadata';$/m);
  assert.match(runtimeSource, /^import type { DatasetBenchmarkResult, ToolBenchmarkResult, ToolCase } from '\.\/types';$/m);
  assert.match(runtimeSource, /\nasync function createHarness\(dbPath: string\): Promise<Harness> \{/);
  assert.match(runtimeSource, /\nexport async function runBenchmarkSuite\(datasets: number\[\]\): Promise<DatasetBenchmarkResult\[]> \{/);
});
