#!/usr/bin/env node
/**
 * Audit #2299 + #2984-DC-H10: supply-chain — Cargo.lock byte-stability
 * verifier, parameterized over a list of (manifest, lockfile) tuples.
 *
 * Lorvex carries TWO independent Cargo workspaces:
 *
 *   • Root `Cargo.toml` / `Cargo.lock` — every workspace crate
 *     (lorvex-domain, -store, -sync, -runtime, -cli, mcp-server) and
 *     the bulk of the codebase by line count.
 *
 *   • `app/src-tauri/Cargo.toml` / `Cargo.lock` — the Tauri desktop
 *     binary, intentionally a SEPARATE crate graph because Tauri pins
 *     a specific tauri-build/tauri-codegen toolchain and we don't want
 *     a desktop dependency bump to ripple through the headless logic
 *     crates.
 *
 * Pre-fix this verifier covered only the Tauri lockfile, so a
 * `cargo update` in the workspace root could silently un-lock the bulk
 * of the dependency graph between builds. The aggregated `--locked`
 * call now happens for every entry in `LOCK_TARGETS`.
 *
 * For each entry the script:
 *   1. Snapshots the lockfile bytes and SHA-256.
 *   2. Runs `cargo metadata --locked --manifest-path <toml>`. `--locked`
 *      makes cargo exit non-zero if the lockfile cannot satisfy the
 *      manifest without an update — the drift signal we want.
 *   3. Re-reads the lockfile and refuses to declare success if cargo
 *      silently rewrote it as a side effect.
 *
 * If `cargo` is unavailable on the runner, the verifier skips with a
 * warning so a slim CI image without the Rust toolchain doesn't red-line
 * the aggregate gate. Build runners always have cargo, so the check is
 * authoritative there.
 *
 * CLI:
 *   node scripts/verify/cargo_lockfile_integrity.mjs           → exit 0 clean
 *   node scripts/verify/cargo_lockfile_integrity.mjs --check   → alias
 */
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';

import { resolveRepoRootFromMeta, runVerifierCli } from '../lib/verifier_runtime.mjs';

const SCRIPT_TAG = '[cargo_lockfile_integrity]';
const REPO_ROOT = resolveRepoRootFromMeta(import.meta.url);

/**
 * Every (manifest, lockfile) pair this verifier audits. Add new tuples
 * here when a new Cargo workspace lands in the repo.
 */
const LOCK_TARGETS = [
  {
    label: 'workspace root',
    manifest: 'Cargo.toml',
    lockfile: 'Cargo.lock',
  },
  {
    label: 'tauri app',
    manifest: 'app/src-tauri/Cargo.toml',
    lockfile: 'app/src-tauri/Cargo.lock',
  },
];

const ALLOWED_LOCKFILE_PATHS = new Set(
  LOCK_TARGETS.map((target) => path.resolve(REPO_ROOT, target.lockfile)),
);

function sha256(buf) {
  return crypto.createHash('sha256').update(buf).digest('hex');
}

function rootWorkspaceMembers() {
  const manifestPath = path.join(REPO_ROOT, 'Cargo.toml');
  const manifest = fs.readFileSync(manifestPath, 'utf8');
  const membersMatch = manifest.match(/^\s*members\s*=\s*\[([\s\S]*?)^\s*\]/m);
  if (!membersMatch) {
    throw new Error(`${SCRIPT_TAG} root Cargo.toml is missing a [workspace] members list`);
  }
  return [...membersMatch[1].matchAll(/"([^"]+)"/g)].map((match) => match[1]);
}

function checkNoStaleMemberLockfiles() {
  const staleLockfiles = [];
  for (const member of rootWorkspaceMembers()) {
    const lockfilePath = path.resolve(REPO_ROOT, member, 'Cargo.lock');
    if (fs.existsSync(lockfilePath) && !ALLOWED_LOCKFILE_PATHS.has(lockfilePath)) {
      staleLockfiles.push(path.relative(REPO_ROOT, lockfilePath));
    }
  }

  if (staleLockfiles.length > 0) {
    throw new Error(
      `${SCRIPT_TAG} workspace member lockfiles are stale and outside the audited lock set:\n` +
        staleLockfiles.map((entry) => `  - ${entry}`).join('\n') +
        `\nDelete these member Cargo.lock files; root workspace members are locked by Cargo.lock.`,
    );
  }
}

