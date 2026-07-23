import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";

import { readRustSources, repoRoot } from "./shared.mjs";

const enqueueFacadePath = path.join(
  repoRoot,
  "app/src-tauri/src/commands/sync/runtime/queue/enqueue.rs",
);
const enqueueModulesPath = path.join(
  repoRoot,
  "app/src-tauri/src/commands/sync/runtime/queue",
);

function readFacade() {
  return fs.readFileSync(enqueueFacadePath, "utf8");
}

function readModule(name) {
  return fs.readFileSync(path.join(enqueueModulesPath, `enqueue_${name}.rs`), "utf8");
}

function assertFunctionInModule(moduleName, functionName) {
  assert.match(
    readModule(moduleName),
    new RegExp(
      `\\n(?:pub\\(crate\\)\\s+)?fn ${functionName}(?:<[^\\n{]*>)?\\(`,
    ),
    `${moduleName}.rs should own ${functionName}`,
  );
}

test("sync runtime enqueue helpers are split into focused modules", () => {
  const facadeSource = readFacade();
  const expectedModules = [
    "aggregates",
    "child_items",
    "core",
    "edge_snapshots",
    "envelope",
    "lifecycle",
    "task_entities",
  ];

  assert.equal(
    fs.existsSync(enqueueModulesPath),
    true,
    "sync_runtime/queue/enqueue helpers should live as flat enqueue_* siblings",
  );
  const moduleTreeSource = readRustSources(
    "app/src-tauri/src/commands/sync/runtime/queue/enqueue.rs",
    "app/src-tauri/src/commands/sync/runtime/queue/enqueue_aggregates.rs",
    "app/src-tauri/src/commands/sync/runtime/queue/enqueue_child_items.rs",
    "app/src-tauri/src/commands/sync/runtime/queue/enqueue_core.rs",
    "app/src-tauri/src/commands/sync/runtime/queue/enqueue_edge_snapshots.rs",
    "app/src-tauri/src/commands/sync/runtime/queue/enqueue_envelope.rs",
    "app/src-tauri/src/commands/sync/runtime/queue/enqueue_lifecycle.rs",
    "app/src-tauri/src/commands/sync/runtime/queue/enqueue_task_entities.rs",
  );

  assert.doesNotMatch(
    facadeSource,
    /#\[test\]/,
    "sync_runtime/queue/enqueue.rs should be a facade, not a mixed implementation and test file",
  );
  assert.doesNotMatch(
    facadeSource,
    /\n(?:pub\(crate\)\s+)?fn\s+[a-zA-Z0-9_]+\(/,
    "sync_runtime/queue/enqueue.rs should not regain implementation functions",
  );
  assert.doesNotMatch(
    facadeSource,
    /\n(?:pub\(crate\)\s+)?struct\s+[a-zA-Z0-9_]+/,
    "sync_runtime/queue/enqueue.rs should not regain implementation structs",
  );

  for (const moduleName of expectedModules) {
    assert.match(
      facadeSource,
      new RegExp(`pub\\(crate\\) use super::enqueue_${moduleName}::`, "m"),
      `enqueue.rs should re-export enqueue_${moduleName}.rs`,
    );
  }

  assert.match(readModule("envelope"), /\npub\(crate\) struct DeleteEnvelope</);
  for (const functionName of [
    "get_or_create_sync_device_id_typed",
    "enqueue_to_outbox_typed",
    "enqueue_to_outbox",
    "enqueue_calendar_to_outbox",
  ]) {
    assertFunctionInModule("core", functionName);
  }

  for (const functionName of [
    "load_task_reminder_sync_payload",
    "enqueue_task_reminder_upsert",
    "enqueue_task_reminder_delete",
    "load_task_reminder_pre_delete_snapshot",
    "enqueue_task_checklist_item_upsert",
    "enqueue_task_checklist_item_delete",
    "load_task_checklist_item_pre_delete_snapshot",
  ]) {
    assertFunctionInModule("child_items", functionName);
  }

  for (const functionName of [
    "enqueue_task_upsert",
    "enqueue_task_delete_with_version",
    "enqueue_list_upsert",
    "enqueue_list_delete_with_version",
    "enqueue_tag_upsert",
  ]) {
    assertFunctionInModule("task_entities", functionName);
  }

  for (const functionName of [
    "enqueue_preference_upsert",
    "enqueue_preference_delete",
    "load_preference_pre_delete_snapshot",
    "enqueue_task_tag_delete",
    "load_task_tag_pre_delete_snapshot",
    "enqueue_task_calendar_event_link_delete",
    "load_task_calendar_event_link_pre_delete_snapshot",
  ]) {
    assertFunctionInModule("edge_snapshots", functionName);
  }

  for (const functionName of [
    "enqueue_current_focus_upsert_for_date",
    "enqueue_focus_schedule_upsert_for_date",
    "enqueue_aggregate_root_for_date",
  ]) {
    assertFunctionInModule("aggregates", functionName);
  }

  for (const functionName of [
    "enqueue_deleted_dep_edges",
    "enqueue_dependency_edge_upsert",
    "enqueue_affected_dependents",
    "enqueue_copied_tag_edges",
    "enqueue_cancelled_successors",
    "enqueue_lifecycle_sync_plan",
    "enqueue_lifecycle_transition",
  ]) {
    assertFunctionInModule("lifecycle", functionName);
  }

  const testNames = Array.from(
    moduleTreeSource.matchAll(/#\[test\]\s*fn\s+([a-zA-Z0-9_]+)\(/g),
    (match) => match[1],
  );
  assert.deepEqual(
    testNames.sort(),
    [
      "enqueue_lifecycle_sync_plan_surfaces_missing_reminder_errors",
      "enqueue_preference_upsert_rejects_malformed_json_value",
      "load_task_reminder_sync_payload_returns_full_snapshot_shape",
    ],
    "enqueue/ should preserve the existing focused enqueue unit tests",
  );
});
