import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

const repoRoot = path.resolve(import.meta.dirname, '..', '..', '..');

function readRepoFile(...parts) {
  return fs.readFileSync(path.join(repoRoot, ...parts), 'utf8');
}

test('habit sync payload mapping is centralized in lorvex-store', () => {
  const storeMod = readRepoFile('lorvex-store/src/payload_loaders/mod.rs');
  const storeHabit = readRepoFile('lorvex-store/src/payload_loaders/habit.rs');
  const mcpHabits = readRepoFile('mcp-server/src/habits/mod.rs');
  const mcpDelete = readRepoFile('mcp-server/src/habits/writes/delete.rs');
  const tauriWrites = readRepoFile('app/src-tauri/src/commands/habits/queries/writes.rs');
  const cliEffects = readRepoFile('lorvex-cli/src/commands/mutate/habits/effects/mod.rs');
  const cliTypes = readRepoFile('lorvex-cli/src/commands/mutate/habits/effects/types.rs');

  assert.match(
    storeMod,
    /pub use habit::(?:\{[\s\S]*load_habit_sync_payload[\s\S]*\}|load_habit_sync_payload);/,
    'lorvex-store should export the per-id habit sync payload loader',
  );
  assert.match(
    storeHabit,
    /\npub fn load_habit_sync_payload\(/,
    'lorvex-store should own the per-id habit sync payload loader',
  );
  assert.doesNotMatch(
    mcpHabits,
    /HabitSyncFields|fn habit_sync_fields/,
    'MCP should not own habit sync field mapping',
  );
  assert.match(
    mcpDelete,
    /load_habit_sync_payload\(/,
    'MCP delete should use the store-owned habit sync payload loader',
  );
  assert.doesNotMatch(
    tauriWrites,
    /HabitSyncFields|fn habit_sync_fields|fn habit_upsert_payload/,
    'Tauri habit writes should not own habit sync field mapping helpers',
  );
  assert.match(
    tauriWrites,
    /load_habit_sync_payload\(/,
    'Tauri habit writes should use the store-owned habit sync payload loader',
  );
  assert.doesNotMatch(
    cliTypes,
    /HabitSyncFields|sync_fields\(/,
    'CLI habit row DTOs should not own habit sync field mapping',
  );
  assert.doesNotMatch(
    cliEffects,
    /lorvex_domain::habits::habit_sync_payload\(|sync_fields\(/,
    'CLI habit effects should not directly build habit sync payloads',
  );
  assert.match(
    cliEffects,
    /load_habit_sync_payload\(/,
    'CLI habit effects should use the store-owned habit sync payload loader',
  );
});
