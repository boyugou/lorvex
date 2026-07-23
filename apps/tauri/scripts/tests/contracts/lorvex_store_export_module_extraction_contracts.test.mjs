import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

const exportDir = path.join(repoRoot, 'lorvex-store/src/export');

test('lorvex-store export root stays a thin facade over focused modules', () => {
  const modSource = fs.readFileSync(path.join(exportDir, 'mod.rs'), 'utf8');

  // Enumerate every submodule under `export/` whether it lives as a single
  // `<name>.rs` file or as a `<name>/mod.rs` directory module. The original
  // contract only inspected `.rs` files; that quietly broke when `dataset.rs`
  // was promoted to a directory module without anyone noticing the gate had
  // gone red.
  const moduleNames = fs
    .readdirSync(exportDir, { withFileTypes: true })
    .flatMap((entry) => {
      if (entry.isFile() && entry.name.endsWith('.rs') && entry.name !== 'mod.rs') {
        return [entry.name.slice(0, -3)];
      }
      if (
        entry.isDirectory()
        && fs.existsSync(path.join(exportDir, entry.name, 'mod.rs'))
      ) {
        return [entry.name];
      }
      return [];
    })
    .sort();

  assert.deepEqual(moduleNames, [
    'archive',
    'dataset',
    'entrypoints',
    'error',
    'inventory',
    'jsonl',
    'row_writers',
    'sqlite_json',
    'temp_file',
    'tests',
    'types',
    'writers',
  ]);

  // `tests` is gated behind `#[cfg(test)]` so the facade-registration
  // assertion targets the production submodules only.
  for (const moduleName of [
    'archive',
    'dataset',
    'entrypoints',
    'error',
    'inventory',
    'jsonl',
    'row_writers',
    'sqlite_json',
    'temp_file',
    'types',
    'writers',
  ]) {
    assert.match(
      modSource,
      new RegExp(`^mod ${moduleName};$`, 'm'),
      `export facade should register ${moduleName} module`,
    );
  }

  const lineCount = modSource.trimEnd().split('\n').length;
  assert.ok(lineCount <= 90, `export/mod.rs should stay a thin facade, got ${lineCount} lines`);

  for (const forbiddenSnippet of [
    'pub fn export_to_zip(',
    'pub enum ExportError',
    'pub struct ExportManifest',
    'pub(super) fn sqlite_value_to_json',
  ]) {
    assert.equal(
      modSource.includes(forbiddenSnippet),
      false,
      `export facade should not inline extracted implementation: ${forbiddenSnippet}`,
    );
  }

  const entrypointsSource = fs.readFileSync(path.join(exportDir, 'entrypoints.rs'), 'utf8');
  assert.match(entrypointsSource, /\npub fn export_to_zip\(/);
  assert.match(entrypointsSource, /\npub fn export_to_zip_scoped\(/);

  // `row_writers.rs` now hosts only the unversioned writers (provider links,
  // ai_changelog). Versioned per-entity writers (tasks + checklists,
  // calendar events + attendees, etc.) moved behind the
  // `VersionedTableWriter` trait under `writers/`.
  const rowWritersSource = fs.readFileSync(path.join(exportDir, 'row_writers.rs'), 'utf8');
  assert.match(rowWritersSource, /\npub\(in crate::export\) fn write_provider_link_rows\(/);
  assert.match(rowWritersSource, /\npub\(in crate::export\) fn write_audit_rows\(/);

  const writersModSource = fs.readFileSync(path.join(exportDir, 'writers/mod.rs'), 'utf8');
  assert.match(writersModSource, /\npub\(super\) trait VersionedTableWriter\b/);
  assert.match(writersModSource, /\npub\(super\) fn run_versioned_writer</);
  // Per-entity writer modules implement the shared trait.
  for (const writerFile of ['task.rs', 'calendar_event.rs', 'edge.rs']) {
    const writerSource = fs.readFileSync(path.join(exportDir, 'writers', writerFile), 'utf8');
    assert.match(
      writerSource,
      /impl VersionedTableWriter for /,
      `${writerFile} should implement VersionedTableWriter`,
    );
  }
});
