import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import { spawnSync } from 'node:child_process';
import path from 'node:path';
import test from 'node:test';

import { verifyPlatformCapabilityContract } from '../../../verify/platform_capability_contract.mjs';
import { verifyAppSelectVariantContract } from '../../../verify/appselect_variant_contract.mjs';
import { verifyAndroidTypographyContract } from '../../../verify/android_typography_contract.mjs';
import { verifyAndroidScaffoldContract } from '../../../verify/android_scaffold.mjs';
import { verifyAndroidBackgroundReliabilityContract } from '../../../verify/android_background_reliability_contract.mjs';

import { fixturesRoot, repoRoot } from '../shared.mjs';

test('ui-wiring verifier passes against the canonical repo', () => {
  const result = spawnSync(process.execPath, ['scripts/verify/ui_wiring.mjs'], {
    cwd: repoRoot,
    encoding: 'utf8',
  });

  assert.equal(
    result.status,
    0,
    `ui_wiring verifier should pass on the canonical repo.\nstdout:\n${result.stdout}\nstderr:\n${result.stderr}`,
  );
});

test('platform capability verifier passes canonical fixture', () => {
  const fixtureRepoRoot = path.join(fixturesRoot, 'platform-contract', 'pass');
  assert.doesNotThrow(() => verifyPlatformCapabilityContract({ repoRoot: fixtureRepoRoot }));
});

test('platform capability verifier fails when data-os attributes are only in comments', () => {
  const fixtureRepoRoot = path.join(fixturesRoot, 'platform-contract', 'fail-main-attr-comment');
  assert.throws(
    () => verifyPlatformCapabilityContract({ repoRoot: fixtureRepoRoot }),
    /main\.runtime\.ts must set documentElement data-desktop-os attribute/i,
  );
});

test('platform capability verifier fails when main.runtime is not installed', () => {
  const fixtureRepoRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'platform-contract-unused-runtime-'));
  fs.cpSync(path.join(fixturesRoot, 'platform-contract', 'pass'), fixtureRepoRoot, { recursive: true });
  fs.writeFileSync(
    path.join(fixtureRepoRoot, 'app', 'src', 'main.tsx'),
    [
      "import { getDesktopPlatform, getMobilePlatform } from './lib/platform';",
      '',
      'void getDesktopPlatform();',
      'void getMobilePlatform();',
      '',
    ].join('\n'),
  );

  assert.throws(
    () => verifyPlatformCapabilityContract({ repoRoot: fixtureRepoRoot }),
    /main\.tsx must call installMainDocumentRuntime/i,
  );
});

test('platform capability verifier is split by contract domain', () => {
  const moduleRoot = path.join(repoRoot, 'scripts', 'lib', 'platform_capability_contract');
  for (const moduleName of [
    'ast.mjs',
    'consumers.mjs',
    'contract.mjs',
    'document_runtime.mjs',
    'repo_paths.mjs',
    'runtime_profile.mjs',
  ]) {
    assert.equal(fs.existsSync(path.join(moduleRoot, moduleName)), true, `${moduleName} module must exist`);
  }

  const verifierSource = fs.readFileSync(
    path.join(repoRoot, 'scripts', 'verify', 'platform_capability_contract.mjs'),
    'utf8',
  );
  assert.doesNotMatch(verifierSource, /sync\.ts|legacy single-file|isLikelyMobileRuntime|fallback/i);
  assert.match(verifierSource, /assertRuntimeProfileModelContracts/);
  assert.match(verifierSource, /assertMainDocumentRuntimeContract/);
  assert.match(verifierSource, /assertRuntimeProfileConsumerContracts/);
});

test('AppSelect variant verifier passes explicit literal variants', () => {
  const srcRoot = path.join(fixturesRoot, 'appselect-contract', 'pass', 'app', 'src');
  assert.doesNotThrow(() => verifyAppSelectVariantContract({ srcRoot }));
});

test('AppSelect variant verifier fails dynamic variant expressions', () => {
  const srcRoot = path.join(fixturesRoot, 'appselect-contract', 'fail-dynamic-variant', 'app', 'src');
  assert.throws(
    () => verifyAppSelectVariantContract({ srcRoot }),
    /must be a string literal/i,
  );
});

test('android typography verifier passes AST declaration-level fixture', () => {
  const cssPath = path.join(fixturesRoot, 'android-typography', 'pass', 'app', 'src', 'index.css');
  assert.doesNotThrow(() => verifyAndroidTypographyContract({ cssPath }));
});

test('android typography verifier fails when Roboto/Noto only appear in comments', () => {
  const cssPath = path.join(fixturesRoot, 'android-typography', 'fail-comment-font', 'app', 'src', 'index.css');
  assert.throws(
    () => verifyAndroidTypographyContract({ cssPath }),
    /Roboto/i,
  );
});

test('android scaffold verifier passes canonical fixture', () => {
  const fixtureRepoRoot = path.join(fixturesRoot, 'android-scaffold-contract', 'pass');
  assert.doesNotThrow(() => verifyAndroidScaffoldContract({ repoRoot: fixtureRepoRoot }));
});

test('android scaffold verifier fails when data-mobile-os attribute is missing', () => {
  const fixtureRepoRoot = path.join(fixturesRoot, 'android-scaffold-contract', 'fail-missing-mobile-attr');
  assert.throws(
    () => verifyAndroidScaffoldContract({ repoRoot: fixtureRepoRoot }),
    /data-mobile-os/i,
  );
});

test('android scaffold verifier fails when required markers only appear in comments', () => {
  const fixtureRepoRoot = path.join(fixturesRoot, 'android-scaffold-contract', 'fail-comment-only-markers');
  assert.throws(
    () => verifyAndroidScaffoldContract({ repoRoot: fixtureRepoRoot }),
    /MobilePlatform|data-mobile-os|getMobilePlatform|installMainDocumentRuntime/i,
  );
});

test('android background reliability verifier passes canonical fixture', () => {
  const fixtureRepoRoot = path.join(fixturesRoot, 'android-background-reliability-contract', 'pass');
  assert.doesNotThrow(() => verifyAndroidBackgroundReliabilityContract({ repoRoot: fixtureRepoRoot }));
});

test('android background reliability verifier fails when resume listener is missing', () => {
  const fixtureRepoRoot = path.join(fixturesRoot, 'android-background-reliability-contract', 'fail-missing-resume-listener');
  assert.throws(
    () => verifyAndroidBackgroundReliabilityContract({ repoRoot: fixtureRepoRoot }),
    /resume signal/i,
  );
});

test('android background reliability verifier fails when contract markers only appear in comments', () => {
  const fixtureRepoRoot = path.join(fixturesRoot, 'android-background-reliability-contract', 'fail-comment-only-resume-contract');
  assert.throws(
    () => verifyAndroidBackgroundReliabilityContract({ repoRoot: fixtureRepoRoot }),
    /ANDROID_SUSPEND_RESYNC_GAP_MS|shouldForceAndroidResumeResync|resume signal|scheduleImmediateTick/i,
  );
});
