import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

function readRustTree(relativeDir) {
  const dir = path.join(repoRoot, relativeDir);
  const entries = fs.readdirSync(dir, { withFileTypes: true });
  return entries.flatMap((entry) => {
    const relativePath = path.join(relativeDir, entry.name);
    if (entry.isDirectory()) return readRustTree(relativePath);
    if (!entry.isFile() || !entry.name.endsWith('.rs')) return [];
    return [{
      relativePath,
      source: fs.readFileSync(path.join(repoRoot, relativePath), 'utf8'),
    }];
  });
}

test('app invariants are organized as a folder-backed subsystem with the dependencies + validation modules', () => {
  const rootSource = fs.readFileSync(
    path.join(repoRoot, 'app/src-tauri/src/invariants.rs'),
    'utf8',
  );

  // `validation` is exposed as a submodule (callers reach it via
  // `crate::invariants::validation::*`) rather than re-exported flat.
  assert.match(
    rootSource,
    /^pub mod validation;$/m,
    'invariants root should re-expose validation as a submodule',
  );

  // The `dependencies` submodule was retired once `propagate_deps` was
  // proven to be a no-op stub on the Tauri surface — dependency
  // propagation is owned by lorvex-workflow now, and the Tauri
  // invariants tree no longer carries an app-side helper.
  assert.doesNotMatch(
    rootSource,
    /^mod dependencies;$/m,
    'invariants root should not declare a dependencies module after the propagate_deps stub removal',
  );
  assert.equal(
    fs.existsSync(path.join(repoRoot, 'app/src-tauri/src/invariants/dependencies')),
    false,
    'app/src-tauri/src/invariants/dependencies/ should not exist after the propagate_deps stub removal',
  );

  // urgency module was removed (#1515) — verify it is no longer declared
  assert.doesNotMatch(
    rootSource,
    /^mod urgency;$/m,
    'invariants root should not declare urgency module after removal',
  );
  assert.doesNotMatch(
    rootSource,
    /pub use urgency::compute_urgency_score/,
    'invariants root should not re-export urgency helpers after removal',
  );

  // change_tracking submodule was removed once `log_change` was
  // proven to be a no-op stub on the Tauri surface (Tauri does not
  // write `ai_changelog`; that table is reserved for AI/MCP). The
  // contract pins the new posture so a future refactor cannot
  // re-introduce the misleading helper without explicit intent.
  assert.doesNotMatch(
    rootSource,
    /^mod change_tracking;$/m,
    'invariants root should not declare a change_tracking module — Tauri does not author ai_changelog',
  );
  assert.doesNotMatch(
    rootSource,
    /pub use change_tracking::log_change/,
    'invariants root should not re-export log_change after the no-op stub removal',
  );
  assert.equal(
    fs.existsSync(path.join(repoRoot, 'app/src-tauri/src/invariants/change_tracking.rs')),
    false,
    'app/src-tauri/src/invariants/change_tracking.rs should not exist after removal',
  );

  assert.doesNotMatch(
    rootSource,
    /\npub fn log_change\(|\npub fn propagate_deps\(|\nfn add_to_json_array_column\(/,
    'invariants root should stay a composition root after module extraction',
  );
});

test('tauri sync-admin code writes diagnostics instead of ai_changelog rows', () => {
  const syncCommandFiles = readRustTree('app/src-tauri/src/commands/sync');
  const archiveLifecycleFiles = readRustTree('app/src-tauri/src/commands/tasks/lifecycle/archive');
  for (const { relativePath, source } of [...syncCommandFiles, ...archiveLifecycleFiles]) {
    assert.doesNotMatch(
      source,
      /INSERT\s+INTO\s+ai_changelog/i,
      `${relativePath} must not directly insert app-originated sync-admin rows into ai_changelog`,
    );
  }
});
