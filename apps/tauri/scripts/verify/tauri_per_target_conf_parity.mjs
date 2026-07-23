#!/usr/bin/env node

// Issue #3337: `tauri.linux.conf.json` and `tauri.windows.conf.json`
// currently carry byte-identical overlay payloads — both reset the
// macOS-only window chrome (titleBarStyle / hiddenTitle / decorations
// / trafficLightPosition) so the base `tauri.conf.json` doesn't ship
// macOS-specific traffic-light positioning to Linux/Windows builds.
//
// Tauri 2's per-target overlay merges by REPLACEMENT (see
// `verify:platform-csp-inheritance`); there is no native "inherit
// from sibling" keyword, and Tauri requires per-OS files at fixed
// paths so the build pipeline can resolve them. Generating one from
// the other (option b) would add a build step and tooling surface
// for what is effectively a parity assertion. The cleanest option is
// (c): keep both files (as the build pipeline expects) and fail CI
// the moment they drift unintentionally.
//
// To intentionally diverge, delete this gate or update the marker
// file `app/src-tauri/tauri.per-target-conf-divergence.allowed`
// (any non-empty file at that path is taken as an explicit override
// and the script becomes a no-op until it is removed).

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const SCRIPT_TAG = '[verify:tauri-per-target-conf-parity]';

function resolveRepoRoot() {
  const scriptPath = fileURLToPath(import.meta.url);
  return path.resolve(path.dirname(scriptPath), '..', '..');
}

function fail(message) {
  throw new Error(`${SCRIPT_TAG} ${message}`);
}

export function verifyTauriPerTargetConfParity({ repoRoot = resolveRepoRoot() } = {}) {
  const tauriDir = path.join(repoRoot, 'app', 'src-tauri');
  const overrideMarker = path.join(tauriDir, 'tauri.per-target-conf-divergence.allowed');
  if (fs.existsSync(overrideMarker) && fs.readFileSync(overrideMarker, 'utf8').trim().length > 0) {
    return { ok: true, skipped: true };
  }

  const linuxPath = path.join(tauriDir, 'tauri.linux.conf.json');
  const windowsPath = path.join(tauriDir, 'tauri.windows.conf.json');

  if (!fs.existsSync(linuxPath) || !fs.existsSync(windowsPath)) {
    // If either has been removed, the parity assertion is vacuous —
    // a follow-up audit should re-establish whether the remaining file
    // still serves its purpose. Don't fail CI on a deliberate deletion.
    return { ok: true, skipped: true };
  }

  const linux = fs.readFileSync(linuxPath, 'utf8');
  const windows = fs.readFileSync(windowsPath, 'utf8');

  if (linux !== windows) {
    fail(
      'tauri.linux.conf.json and tauri.windows.conf.json have diverged. '
        + 'These two overlays must remain byte-identical until divergence is intentional. '
        + 'If you intend to diverge, write a non-empty marker file at '
        + 'app/src-tauri/tauri.per-target-conf-divergence.allowed (one line per file documenting why) '
        + 'and re-run this gate. See issue #3337.',
    );
  }

  return { ok: true };
}

function runCli() {
  try {
    const result = verifyTauriPerTargetConfParity();
    if (result.skipped) {
      console.log(`${SCRIPT_TAG} skipped (override marker present or one overlay missing).`);
    } else {
      console.log(`${SCRIPT_TAG} per-target Tauri overlay parity check passed.`);
    }
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error(message.startsWith(SCRIPT_TAG) ? message : `${SCRIPT_TAG} ${message}`);
    process.exit(1);
  }
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  runCli();
}
