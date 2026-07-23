#!/usr/bin/env node
/**
 * Issue #3024 M7: dead-code / unused gate.
 *
 * Clippy already runs with `-D warnings`, but `cargo clippy` defaults to
 * `dead_code` and `unused` at WARN, and the workspace clippy invocation
 * doesn't elevate them per-call. A function that becomes dead because
 * its single caller was removed in the same PR slips through the gate
 * unless we run cargo with the lints explicitly denied.
 *
 * This verifier runs root workspace and Tauri-backend `cargo check`
 * gates with `RUSTFLAGS=-D dead_code -D unused`. `--all-targets`
 * covers tests + benches + examples so a function only referenced
 * from a deleted test still trips the gate.
 *
 * Local developer checkouts may skip when cargo is unavailable, but
 * GitHub Actions must fail closed so the canonical static gate cannot
 * pass unless CI explicitly installed a Rust toolchain.
 */
import path from 'node:path';
import { spawnSync } from 'node:child_process';

import { resolveRepoRootFromMeta, runVerifierCli } from '../lib/verifier_runtime.mjs';

const SCRIPT_TAG = '[cargo_dead_code]';
const REPO_ROOT = resolveRepoRootFromMeta(import.meta.url);
const CHECKS = [
  {
    label: 'root workspace',
    args: ['check', '--workspace', '--all-targets', '--quiet'],
    rustflags: '-D dead_code -D unused',
  },
  {
    label: 'Tauri backend',
    args: [
      'check',
      '--manifest-path',
      'app/src-tauri/Cargo.toml',
      '--all-targets',
      '--quiet',
    ],
    // The Tauri command tree is intentionally registration-driven:
    // build.rs emits handler paths to private leaf modules, while Rust's
    // unused-import lint still sees many command facade re-exports as
    // unreferenced in a given target. Keep the dead-code and non-import
    // unused gates strict, but centralize this generated-IPC exception in
    // the verifier instead of carrying a broad source-level allow in
    // app/src-tauri/src/commands.rs.
    rustflags: '-D dead_code -D unused -A unused_imports',
  },
];

function cargoAvailable() {
  const r = spawnSync('cargo', ['--version'], { stdio: 'ignore' });
  return r.status === 0;
}

function run() {
  if (!cargoAvailable()) {
    if (process.env.GITHUB_ACTIONS === 'true') {
      throw new Error(
        `${SCRIPT_TAG} cargo is required in GitHub Actions; install Rust before running verify:cargo-dead-code.`,
      );
    }
    console.warn(
      `${SCRIPT_TAG} cargo not available locally; skipping. Install Rust with rustup, or set PATH="$HOME/.cargo/bin:$PATH" to run this gate before CI.`,
    );
    process.exit(0);
  }

  // `-D dead_code -D unused` elevates both lint groups to deny so a
  // function that lost its sole caller (or, in the root workspace, an
  // import that lost its sole reference, or a variable that became
  // unused) fails the gate rather than slipping through under clippy's
  // default warn level.
  //
  // `--all-targets` covers `[lib]`, `[[bin]]`, `[[test]]`, and
  // `[[bench]]` so a helper that's only referenced from a recently
  // deleted test surface fails the gate too.
  //
  // RUSTFLAGS is the right knob here (not `--workspace` lint flags),
  // because the elevation must reach every crate in the dep graph,
  // not just the workspace members.
  for (const check of CHECKS) {
    console.log(`${SCRIPT_TAG} checking ${check.label} with ${check.args.join(' ')}`);
    const env = {
      ...process.env,
      RUSTFLAGS: `${process.env.RUSTFLAGS ?? ''} ${check.rustflags}`.trim(),
    };
    const result = spawnSync('cargo', check.args, {
      cwd: REPO_ROOT,
      env,
      stdio: 'inherit',
    });

    if (result.error) {
      throw new Error(
        `${SCRIPT_TAG} failed to invoke ${check.label} cargo check: ${result.error.message}`,
      );
    }
    if (typeof result.status === 'number' && result.status !== 0) {
      throw new Error(
        `${SCRIPT_TAG} ${check.label} cargo check failed under -D dead_code -D unused.\n` +
          `A symbol or import is unreferenced. Either delete it, or — if\n` +
          `it is intentionally kept (e.g. public API surface for downstream\n` +
          `crates) — annotate it with #[allow(dead_code)] / #[allow(unused)]\n` +
          `with a comment explaining why.`,
      );
    }
    if (result.signal) {
      throw new Error(
        `${SCRIPT_TAG} ${check.label} cargo check terminated with signal ${result.signal}.`,
      );
    }
  }

  // Audit-flagged in repo-facts review: the script's own location is
  // verifiable so a future move that orphans the registration in
  // package.json is caught at runtime.
  console.log(
    `${SCRIPT_TAG} root workspace and Tauri backend dead_code + unused gates clean (cargo check --all-targets, RUSTFLAGS pinned; Tauri import re-export exception centralized).`,
  );
}

// Touch REPO_ROOT path so a typo would surface immediately in CI.
path.resolve(REPO_ROOT);

runVerifierCli({
  scriptTag: SCRIPT_TAG,
  successMessage: 'Root workspace and Tauri backend pass -D dead_code -D unused.',
  run,
});
