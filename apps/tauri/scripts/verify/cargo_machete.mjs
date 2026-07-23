#!/usr/bin/env node
/**
 * Cargo unused-dependency gate.
 *
 * `cargo machete --with-metadata` catches stale entries in Cargo.toml
 * that `cargo check` and Clippy do not report. The root workspace
 * excludes `app/src-tauri`, so this verifier runs both workspaces
 * explicitly. Local developer checkouts may skip when cargo-machete
 * is unavailable, but GitHub Actions must fail closed so the
 * canonical static gate cannot pass unless CI installed the tool it
 * is claiming to run.
 */
import { spawnSync } from 'node:child_process';
import path from 'node:path';

import { resolveRepoRootFromMeta, runVerifierCli } from '../lib/verifier_runtime.mjs';

const SCRIPT_TAG = '[cargo_machete]';
const REPO_ROOT = resolveRepoRootFromMeta(import.meta.url);
const CHECKS = [
  {
    label: 'root workspace',
    cwd: REPO_ROOT,
  },
  {
    label: 'Tauri backend',
    cwd: path.join(REPO_ROOT, 'app', 'src-tauri'),
  },
];

function cargoMacheteAvailable() {
  const result = spawnSync('cargo', ['machete', '--version'], { stdio: 'ignore' });
  return result.status === 0;
}

function run() {
  if (!cargoMacheteAvailable()) {
    if (process.env.GITHUB_ACTIONS === 'true') {
      throw new Error(
        `${SCRIPT_TAG} cargo machete is required in GitHub Actions; install cargo-machete before running verify:cargo-machete.`,
      );
    }
    console.warn(
      `${SCRIPT_TAG} cargo machete not available locally; skipping. Install it with ` +
        '`cargo install cargo-machete --locked --version =0.9.2` to run this gate before CI.',
    );
    process.exit(0);
  }

  for (const check of CHECKS) {
    console.log(`${SCRIPT_TAG} checking ${check.label} with cargo machete --with-metadata`);
    const result = spawnSync('cargo', ['machete', '--with-metadata'], {
      cwd: check.cwd,
      stdio: 'inherit',
    });

    if (result.error) {
      throw new Error(
        `${SCRIPT_TAG} failed to invoke ${check.label} cargo machete --with-metadata: ${result.error.message}`,
      );
    }
    if (result.signal) {
      throw new Error(
        `${SCRIPT_TAG} ${check.label} cargo machete --with-metadata terminated with signal ${result.signal}.`,
      );
    }
    if (typeof result.status === 'number' && result.status !== 0) {
      throw new Error(
        `${SCRIPT_TAG} ${check.label} cargo machete --with-metadata found unused Cargo dependencies.\n` +
          'Delete stale Cargo.toml entries, or add [package.metadata.cargo-machete] ' +
          'ignored = ["crate-name"] with a nearby comment explaining the false positive.',
      );
    }
  }
}

runVerifierCli({
  scriptTag: SCRIPT_TAG,
  successMessage: 'Root workspace and Tauri backend cargo machete checks reported no unused Cargo dependencies.',
  run,
});