function cargoAvailable() {
  const r = spawnSync('cargo', ['--version'], { stdio: 'ignore' });
  return r.status === 0;
}

function checkOne({ label, manifest, lockfile }) {
  const manifestPath = path.join(REPO_ROOT, manifest);
  const lockfilePath = path.join(REPO_ROOT, lockfile);

  if (!fs.existsSync(manifestPath)) {
    throw new Error(`${SCRIPT_TAG} (${label}) missing manifest: ${manifest}`);
  }
  if (!fs.existsSync(lockfilePath)) {
    throw new Error(`${SCRIPT_TAG} (${label}) missing lockfile: ${lockfile}`);
  }

  const before = fs.readFileSync(lockfilePath);
  const beforeHash = sha256(before);

  // `cargo metadata --locked` re-reads the manifest and re-resolves the
  // dep graph from the committed Cargo.lock. `--locked` makes cargo
  // exit non-zero if the lockfile cannot satisfy the manifest without
  // an update — that's exactly the drift we want to catch. Unlike
  // `generate-lockfile`, it never rewrites the lockfile on disk, so
  // the working tree stays clean.
  //
  // `--offline` is NOT passed: the first-time run on a fresh machine
  // needs to fetch the crate index to validate the graph. Subsequent
  // runs hit the cache and are fast.
  const result = spawnSync(
    'cargo',
    [
      'metadata',
      '--locked',
      '--format-version',
      '1',
      '--manifest-path',
      manifestPath,
    ],
    {
      encoding: 'utf8',
      // `cargo metadata` emits the full resolved dep graph as JSON. For
      // Lorvex's two graphs that's several MB. Node's default
      // `maxBuffer` (1 MB) would truncate and fail with ENOBUFS, which
      // we'd misreport as lockfile drift. Allocate plenty of headroom.
      maxBuffer: 64 * 1024 * 1024,
    },
  );

  if (result.status !== 0) {
    const stderr = (result.stderr || '').trim();
    throw new Error(
      `${SCRIPT_TAG} (${label}) cargo metadata --locked failed — Cargo.lock drift detected.\n` +
        `Fix options:\n` +
        `  1. Inspect which pin is unsatisfiable: cargo update --manifest-path ${manifest} --dry-run\n` +
        `  2. Commit the refreshed lockfile after running: cargo update --manifest-path ${manifest}\n` +
        `cargo stderr:\n${stderr}`,
    );
  }

  // Belt-and-braces: a future cargo version could in principle touch
  // Cargo.lock formatting as a side-effect of `metadata`. Catch any
  // such silent rewrite.
  const after = fs.readFileSync(lockfilePath);
  const afterHash = sha256(after);

  if (beforeHash !== afterHash) {
    fs.writeFileSync(lockfilePath, before);
    throw new Error(
      `${SCRIPT_TAG} (${label}) Cargo.lock was rewritten by cargo metadata --locked.\n` +
        `  before sha256: ${beforeHash}\n` +
        `  after  sha256: ${afterHash}\n` +
        `The committed lockfile is not byte-stable. Regenerate and commit.`,
    );
  }

  console.log(`${SCRIPT_TAG} (${label}) ${lockfile} byte-stable under --locked.`);
}

/**
 * Audit #3005 L1: shared-crate version drift between the two Cargo
 * lockfiles.
 *
 * The workspace root and `app/src-tauri` are intentionally separate
 * crate graphs, but they share a long tail of foundational crates
 * (`tokio`, `serde`, `chrono`, `rusqlite`, `uuid`, ...). When those
 * pin to different versions across the two lockfiles — as happened
 * with `tokio 1.50.0` vs `1.51.1` on the day this check landed — a
 * security advisory only patched in one tree leaves the other
 * exposed, and runtime behaviours that depend on cross-crate
 * compatibility (timer wheel layout, panic propagation, channel
 * fairness) silently differ between the desktop binary and the
 * headless logic crates.
 *
 * The allowlist below names crates that we knowingly accept drift
 * for, with the reason. Anything else that diverges fails the check
 * with a precise, actionable error.
 */
