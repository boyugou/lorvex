import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";

import { hasRustUseReexport, readRustSources, repoRoot, rustModuleDeclarationPattern } from "./shared.mjs";

test("sync_runtime queue is organized as a focused module tree instead of one mixed file", () => {
  const queueDir = path.join(
    repoRoot,
    "app/src-tauri/src/commands/sync/runtime/queue",
  );
  const modSource = fs.readFileSync(path.join(queueDir, "mod.rs"), "utf8");
  const typesSource = fs.readFileSync(path.join(queueDir, "types.rs"), "utf8");
  const enqueueSource = readRustSources(
    "app/src-tauri/src/commands/sync/runtime/queue/enqueue.rs",
    "app/src-tauri/src/commands/sync/runtime/queue/enqueue_aggregates.rs",
    "app/src-tauri/src/commands/sync/runtime/queue/enqueue_child_items.rs",
    "app/src-tauri/src/commands/sync/runtime/queue/enqueue_core.rs",
    "app/src-tauri/src/commands/sync/runtime/queue/enqueue_edge_snapshots.rs",
    "app/src-tauri/src/commands/sync/runtime/queue/enqueue_envelope.rs",
    "app/src-tauri/src/commands/sync/runtime/queue/enqueue_lifecycle.rs",
    "app/src-tauri/src/commands/sync/runtime/queue/enqueue_task_entities.rs",
  );
  const eventsSource = fs.readFileSync(
    path.join(queueDir, "events.rs"),
    "utf8",
  );
  const retrySource = fs.readFileSync(path.join(queueDir, "retry.rs"), "utf8");
  const filesystemRootSource = fs.readFileSync(
    path.join(queueDir, "filesystem_bridge_root_path.rs"),
    "utf8",
  );

  assert.equal(
    fs.existsSync(
      path.join(repoRoot, "app/src-tauri/src/commands/sync/runtime/queue.rs"),
    ),
    false,
    "sync_runtime/queue.rs should be replaced by a sync_runtime/queue/ folder tree",
  );

  for (const moduleName of [
    "enqueue",
    "enqueue_aggregates",
    "enqueue_child_items",
    "enqueue_core",
    "enqueue_edge_snapshots",
    "enqueue_envelope",
    "enqueue_imports",
    "enqueue_lifecycle",
    "enqueue_task_entities",
    "events",
    "retry",
    "seed",
    "seed_entities",
    "seed_helpers",
    "seed_orchestrator",
    "filesystem_bridge_root_path",
    "types",
  ]) {
    assert.match(
      modSource,
      rustModuleDeclarationPattern(moduleName),
      `sync_runtime/queue/mod.rs should register ${moduleName}.rs`,
    );
  }

  assert.equal(
    hasRustUseReexport(modSource, {
      modulePath: "events",
      symbols: ["get_pending_outbox_entries", "get_recent_outbox_entries"],
    }),
    true,
    "sync_runtime/queue/mod.rs should re-export queue event commands from events.rs",
  );
  assert.equal(
    hasRustUseReexport(modSource, {
      modulePath: "retry",
      symbols: [
        "mark_outbox_entries_synced_internal",
        "mark_outbox_entry_retry_internal",
      ],
    }),
    true,
    "sync_runtime/queue/mod.rs should re-export queue retry commands from retry.rs",
  );
  assert.equal(
    hasRustUseReexport(modSource, {
      modulePath: "types",
      symbols: ["SyncOutboxEntry"],
    }),
    true,
    "sync_runtime/queue/mod.rs should re-export SyncOutboxEntry from types.rs",
  );

  assert.match(typesSource, /\npub struct SyncOutboxEntry \{/);
  assert.match(typesSource, /\npub\(super\) fn outbox_entry_from_row\(/);
  assert.match(
    enqueueSource,
    /\npub\(crate\) fn get_or_create_sync_device_id_typed\(/,
  );
  assert.match(enqueueSource, /\npub\(crate\) fn enqueue_preference_upsert\(/);
  assert.match(
    eventsSource,
    /\n#\[tauri::command\]\npub fn get_pending_outbox_entries\(/,
  );
  assert.match(
    eventsSource,
    /\n#\[tauri::command\]\npub fn get_recent_outbox_entries\(/,
  );
  assert.match(
    retrySource,
    /\npub\(crate\) fn mark_outbox_entries_synced_internal\(/,
  );
  assert.match(
    retrySource,
    /\npub\(crate\) fn mark_outbox_entry_retry_internal\(/,
  );
  assert.match(
    filesystemRootSource,
    /\npub\(crate\) fn resolve_filesystem_bridge_root_path\(/,
  );
});
