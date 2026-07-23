import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from '../contracts/shared.mjs';

const verifier = path.join(repoRoot, 'scripts', 'verify', 'shell_scripts_shellcheck.mjs');

function runVerifierWithoutShellcheck(extraEnv = {}) {
  return spawnSync(process.execPath, [verifier], {
    cwd: repoRoot,
    encoding: 'utf8',
    env: {
      ...process.env,
      ...extraEnv,
      PATH: '',
    },
  });
}

test('shellcheck verifier skips explicitly on local machines without shellcheck', () => {
  const result = runVerifierWithoutShellcheck({ GITHUB_ACTIONS: 'false' });

  assert.equal(result.status, 0);
  assert.match(result.stderr, /shellcheck not available locally; skipping/);
});

test('shellcheck verifier fails closed in GitHub Actions without shellcheck', () => {
  const result = runVerifierWithoutShellcheck({ GITHUB_ACTIONS: 'true' });

  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /shellcheck is required in GitHub Actions/);
});