const SHARED_CRATE_DRIFT_ALLOWLIST = new Map([
  // Tauri pins its own derive-macro / runtime / build trio; bumping
  // them in lockstep with the workspace root would force the desktop
  // binary onto an untested Tauri toolchain.
  ['tauri', 'pinned by app/src-tauri/Cargo.toml; not used by workspace crates'],
  ['tauri-build', 'pinned by app/src-tauri/Cargo.toml; build-time only'],
  ['tauri-codegen', 'pinned by app/src-tauri/Cargo.toml; codegen only'],
  ['tauri-macros', 'pinned by app/src-tauri/Cargo.toml; proc-macro only'],
  ['tauri-utils', 'pinned by tauri itself; not in workspace dep tree'],
  ['tauri-runtime', 'pinned by tauri itself; not in workspace dep tree'],
  ['tauri-runtime-wry', 'pinned by tauri itself; not in workspace dep tree'],
  ['tauri-plugin', 'pinned by tauri-plugin crates'],
  // Pre-existing drift snapshot at the time the cross-lockfile drift
  // check landed (audit #3005 L1, 2026-04-28). Each entry below is a
  // transitive crate whose version is dictated by an upstream
  // dependency that pins differently in the two graphs (Tauri's
  // 2.x bundle pins older `mio`/`rand`/`toml_edit` etc.; the
  // workspace `cargo update` cadence advances independently). They
  // are recorded here rather than auto-equalised because forcing
  // alignment would require yanking and re-pinning a transitive
  // dependency — strictly worse than the drift itself.
  //
  // The allowlist exists so NEW drift (e.g. a fresh `serde_json`
  // bump in only one tree) trips the gate; tightening it further
  // means landing a coordinated upstream-tracker bump and removing
  // the entry in the same change.
  ['cc', 'pre-existing drift snapshot — transitive build-script crate'],
  ['darling', 'pre-existing drift snapshot — schemars_derive pins older'],
  ['darling_core', 'pre-existing drift snapshot — follows darling'],
  ['darling_macro', 'pre-existing drift snapshot — follows darling'],
  ['itoa', 'pre-existing drift snapshot — transitive serde dep'],
  ['libc', 'pre-existing drift snapshot — patch-level'],
  ['mio', 'pre-existing drift snapshot — Tauri tree carries mio 0.8 + 1.1, workspace on 1.2'],
  ['quick-error', 'transitive major split — workspace proptest/rusty-fork pins 1.x while Tauri image/tiff pins 2.x'],
  ['quote', 'pre-existing drift snapshot — proc-macro dep, patch-level'],
  ['schemars_derive', 'pre-existing drift snapshot — old schemars in Tauri tree'],
  ['tokio', 'pre-existing drift snapshot — workspace 1.51, Tauri tree 1.50; advance Tauri tree to align'],
  ['toml', 'pre-existing drift snapshot — Tauri tree spans toml 0.8/0.9'],
  ['toml_datetime', 'pre-existing drift snapshot — follows toml'],
  ['toml_edit', 'pre-existing drift snapshot — Tauri tree spans toml_edit 0.19/0.20/0.23'],
  ['uuid', 'pre-existing drift snapshot — patch-level'],
  ['winnow', 'pre-existing drift snapshot — follows toml_edit'],
  ['zerocopy', 'pre-existing drift snapshot — patch-level'],
  ['zerocopy-derive', 'pre-existing drift snapshot — follows zerocopy'],
]);

function parseLockfilePackages(lockfilePath) {
  const text = fs.readFileSync(lockfilePath, 'utf8');
  // `Cargo.lock` is TOML; rather than pulling in a TOML parser we
  // walk the `[[package]]` blocks because we only need the
  // `name = "..."` and `version = "..."` lines per block — the rest
  // (source, checksum, dependencies) is irrelevant to drift
  // detection.
  const blocks = text.split(/^\[\[package\]\]\s*$/m).slice(1);
  const map = new Map();
  for (const block of blocks) {
    const nameMatch = block.match(/^name\s*=\s*"([^"]+)"/m);
    const versionMatch = block.match(/^version\s*=\s*"([^"]+)"/m);
    if (!nameMatch || !versionMatch) continue;
    const name = nameMatch[1];
    const version = versionMatch[1];
    // A single name can legitimately appear at multiple major versions
    // (e.g. `windows-sys 0.48`/`0.59`). Track the full set per name so
    // the drift check compares like-for-like across both lockfiles.
    if (!map.has(name)) map.set(name, new Set());
    map.get(name).add(version);
  }
  return map;
}

