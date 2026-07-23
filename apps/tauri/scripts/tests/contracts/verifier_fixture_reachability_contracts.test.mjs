import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { verifyDesktopChannelContract } from '../../verify/desktop_channel.mjs';
import { verifyMobileSyncCadenceContract } from '../../verify/mobile_sync_cadence_contract.mjs';
import { verifyModuleContractMatrix } from '../../verify/module_contract_matrix.mjs';
import { verifyPlatformCapabilityMatrixContract } from '../../verify/platform_capability_matrix_contract.mjs';
import { verifySyncBackendAbstractionContract } from '../../verify/sync_backend_abstraction_contract.mjs';
import { verifySyncBackendManualRunnerContract } from '../../verify/sync_backend_manual_runner_contract.mjs';
import { verifySyncBackendProfileContract } from '../../verify/sync_backend_profile_contract.mjs';
import { verifyWindowsCopyContract } from '../../verify/windows_copy_contract.mjs';
import { verifyWindowsTypographyContract } from '../../verify/windows_typography_contract.mjs';
import { verifyUiWiringModuleAstContracts } from '../../lib/ui_wiring_module_ast_contract.mjs';

import { fixturesRoot } from './shared.mjs';

function verifyUiWiringFixture({ repoRoot }) {
  const result = verifyUiWiringModuleAstContracts({ repoRoot });
  const failures = [
    ['settings toggle options', result.missingSettingsOptions],
    ['sidebar visibility guards', result.missingSidebarVisibilityGuards],
    ['main view render branches', result.missingAppRenderBranches],
    ['app module guard mappings', result.missingAppModuleGuardMappings],
  ].filter(([, values]) => values.length > 0);

  if (failures.length > 0) {
    throw new Error(
      failures
        .map(([label, values]) => `missing ${label}: ${values.join(', ')}`)
        .join('; '),
    );
  }

  return result;
}

const VERIFIER_FIXTURE_SUITES = [
  {
    name: 'desktop-channel-contract',
    verify: verifyDesktopChannelContract,
    pass: ['pass'],
    fail: ['fail-nonrust-prepare'],
  },
  {
    name: 'mobile-sync-cadence-contract',
    verify: verifyMobileSyncCadenceContract,
    pass: ['pass'],
    fail: ['fail-comment-events'],
  },
  {
    name: 'module-contract-matrix',
    verify: verifyModuleContractMatrix,
    pass: ['pass'],
    fail: ['fail-comment-settings'],
  },
  {
    name: 'platform-capability-matrix-contract',
    verify: verifyPlatformCapabilityMatrixContract,
    pass: ['pass'],
    fail: ['fail-comment-interface'],
  },
  {
    name: 'sync-backend-abstraction-contract',
    verify: verifySyncBackendAbstractionContract,
    pass: ['pass'],
    fail: ['fail-comment-usage'],
  },
  {
    name: 'sync-backend-manual-runner-contract',
    verify: verifySyncBackendManualRunnerContract,
    pass: ['pass'],
    fail: ['fail-comment-runner', 'fail-direct-transport-runner'],
  },
  {
    name: 'sync-backend-profile-contract',
    verify: verifySyncBackendProfileContract,
    pass: ['pass'],
    fail: ['fail-comment-settings-call'],
  },
  {
    name: 'ui-wiring-module-ast-contract',
    verify: verifyUiWiringFixture,
    pass: ['pass-formatting'],
    fail: [
      'fail-comment-settings',
      'fail-mainview-nonrender-comparisons',
      'fail-sidebar-nonrender-guards',
    ],
  },
  {
    name: 'windows-copy-contract',
    verify: verifyWindowsCopyContract,
    pass: ['pass'],
    fail: ['fail-comment-only-markers', 'fail-missing-locale-key'],
  },
  {
    name: 'windows-typography-contract',
    verify: verifyWindowsTypographyContract,
    pass: ['pass'],
    fail: ['fail-invalid-stack'],
  },
];

const suiteNames = VERIFIER_FIXTURE_SUITES
  .map((suite) => suite.name)
  .sort((left, right) => left.localeCompare(right));

const PLATFORM_STATIC_FIXTURE_SUITES = [
  'android-background-reliability-contract',
  'android-scaffold-contract',
  'android-typography',
  'appselect-contract',
  'platform-contract',
];

const registeredFixtureSuites = [
  ...PLATFORM_STATIC_FIXTURE_SUITES,
  ...suiteNames,
].sort((left, right) => left.localeCompare(right));

function resolveFixture(suiteName, fixtureName) {
  return path.join(fixturesRoot, suiteName, fixtureName);
}

function assertFixtureExists(suiteName, fixtureName) {
  const fixtureRoot = resolveFixture(suiteName, fixtureName);
  assert.equal(
    fs.existsSync(fixtureRoot),
    true,
    `Missing verifier fixture: ${path.relative(fixturesRoot, fixtureRoot)}`,
  );
  return fixtureRoot;
}

test('verifier fixture suites are covered by fixture-backed contract tests', () => {
  const actual = fs
    .readdirSync(fixturesRoot, { withFileTypes: true })
    .filter((entry) => entry.isDirectory())
    .map((entry) => entry.name)
    .sort((left, right) => left.localeCompare(right));

  assert.deepEqual(
    actual,
    registeredFixtureSuites,
    'Every fixture suite must be registered either in platform_static_contracts or in this verifier-backed registry.',
  );
});

for (const suite of VERIFIER_FIXTURE_SUITES) {
  test(`${suite.name} fixture cases are registered`, () => {
    const actual = fs
      .readdirSync(path.join(fixturesRoot, suite.name), { withFileTypes: true })
      .filter((entry) => entry.isDirectory())
      .map((entry) => entry.name)
      .sort((left, right) => left.localeCompare(right));
    const expected = [...suite.pass, ...suite.fail].sort((left, right) => left.localeCompare(right));

    assert.deepEqual(
      actual,
      expected,
      `Every ${suite.name} fixture case must be run by this contract.`,
    );
  });
}

for (const suite of VERIFIER_FIXTURE_SUITES) {
  for (const fixtureName of suite.pass) {
    test(`${suite.name} accepts ${fixtureName}`, () => {
      const repoRoot = assertFixtureExists(suite.name, fixtureName);
      assert.doesNotThrow(() => suite.verify({ repoRoot }));
    });
  }

  for (const fixtureName of suite.fail) {
    test(`${suite.name} rejects ${fixtureName}`, () => {
      const repoRoot = assertFixtureExists(suite.name, fixtureName);
      const error = assert.throws(() => suite.verify({ repoRoot }));
      const message = error instanceof Error ? error.message : String(error);

      assert.doesNotMatch(
        message,
        /ENOENT|missing required file|Missing file/i,
        `Failure fixture ${suite.name}/${fixtureName} should fail the intended contract, not fixture completeness: ${message}`,
      );
    });
  }
}
