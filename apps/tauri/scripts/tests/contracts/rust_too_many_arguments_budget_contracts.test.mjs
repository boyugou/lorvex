import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import test from 'node:test';

import {
  collectTooManyArgumentsAllowances,
  verifyTooManyArgumentsBudget,
} from '../../verify/rust_too_many_arguments_budget.mjs';
import { displayCommand, flattenBundle } from '../../verify/verification_manifest.mjs';
import { repoRoot } from './shared.mjs';

test('rust too_many_arguments allowance budget is enforced by repo governance', () => {
  const packageJson = JSON.parse(fs.readFileSync(path.join(repoRoot, 'package.json'), 'utf8'));
  const verifierPath = path.join(repoRoot, 'scripts/verify/rust_too_many_arguments_budget.mjs');
  const repoGovernanceCommands = flattenBundle('verify:repo-governance').map(displayCommand);

  assert.equal(
    packageJson.scripts['verify:rust-too-many-arguments-budget'],
    'node scripts/verify/rust_too_many_arguments_budget.mjs',
    'package.json should expose the Rust too_many_arguments budget verifier',
  );
  assert.equal(fs.existsSync(verifierPath), true, 'repo should provide the Rust too_many_arguments budget verifier');
  assert.equal(
    repoGovernanceCommands.includes('npm run verify:rust-too-many-arguments-budget'),
    true,
    'repo governance should run the Rust too_many_arguments budget verifier',
  );
});

test('rust too_many_arguments allowance budget passes for the canonical repo', () => {
  const result = spawnSync(process.execPath, ['scripts/verify/rust_too_many_arguments_budget.mjs'], {
    cwd: repoRoot,
    encoding: 'utf8',
  });

  assert.equal(result.status, 0, `stdout:\n${result.stdout}\nstderr:\n${result.stderr}`);
  assert.match(result.stdout, /tracked \d+ allowances/);
});

test('rust too_many_arguments allowance scanner catches non-canonical suppression shapes', () => {
  const fixtureRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'lorvex-too-many-args-'));
  try {
    fs.mkdirSync(path.join(fixtureRoot, 'src'), { recursive: true });
    fs.writeFileSync(
      path.join(fixtureRoot, 'src', 'lib.rs'),
      `
#![allow(clippy::too_many_arguments)]

#[allow(dead_code, clippy :: too_many_arguments)]
fn combined(a: i64, b: i64, c: i64, d: i64, e: i64, f: i64, g: i64, h: i64) {}

#[allow(
    clippy::too_many_arguments,
    clippy::needless_pass_by_value,
)]
fn multiline(a: i64, b: i64, c: i64, d: i64, e: i64, f: i64, g: i64, h: i64) {}

#[cfg_attr(feature = "wide", allow(clippy::too_many_arguments))]
fn cfg_attr_suppression(a: i64, b: i64, c: i64, d: i64, e: i64, f: i64, g: i64, h: i64) {}

#[cfg_attr(feature = "strict", deny(clippy::too_many_arguments), allow(dead_code))]
fn cfg_attr_deny_with_unrelated_allow(a: i64, b: i64, c: i64, d: i64, e: i64, f: i64, g: i64, h: i64) {}

#[expect(clippy::too_many_arguments)]
fn expect_suppression(a: i64, b: i64, c: i64, d: i64, e: i64, f: i64, g: i64, h: i64) {}

#[deny(clippy::too_many_arguments)]
fn deny_is_not_suppression(a: i64, b: i64, c: i64, d: i64, e: i64, f: i64, g: i64, h: i64) {}
`,
    );

    const allowances = collectTooManyArgumentsAllowances(fixtureRoot);
    assert.deepEqual(
      allowances.map((entry) => `${entry.path}::${entry.symbol}`),
      [
        'src/lib.rs::<file>',
        'src/lib.rs::cfg_attr_suppression',
        'src/lib.rs::combined',
        'src/lib.rs::expect_suppression',
        'src/lib.rs::multiline',
      ],
    );
    assert.throws(
      () => verifyTooManyArgumentsBudget({ repoRoot: fixtureRoot, budget: [] }),
      /Unbudgeted too_many_arguments allowances/,
    );
  } finally {
    fs.rmSync(fixtureRoot, { recursive: true, force: true });
  }
});
