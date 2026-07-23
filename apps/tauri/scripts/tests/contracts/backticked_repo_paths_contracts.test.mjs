import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { verifyBacktickedRepoPaths } from '../../verify/backticked_repo_paths.mjs';
import { repoRoot } from './shared.mjs';

test('backticked repo path verifier is wired into docs governance', () => {
  const docsGovernance = fs.readFileSync(path.join(repoRoot, 'scripts/verify/doc_governance.mjs'), 'utf8');
  const verifierPath = path.join(repoRoot, 'scripts/verify/backticked_repo_paths.mjs');

  assert.ok(fs.existsSync(verifierPath), 'backticked repo path verifier should exist');
  assert.match(
    docsGovernance,
    /verifyBacktickedRepoPaths\(/,
    'docs governance should run the backticked repo path verifier',
  );
});

test('backticked repo path verifier only exports its public verifier API', async () => {
  const module = await import('../../verify/backticked_repo_paths.mjs');

  assert.equal(typeof module.verifyBacktickedRepoPaths, 'function');
  assert.equal(
    'collectBacktickedRepoPathViolations' in module,
    false,
    'collector is an implementation detail, not a root-script export',
  );
});

test('active docs do not contain stale backticked repo paths', () => {
  const result = verifyBacktickedRepoPaths({ repoRoot });

  assert.equal(result.ok, true);
  assert.ok(result.filesChecked > 0);
  assert.ok(result.backtickedPathsChecked > 0);
});
