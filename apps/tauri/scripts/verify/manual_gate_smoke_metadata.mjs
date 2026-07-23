#!/usr/bin/env node

import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';

import {
  assertContract,
  resolveRepoRootFromMeta,
  runVerifierCli,
} from '../lib/verifier_runtime.mjs';

const SCRIPT_TAG = '[manual_gate_smoke_metadata]';
const FORBIDDEN_HISTORICAL_IDS_RE = /\b(?:168|169|170|208)\b/;

function runMetadataSmoke(repoRoot, outDir) {
  const result = spawnSync(process.execPath, [
    'scripts/manual-gate/smoke_runner.mjs',
    '--metadata-only',
    '--out-dir',
    outDir,
  ], {
    cwd: repoRoot,
    encoding: 'utf8',
  });

  assertContract(
    result.status === 0,
    SCRIPT_TAG,
    `manual-gate smoke metadata generation failed\nstdout:\n${result.stdout ?? ''}\nstderr:\n${result.stderr ?? ''}`,
  );
}

function assertReportShape(report) {
  assertContract(report && typeof report === 'object', SCRIPT_TAG, 'metadata report must be a JSON object');
  assertContract(Array.isArray(report.steps) && report.steps.length > 0, SCRIPT_TAG, 'metadata report must include steps');
  assertContract(report.coverage_map && typeof report.coverage_map === 'object', SCRIPT_TAG, 'metadata report must include coverage_map');

  const serialized = JSON.stringify(report);
  assertContract(!FORBIDDEN_HISTORICAL_IDS_RE.test(serialized), SCRIPT_TAG, 'manual-gate smoke metadata must not reference closed historical issue IDs');

  const stepIds = new Set(report.steps.map((step) => step.id));
  for (const step of report.steps) {
    assertContract(Array.isArray(step.gate_refs) && step.gate_refs.length > 0, SCRIPT_TAG, `step ${step.id} must include neutral gate_refs`);
    assertContract(!Object.hasOwn(step, 'issues'), SCRIPT_TAG, `step ${step.id} must not use issue-number metadata`);
  }
  for (const [gateRef, coverage] of Object.entries(report.coverage_map)) {
    assertContract(!/^\d+$/.test(gateRef), SCRIPT_TAG, `coverage key ${gateRef} must be a neutral gate id, not an issue number`);
    assertContract(Array.isArray(coverage.automated), SCRIPT_TAG, `coverage ${gateRef} must include automated step ids`);
    for (const stepId of coverage.automated) {
      assertContract(stepIds.has(stepId), SCRIPT_TAG, `coverage ${gateRef} references unknown step ${stepId}`);
    }
  }
}

export function verifyManualGateSmokeMetadata({
  repoRoot = resolveRepoRootFromMeta(import.meta.url),
} = {}) {
  const scratchParent = path.join(repoRoot, 'artifacts');
  fs.mkdirSync(scratchParent, { recursive: true });
  const outDirAbs = fs.mkdtempSync(path.join(scratchParent, `manual-gate-smoke-metadata-${process.pid}-`));
  const outDir = path.relative(repoRoot, outDirAbs).split(path.sep).join('/');
  try {
    runMetadataSmoke(repoRoot, outDir);
    const latestPath = path.join(outDirAbs, 'manual-gate-smoke-latest.json');
    assertContract(fs.existsSync(latestPath), SCRIPT_TAG, 'metadata smoke did not write latest JSON report');
    assertReportShape(JSON.parse(fs.readFileSync(latestPath, 'utf8')));
  } finally {
    fs.rmSync(outDirAbs, { recursive: true, force: true });
  }

  return { ok: true };
}

if (import.meta.url === `file://${process.argv[1]}`) {
  runVerifierCli({
    scriptTag: SCRIPT_TAG,
    successMessage: 'manual-gate smoke metadata contract passed.',
    run: () => verifyManualGateSmokeMetadata(),
  });
}
