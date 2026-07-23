import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const repoRoot = path.resolve(__dirname, '../../..');

function read(relativePath) {
  return fs.readFileSync(path.join(repoRoot, relativePath), 'utf8');
}

const actorFilterModulePath = 'lorvex-store/src/repositories/ai_changelog_actor_filter.rs';
const rawActorList = "'human', 'system', 'user', 'manual'";

test('AI changelog assistant actor filtering is owned by the store helper', () => {
  const actorFilterModule = read(actorFilterModulePath);
  const querySource = read('lorvex-store/src/repositories/ai_changelog_query/mod.rs');
  const retentionSource = read('lorvex-sync/src/retention_sweep/mod.rs');
  const exportSource = read('lorvex-store/src/export/row_writers.rs');
  const tauriSharedConstants = read('app/src-tauri/src/commands/shared/constants.rs');
  const diagnosticsSource = read('app/src-tauri/src/commands/diagnostics/changelog.rs');

  assert.match(actorFilterModule, /NON_ASSISTANT_ACTORS_SQL/);
  assert.match(actorFilterModule, /ai_changelog_assistant_actor_filter_sql\(/);
  assert.match(actorFilterModule, /ai_changelog_assistant_actor_filter_sql_for_alias\(/);

  for (const [label, source] of [
    ['store query', querySource],
    ['retention sweep', retentionSource],
    ['export row writer', exportSource],
    ['Tauri shared constants', tauriSharedConstants],
    ['Tauri diagnostics', diagnosticsSource],
  ]) {
    assert.doesNotMatch(
      source,
      new RegExp(rawActorList.replaceAll("'", "\\'")),
      `${label} must not duplicate the non-assistant actor list`,
    );
  }

  assert.match(querySource, /ai_changelog_assistant_actor_filter_sql\(\)/);
  assert.match(querySource, /ai_changelog_assistant_actor_filter_sql_for_alias\("ac"\)/);
  assert.match(retentionSource, /ai_changelog_assistant_actor_filter_sql\(\)/);
  assert.match(exportSource, /ai_changelog_assistant_actor_filter_sql\(\)/);
  assert.match(tauriSharedConstants, /ai_changelog_assistant_actor_filter_sql\(\)/);
  assert.match(diagnosticsSource, /ai_changelog_where_clause_for_alias\("c"\)/);
});
