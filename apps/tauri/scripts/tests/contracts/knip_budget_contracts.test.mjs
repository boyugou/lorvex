import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

function runVerifierWithFakeKnip(fakeKnipSource, extraEnv = {}) {
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'lorvex-knip-contract-'));
  const fakeKnipPath = path.join(tempDir, 'knip');
  fs.writeFileSync(fakeKnipPath, fakeKnipSource);
  fs.chmodSync(fakeKnipPath, 0o755);
  try {
    return spawnSync(process.execPath, ['scripts/verify/knip_unused.mjs'], {
      cwd: repoRoot,
      env: {
        ...process.env,
        ...extraEnv,
        KNIP_UNUSED_BIN: fakeKnipPath,
      },
      encoding: 'utf8',
    });
  } finally {
    fs.rmSync(tempDir, { recursive: true, force: true });
  }
}

function runVerifierWithMissingKnip(extraEnv = {}) {
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'lorvex-knip-missing-contract-'));
  const missingKnipPath = path.join(tempDir, 'missing-knip');
  try {
    return spawnSync(process.execPath, ['scripts/verify/knip_unused.mjs'], {
      cwd: repoRoot,
      env: {
        ...process.env,
        ...extraEnv,
        KNIP_UNUSED_BIN: missingKnipPath,
      },
      encoding: 'utf8',
    });
  } finally {
    fs.rmSync(tempDir, { recursive: true, force: true });
  }
}

test('knip budget verifier uses a pinned project dependency', () => {
  const packageJson = JSON.parse(
    fs.readFileSync(path.join(repoRoot, 'package.json'), 'utf8'),
  );
  const knipVersion = packageJson.devDependencies?.knip;

  assert.equal(typeof knipVersion, 'string');
  assert.match(knipVersion, /^\d+\.\d+\.\d+$/);

  const verifierSource = fs.readFileSync(
    path.join(repoRoot, 'scripts/verify/knip_unused.mjs'),
    'utf8',
  );
  assert.doesNotMatch(verifierSource, /spawnSync\('npx'/);
  assert.doesNotMatch(verifierSource, /\['knip',/);
  assert.match(verifierSource, /path\.join\(\s*REPO_ROOT,\s*'node_modules',\s*'\.bin',/);
  assert.match(verifierSource, /\? 'knip\.cmd' : 'knip'/);
});

test('knip budget verifier fails closed when knip exits nonzero', () => {
  const result = runVerifierWithFakeKnip(`#!/usr/bin/env node
if (process.argv.includes('--version')) {
  process.stdout.write('6.12.1\\n');
  process.exit(0);
}
process.stderr.write('knip crashed while loading project\\n');
process.exit(2);
`);

  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /knip.*(?:status|failed|exit|crashed)/i);
});

test('knip budget verifier fails closed when knip is missing in GitHub Actions', () => {
  const result = runVerifierWithMissingKnip({
    GITHUB_ACTIONS: 'true',
  });

  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /Knip is required in GitHub Actions/i);
});

test('knip budget verifier fails closed on unparseable knip output', () => {
  const result = runVerifierWithFakeKnip(`#!/usr/bin/env node
if (process.argv.includes('--version')) {
  process.stdout.write('6.12.1\\n');
  process.exit(0);
}
process.stdout.write('this is not a knip report\\n');
process.exit(0);
`);

  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /unparseable|parse/i);
});

test('knip budget verifier accepts ANSI-colored report output from bundle runs', () => {
  const result = runVerifierWithFakeKnip(`#!/usr/bin/env node
if (process.argv.includes('--version')) {
  process.stdout.write('6.12.1\\n');
  process.exit(0);
}
process.stdout.write('\\u001b[1mUnused exports (0)\\u001b[22m\\n\\u001b[1mUnused exported types (0)\\u001b[22m\\n');
process.exit(0);
`);

  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /0 unused exports/);
  assert.match(result.stdout, /0 unused exported types/);
});

test('knip budget verifier clears FORCE_COLOR before invoking knip', () => {
  const result = runVerifierWithFakeKnip(`#!/usr/bin/env node
if (process.argv.includes('--version')) {
  process.stdout.write('6.12.1\\n');
  process.exit(0);
}
if (process.env.FORCE_COLOR) {
  process.stderr.write("(node:1) Warning: The 'NO_COLOR' env is ignored due to the 'FORCE_COLOR' env being set.\\n");
}
process.exit(0);
`, {
    FORCE_COLOR: '1',
    NO_COLOR: '1',
  });

  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /0 unused exports/);
});
