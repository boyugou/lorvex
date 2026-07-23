import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

const repoRoot = path.resolve(import.meta.dirname, '..', '..', '..');
const commandsPath = path.join(repoRoot, 'app', 'src-tauri', 'src', 'commands.rs');

test('commands root delegates sync runtime commands and core types to a dedicated module', () => {
  const source = fs.readFileSync(commandsPath, 'utf8');
  const runtimeSource = fs.readFileSync(
    path.join(repoRoot, 'app', 'src-tauri', 'src', 'commands', 'sync', 'runtime.rs'),
    'utf8',
  );

  assert.match(source, /^(?:pub\(crate\)\s+)?mod sync;$/m);
  // Several IPC entrypoints (apply_remote_sync_envelopes,
  // cleanup_sync_outbox, mark_outbox_entries_synced, mark_outbox_entry_retry,
  // get/set/delete_sync_checkpoint) were intentionally deleted as the writes
  // were folded into transport-internal helpers and are no longer exposed to
  // the renderer. The remaining IPC re-exports cover the surface that's still
  // wired through commands.rs.
  assert.match(runtimeSource, /pub use apply::\{ApplyRemoteSyncResult, IncomingSyncRecord\};/);
  assert.match(runtimeSource, /pub use queue::\{[\s\S]*get_pending_outbox_entries[\s\S]*get_recent_outbox_entries[\s\S]*SyncOutboxEntry[\s\S]*\};/);
  assert.match(runtimeSource, /pub use status::\{get_sync_status, SyncStatus\};/);

  for (const snippet of [
    'pub fn get_sync_checkpoint(',
    'pub fn set_sync_checkpoint(',
    'pub fn delete_sync_checkpoint(',
    'pub fn cleanup_sync_outbox(',
    'pub fn get_sync_status(',
    'fn load_sync_status_from_conn(',
    'pub fn get_pending_outbox_entries(',
    'pub fn get_recent_outbox_entries(',
    'pub fn mark_outbox_entries_synced(',
    'fn mark_outbox_entries_synced_internal(',
    'pub fn mark_outbox_entry_retry(',
    'fn mark_outbox_entry_retry_internal(',
    'fn gc_synced_events(',
    'fn is_supported_incoming_record(',
    'fn outbox_entry_from_row(',
    'fn get_or_create_sync_device_id(',
    'fn enqueue_to_outbox(',
    'fn enqueue_calendar_to_outbox(',
    'fn enqueue_task_upsert(',
    'fn enqueue_task_delete(',
    'fn enqueue_list_delete(',
    'fn enqueue_preference_upsert(',
    'fn compare_sync_versions(',
    'fn compare_sync_versions_with_outbox_id(',
    'fn upsert_sync_checkpoint_timestamp_if_newer(',
    'fn latest_entity_sync_version(',
    'fn incoming_records_match_for_file_idempotency(',
    'fn sync_entity_apply_priority(',
    'fn apply_remote_sync_envelopes_with_filesystem_bridge_cursor(',
    'fn apply_remote_sync_envelopes_internal(',
    'pub struct SyncStatus',
    'pub struct SyncOutboxEntry',
    'pub struct IncomingSyncRecord',
    'pub struct ApplyRemoteSyncResult',
  ]) {
    assert.equal(
      source.includes(snippet),
      false,
      `commands.rs should no longer inline sync runtime snippet: ${snippet}`,
    );
  }
});
