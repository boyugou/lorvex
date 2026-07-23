import assert from 'node:assert/strict';
import { existsSync } from 'node:fs';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { hasRustUseReexport, repoRoot, rustModuleDeclarationPattern } from './shared.mjs';

test('data_snapshot is organized as a thin facade over store-level zip export/import', () => {
  const rootSource = fs.readFileSync(
    path.join(repoRoot, 'app/src-tauri/src/commands/data/snapshot.rs'),
    'utf8',
  );
  const exportSource = fs.readFileSync(
    path.join(repoRoot, 'app/src-tauri/src/commands/data/snapshot/export.rs'),
    'utf8',
  );
  const importSource = fs.readFileSync(
    path.join(repoRoot, 'app/src-tauri/src/commands/data/snapshot/import.rs'),
    'utf8',
  );

  for (const moduleName of ['export', 'import']) {
    assert.match(
      rootSource,
      rustModuleDeclarationPattern(moduleName),
      `data_snapshot root should register ${moduleName}.rs`,
    );
  }

  assert.equal(
    hasRustUseReexport(rootSource, {
      modulePath: 'export',
      symbols: ['export_data_snapshot'],
    }),
    true,
    'data_snapshot root should re-export export_data_snapshot from export.rs',
  );
  assert.equal(
    hasRustUseReexport(rootSource, {
      modulePath: 'import',
      symbols: ['import_data_snapshot'],
    }),
    true,
    'data_snapshot root should re-export import_data_snapshot from import.rs',
  );
  assert.doesNotMatch(rootSource, rustModuleDeclarationPattern('reset'));
  assert.doesNotMatch(rootSource, /^pub use reset::/m);
  assert.doesNotMatch(
    rootSource,
    /\n#\[tauri::command\]\npub fn export_data_snapshot\(|\n#\[tauri::command\]\npub fn import_data_snapshot\(/,
    'data_snapshot root should stay a re-export facade instead of inlining command bodies',
  );

  assert.match(exportSource, /\n#\[tauri::command\]\npub fn export_data_snapshot\(/);
  assert.match(exportSource, /lorvex_store::export_to_zip/);
  assert.match(importSource, /\n#\[tauri::command\]\npub fn import_data_snapshot\(/);
  assert.match(importSource, /lorvex_store::import_from_zip/);
  assert.match(importSource, /event_bus::emit_data_changed\(event_bus::Entity::DataImport\)/);
  assert.ok(
    !existsSync(path.join(repoRoot, 'app/src-tauri/src/commands/data/snapshot/import/mod.rs')),
    'data_snapshot import should not keep the old nested app-side import fanout once store owns zip import mechanics',
  );
});
