import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

const repoRoot = process.cwd();

function read(relativePath) {
  return fs.readFileSync(path.join(repoRoot, relativePath), 'utf8');
}

test('Tauri task date writes use the canonical domain date validator', () => {
  // Task write paths that accept YYYY-MM-DD user input route the value
  // through `lorvex_domain::validation::validate_date_format` so the
  // shape rules stay aligned with MCP/CLI surfaces.
  const taskWritePaths = [
    'app/src-tauri/src/commands/tasks/capture/mod.rs',
    'app/src-tauri/src/commands/tasks/lifecycle/deferral.rs',
    'app/src-tauri/src/commands/tasks/batch/defer.rs',
  ];

  for (const relativePath of taskWritePaths) {
    const source = read(relativePath);
    assert.match(
      source,
      /validate_date_format/,
      `${relativePath} should delegate YYYY-MM-DD validation to lorvex-domain`,
    );
    assert.doesNotMatch(
      source,
      /is_valid_date_yyyy_mm_dd/,
      `${relativePath} must not use the removed local YYYY-MM-DD parser`,
    );
  }
});

test('Tauri shared utilities do not reintroduce a duplicate YYYY-MM-DD parser', () => {
  // The shared/ command tree should not carry a duplicate date
  // validator. Walk every file under shared/ and confirm none of
  // them ship the legacy helper.
  const sharedDir = path.join(repoRoot, 'app/src-tauri/src/commands/shared');

  function walk(dir) {
    return fs.readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) return walk(full);
      if (entry.isFile() && entry.name.endsWith('.rs')) return [full];
      return [];
    });
  }

  for (const sharedFile of walk(sharedDir)) {
    const source = fs.readFileSync(sharedFile, 'utf8');
    assert.doesNotMatch(
      source,
      /is_valid_date_yyyy_mm_dd/,
      `${path.relative(repoRoot, sharedFile)} must not reintroduce the removed YYYY-MM-DD helper`,
    );
  }
});
