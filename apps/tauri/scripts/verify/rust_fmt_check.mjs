#!/usr/bin/env node

// Audit #2329: gate Rust format drift at the verify chain so local
// developers catch `cargo fmt --check` failures before push, not
// after CI. Previously only CI ran fmt, and `verify:repo-governance`
// didn't invoke it at all.
//
// Runs `cargo fmt --all -- --check` against the root workspace. If
// `cargo fmt` is not installed (e.g. a slim CI image), skip with a
// warning rather than fail — the goal is enforcement for contributors
// who have a normal toolchain, not to block unusual environments.

import { spawnSync } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const scriptPath = fileURLToPath(import.meta.url);
const repoRoot = path.resolve(path.dirname(scriptPath), '..', '..');

function fail(message) {
  console.error(`[verify:rust-fmt] ${message}`);
  process.exit(1);
}

const which = spawnSync('cargo', ['fmt', '--version'], { stdio: 'ignore' });
if (which.status !== 0) {
  console.warn('[verify:rust-fmt] cargo fmt not available; skipping.');
  process.exit(0);
}

const result = spawnSync('cargo', ['fmt', '--all', '--', '--check'], {
  cwd: repoRoot,
  stdio: 'inherit',
});
if (result.error) {
  fail(`failed to invoke cargo fmt: ${result.error.message}`);
}
if (typeof result.status === 'number' && result.status !== 0) {
  fail('Rust files have format drift. Run `cargo fmt --all` to fix.');
}

// Also run fmt on app/src-tauri, which is excluded from the workspace
// but still a Rust crate we ship. Skip if its manifest is missing
// (fresh clone without the Tauri subtree).
import fs from 'node:fs';
const srcTauriManifest = path.join(repoRoot, 'app', 'src-tauri', 'Cargo.toml');
if (fs.existsSync(srcTauriManifest)) {
  const tauriResult = spawnSync(
    'cargo',
    ['fmt', '--manifest-path', srcTauriManifest, '--', '--check'],
    { cwd: repoRoot, stdio: 'inherit' },
  );
  if (typeof tauriResult.status === 'number' && tauriResult.status !== 0) {
    fail('Rust files in app/src-tauri have format drift. Run `cargo fmt --manifest-path app/src-tauri/Cargo.toml` to fix.');
  }
}

console.log('[verify:rust-fmt] OK');
