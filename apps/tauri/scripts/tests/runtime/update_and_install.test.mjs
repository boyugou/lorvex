import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

const repoRoot = path.resolve(import.meta.dirname, '..', '..', '..');
const updateScriptPath = path.join(repoRoot, 'scripts', 'update_and_install.sh');

const installSmokeBuilds = [
  {
    name: 'macOS',
    relativePath: 'scripts/update_and_install.sh',
    lockedBuildPattern: /npm run -w app tauri:build -- --bundles app -- --locked/,
    lockfileRequiredPattern: /\[\[ ! -f package-lock\.json \]\]/,
    npmCiPattern: /npm ci/,
  },
  {
    name: 'Linux',
    relativePath: 'scripts/update_and_install_linux.sh',
    lockedBuildPattern: /npm run -w app tauri:build -- --bundles "\$\{BUNDLE\}" -- --locked/,
    lockfileRequiredPattern: /\[\[ ! -f package-lock\.json \]\]/,
    npmCiPattern: /npm ci/,
  },
  {
    name: 'Windows',
    relativePath: 'scripts/update_and_install_windows.ps1',
    lockedBuildPattern: /npm run -w app tauri:build -- --bundles \$Bundle -- --locked/,
    lockfileRequiredPattern: /Test-Path "package-lock\.json"/,
    npmCiPattern: /npm ci/,
  },
];

const sourceCheckoutDocs = [
  'README.md',
  'CONTRIBUTING.md',
  'docs/setup/GETTING_STARTED.md',
];

test('update_and_install.sh does NOT re-sign the installed macOS app bundle', () => {
  // Re-signing was intentionally removed: the Tauri build already signs with
  // Developer ID and embeds the provisioning profile. Ad-hoc re-signing would
  // invalidate the profile binding and break notarized Developer ID artifacts.
  const script = fs.readFileSync(updateScriptPath, 'utf8');

  assert.doesNotMatch(
    script,
    /codesign\s+--force\s+--deep\s+--sign\s+-/,
    'update_and_install.sh must NOT ad-hoc re-sign — it would break the signed artifact identity',
  );

  assert.match(
    script,
    /Skip re-signing/,
    'update_and_install.sh should document why re-signing is skipped',
  );
});

test('source-checkout install smoke builds pass Cargo --locked', () => {
  for (const { name, relativePath, lockedBuildPattern } of installSmokeBuilds) {
    const script = fs.readFileSync(path.join(repoRoot, relativePath), 'utf8');

    assert.match(
      script,
      lockedBuildPattern,
      `${name} install smoke build should forward --locked after the Cargo separator`,
    );
  }
});

test('source-checkout install smoke refreshes npm deps from package-lock', () => {
  for (const { name, relativePath, lockfileRequiredPattern, npmCiPattern } of installSmokeBuilds) {
    const script = fs.readFileSync(path.join(repoRoot, relativePath), 'utf8');

    assert.match(
      script,
      lockfileRequiredPattern,
      `${name} install path should fail closed when package-lock.json is missing`,
    );
    assert.match(
      script,
      npmCiPattern,
      `${name} install path should run npm ci from package-lock.json before building`,
    );
    assert.doesNotMatch(
      script,
      /npm install/,
      `${name} install path must not fall back to npm install because it can mutate dependency resolution`,
    );
  }
});

test('source-checkout setup docs use npm ci instead of npm install', () => {
  for (const relativePath of sourceCheckoutDocs) {
    const source = fs.readFileSync(path.join(repoRoot, relativePath), 'utf8');
    assert.match(source, /npm ci/, `${relativePath} should document npm ci`);
    assert.doesNotMatch(source, /npm install/, `${relativePath} should not document npm install`);
  }
});