function checkSharedCrateDrift() {
  const labelToPackages = new Map();
  for (const target of LOCK_TARGETS) {
    const lockfilePath = path.join(REPO_ROOT, target.lockfile);
    if (!fs.existsSync(lockfilePath)) continue;
    labelToPackages.set(target.label, parseLockfilePackages(lockfilePath));
  }

  if (labelToPackages.size < 2) {
    // Nothing to compare against; the per-target byte-stability check
    // is still authoritative.
    return;
  }

  const labels = [...labelToPackages.keys()];
  const reference = labelToPackages.get(labels[0]);
  const drift = [];

  for (const [name, versionsA] of reference) {
    if (SHARED_CRATE_DRIFT_ALLOWLIST.has(name)) continue;
    for (let i = 1; i < labels.length; i += 1) {
      const versionsB = labelToPackages.get(labels[i]).get(name);
      if (!versionsB) continue;
      // Drift means: the same crate name resolves to a *disjoint*
      // version set in the other lockfile. Two graphs that both pin
      // `windows-sys` to `{0.48, 0.59}` are fine. One graph at `0.48`
      // and the other at `0.59` is drift.
      const setA = [...versionsA].sort();
      const setB = [...versionsB].sort();
      const overlap = setA.some((v) => versionsB.has(v));
      if (!overlap) {
        drift.push({
          name,
          [labels[0]]: setA,
          [labels[i]]: setB,
        });
      }
    }
  }

  if (drift.length > 0) {
    const summary = drift
      .map((row) => {
        const label0 = labels[0];
        const labelN = labels.find((l) => l !== label0 && Array.isArray(row[l]));
        return `  • ${row.name}: ${label0}=${row[label0].join(',')} ↔ ${labelN}=${row[labelN].join(',')}`;
      })
      .join('\n');
    throw new Error(
      `${SCRIPT_TAG} shared-crate version drift between Cargo.lock files (audit #3005 L1):\n${summary}\n\n` +
        `Resolution options:\n` +
        `  1. Run \`cargo update -p <crate>\` in the lagging workspace and commit the refreshed lockfile.\n` +
        `  2. If the drift is intentional (e.g. one tree pins to avoid a regression), add the crate to\n` +
        `     SHARED_CRATE_DRIFT_ALLOWLIST in scripts/verify/cargo_lockfile_integrity.mjs with a reason.\n`,
    );
  }

  console.log(
    `${SCRIPT_TAG} shared-crate versions are aligned across ${labels.length} lockfile(s).`,
  );
}

function run() {
  checkNoStaleMemberLockfiles();

  if (!cargoAvailable()) {
    // turn the silent-skip into a hard fail. The aggregate
    // `verify:repo-governance` bundle includes this verifier as a
    // leaf, so a CI runner without the Rust toolchain would
    // advertise "all governance checks passed" while skipping
    // lockfile drift entirely. The opt-out env var below preserves
    // the documented "trimmed CI image" path but makes that path
    // explicit instead of accidental (audit-pass-docs-finding-10).
    if (process.env.LORVEX_VERIFY_ALLOW_NO_CARGO === '1') {
      console.warn(
        `${SCRIPT_TAG} cargo not available; skipping all lockfile checks ` +
          `(LORVEX_VERIFY_ALLOW_NO_CARGO=1 was set).`,
      );
      return;
    }
    console.error(
      `${SCRIPT_TAG} cargo not available — refusing to skip lockfile ` +
        `integrity check. This verifier is a leaf in the ` +
        `verify:repo-governance bundle and must run on a host with the ` +
        `Rust toolchain installed. To explicitly opt out (e.g. trimmed ` +
        `CI image), set LORVEX_VERIFY_ALLOW_NO_CARGO=1.`,
    );
    process.exit(1);
  }
  for (const target of LOCK_TARGETS) {
    checkOne(target);
  }
  checkSharedCrateDrift();
}

runVerifierCli({
  scriptTag: SCRIPT_TAG,
  successMessage: `Cargo.lock byte-stability verified across ${LOCK_TARGETS.length} workspace(s).`,
  run,
});
