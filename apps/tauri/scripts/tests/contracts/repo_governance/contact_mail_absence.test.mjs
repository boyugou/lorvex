import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from '../shared.mjs';
import { displayCommand, flattenBundle } from '../../../verify/verification_manifest.mjs';

// Contract test (issue #4499): the contact-mail verifier ENFORCES CLAUDE.md
// Core Design Rule #9 — no @lorvex.app mailbox exists; every contact path
// routes through GitHub. This guards the verifier's wiring (package.json
// script, repo-governance bundle inclusion, source presence) and pins the
// behavioral contract (forbidden literal scan + advisory URL requirement).
test('contact mail absence verifier is wired into the repo-governance bundle and enforces CLAUDE.md rule #9', () => {
  const packageJson = JSON.parse(fs.readFileSync(path.join(repoRoot, 'package.json'), 'utf8'));
  const repoGovernanceCommands = flattenBundle('verify:repo-governance').map(displayCommand);
  const verifierPath = path.join(repoRoot, 'scripts', 'verify', 'contact_mail_absence.mjs');

  assert.equal(
    packageJson.scripts['verify:contact-mail-absence'],
    'node scripts/verify/contact_mail_absence.mjs',
    'package.json should expose the contact mail absence verifier',
  );
  assert.equal(
    packageJson.scripts['verify:contact-mail-routing'],
    undefined,
    'the deprecated contact-mail-routing script must not return',
  );
  assert.equal(
    repoGovernanceCommands.includes('npm run verify:contact-mail-absence'),
    true,
    'repo governance should include the contact mail absence verifier',
  );
  assert.equal(fs.existsSync(verifierPath), true, 'contact mail absence verifier should exist');

  const verifierSource = fs.readFileSync(verifierPath, 'utf8');

  assert.match(verifierSource, /SECURITY\.md/, 'verifier should guard the security contact root doc');
  assert.match(verifierSource, /SUPPORT\.md/, 'verifier should guard the support contact root doc');
  assert.match(verifierSource, /CODE_OF_CONDUCT\.md/, 'verifier should guard the conduct contact root doc');
  assert.match(verifierSource, /README\.md/, 'verifier should guard the project README');
  assert.match(
    verifierSource,
    /@lorvex\.app/,
    'verifier should encode the forbidden mailbox literal it scans for',
  );
  assert.match(
    verifierSource,
    /security\/advisories\/new/,
    'verifier should require SECURITY.md to link the GitHub private advisories URL',
  );
  assert.match(verifierSource, /4096/, 'verifier should reference the #4096 mailbox-provisioning issue');
});
