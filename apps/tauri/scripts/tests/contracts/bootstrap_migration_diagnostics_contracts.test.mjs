import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

// Post-#3303 bootstrap split: the previous monolithic
// `app/src-tauri/src/bootstrap.rs` was extracted into a folder so that
// migration_progress, database_ready, panic_hook, etc. each own their
// own narrow concern. The contract still asserts the same diagnostic
// lifecycle, but reads from the focused submodules.
const DATABASE_READY_PATH = 'app/src-tauri/src/bootstrap/database_ready.rs';
const MIGRATION_PROGRESS_PATH = 'app/src-tauri/src/bootstrap/migration_progress.rs';

test('bootstrap migration progress persists diagnostics instead of writing stderr', () => {
  const databaseReadySource = fs.readFileSync(
    path.join(repoRoot, DATABASE_READY_PATH),
    'utf8',
  );
  const migrationProgressSource = fs.readFileSync(
    path.join(repoRoot, MIGRATION_PROGRESS_PATH),
    'utf8',
  );

  // ensure_database_ready owns the migration progress lifecycle;
  // its body must NOT fall back to direct stderr.
  const ensureDatabaseReadyBody = databaseReadySource.match(
    /pub\(crate\) fn ensure_database_ready\(\) \{[\s\S]*?\n\}/,
  );
  assert.ok(ensureDatabaseReadyBody, 'ensure_database_ready body must stay explicit');
  assert.doesNotMatch(
    ensureDatabaseReadyBody[0],
    /eprintln!\s*\(/,
    'migration progress lifecycle must use structured diagnostics instead of direct stderr',
  );
  assert.match(
    databaseReadySource,
    /persist_migration_progress_events/,
    'ensure_database_ready must persist migration progress via the structured events helper',
  );

  // Per-stage event sources are emitted by the database_ready
  // orchestrator, which dispatches into the migration_progress event
  // recorder. Asserting on database_ready.rs ensures every stage stays
  // wired (and that a future refactor doesn't drop one without also
  // dropping its diagnostics row).
  void migrationProgressSource;
  assert.match(databaseReadySource, /app\.startup\.migration\.init/);
  assert.match(databaseReadySource, /app\.startup\.migration\.complete/);
  assert.match(databaseReadySource, /app\.startup\.migration\.threshold_crossed/);
});
