import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";

import { repoRoot } from "./shared.mjs";

const testsDir = path.join(repoRoot, "lorvex-sync/src/pending_inbox/tests");
const legacyTestsPath = path.join(
  repoRoot,
  "lorvex-sync/src/pending_inbox/tests.rs",
);
const rootPath = path.join(testsDir, "mod.rs");

const expectedModules = [
  "attempt_cap",
  "basic_queue",
  "drain_fairness",
  "error_dedup_busy",
  "expiry_gc",
  "quarantine_blocklist",
  "query_plan",
  "reattempt_accounting",
  "redirect_remap",
  "support",
  "validation_quarantine",
];

const expectedTestsByModule = {
  "attempt_cap.rs": [
    "drain_deferred_schema_too_new_does_not_discard_at_attempt_cap",
    "drain_discards_entry_that_exceeded_attempt_cap",
    "drain_discards_permanently_erroring_entry_after_attempt_cap",
    "drain_keeps_entry_below_attempt_cap",
    "enqueue_deferred_schema_too_new_does_not_exhaust_retry_budget",
    "enqueue_pending_coalesces_duplicate_envelopes",
    "enqueue_pending_distinguishes_envelopes_by_version",
  ],
  "basic_queue.rs": [
    "count_pending_after_inserts",
    "count_pending_empty",
    "enqueue_and_get_pending",
    "enqueue_without_missing_info",
    "fifo_ordering",
    "parse_envelope_roundtrip",
    "remove_pending_deletes_entry",
  ],
  "drain_fairness.rs": [
    "drain_reaches_old_parent_after_first_capped_child_batch",
  ],
  "error_dedup_busy.rs": [
    "busy_or_locked_apply_failure_does_not_bump_attempt_count",
    "drain_dedups_repeated_error_logs_for_same_failure_message",
  ],
  "expiry_gc.rs": [
    "gc_expired_entries_deletes_past_horizon",
    "gc_expired_entries_keeps_recent",
    "has_expired_entries_empty_inbox",
    "has_expired_entries_false_when_recent",
    "has_expired_entries_true_when_old",
  ],
  // Post-#3066: an additional regression test joined this domain.
  "quarantine_blocklist.rs": [
    "enqueue_pending_records_blocklist_when_cap_promotes",
    "enqueue_pending_short_circuits_quarantined_identity",
    "record_quarantine_preserves_first_observed_row",
  ],
  "query_plan.rs": [
    "pending_entry_ids_for_drain_uses_last_attempted_ordering_index",
    "pending_expiry_queries_use_first_attempted_index",
  ],
  "reattempt_accounting.rs": [
    "invariant_blocked_replay_bumps_attempt_once",
    "record_reattempt_increments_count",
  ],
  "redirect_remap.rs": [
    "drain_discards_malformed_composite_redirect_entity_id",
    "drain_pending_inbox_coalesces_identity_collision_after_redirect_remap",
    "drain_pending_inbox_remaps_composite_redirect_via_entity_id_when_payload_lacks_fk_fields",
  ],
  "validation_quarantine.rs": [
    "drain_quarantines_at_cap_unparseable_envelope_to_conflict_log",
    "drain_quarantines_unparseable_envelope_and_continues",
    "enqueue_pending_rejects_malformed_payload_json",
    "enqueue_pending_rejects_overly_nested_payload",
  ],
};

function read(relativePath) {
  return fs.readFileSync(path.join(testsDir, relativePath), "utf8");
}

function testNamesIn(relativePath) {
  return [
    ...read(relativePath).matchAll(
      /^#\[test\]\n(?:#\[[^\n]+\]\n)*fn\s+([a-zA-Z0-9_]+)\s*\(/gm,
    ),
  ].map((match) => match[1]);
}

test("lorvex-sync pending inbox tests are split by queue behavior domain", () => {
  assert.equal(
    fs.existsSync(legacyTestsPath),
    false,
    "pending_inbox/tests.rs should not remain as a 1000+ line hotspot",
  );
  assert.equal(
    fs.existsSync(rootPath),
    true,
    "pending_inbox/tests/mod.rs should exist",
  );

  const rootSource = fs.readFileSync(rootPath, "utf8");
  assert.ok(
    rootSource.split("\n").length <= 70,
    "pending_inbox/tests/mod.rs should stay a small test-module facade",
  );
  assert.doesNotMatch(
    rootSource,
    /\n#\[test\]\n/,
    "behavior tests should live in pending_inbox/tests/*.rs modules",
  );
  assert.doesNotMatch(
    rootSource,
    /\nfn\s+make_(?:delete_)?envelope\b|\nfn\s+insert_unparseable_pending_row\b/,
    "shared pending inbox fixtures should live in support.rs",
  );

  const actualModuleDeclarations = [
    ...rootSource.matchAll(/^mod ([a-z_]+);$/gm),
  ]
    .map((match) => match[1])
    .sort();
  assert.deepEqual(
    actualModuleDeclarations,
    expectedModules.toSorted(),
    "pending_inbox/tests/mod.rs should declare exactly the expected behavior modules",
  );

  const actualFiles = fs
    .readdirSync(testsDir)
    .filter((entry) => entry.endsWith(".rs"))
    .sort();
  assert.deepEqual(
    actualFiles,
    [
      "mod.rs",
      ...expectedModules.map((moduleName) => `${moduleName}.rs`),
    ].sort(),
    "pending_inbox/tests directory should contain exactly the expected Rust module files",
  );

  const supportSource = read("support.rs");
  for (const reexport of [
    "pub(super) use crate::envelope::SyncOperation;",
    "pub(super) use crate::test_db;",
    "pub(super) use crate::tombstone::create_tombstone;",
    "pub(super) use lorvex_domain::naming;",
    "pub(super) use rusqlite::{params, Connection, Params};",
  ]) {
    assert.match(
      supportSource,
      new RegExp(reexport.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")),
      `support.rs should re-export shared pending inbox test dependency: ${reexport}`,
    );
  }
  for (const helperName of [
    "make_envelope",
    "make_delete_envelope",
    "insert_unparseable_pending_row",
    "make_reminder_envelope_with_missing_task",
  ]) {
    assert.match(
      supportSource,
      new RegExp(`\\npub\\(super\\) fn ${helperName}\\b`),
      `support.rs should own shared helper ${helperName}`,
    );
  }

  for (const moduleName of expectedModules.filter(
    (name) => name !== "support",
  )) {
    const source = read(`${moduleName}.rs`);
    assert.match(
      source,
      /^use super::super::\*;$/m,
      `${moduleName}.rs should keep private implementation coverage colocated with pending_inbox`,
    );
    assert.match(
      source,
      /^use super::support::\*;$/m,
      `${moduleName}.rs should import shared pending inbox test fixtures`,
    );
  }

  for (const [relativePath, expectedNames] of Object.entries(
    expectedTestsByModule,
  )) {
    assert.deepEqual(
      testNamesIn(relativePath).sort(),
      expectedNames.toSorted(),
      `${relativePath} should own the expected pending inbox test set`,
    );
  }

  const actualTestNames = Object.keys(expectedTestsByModule)
    .flatMap(testNamesIn)
    .sort();
  const expectedTestNames = Object.values(expectedTestsByModule).flat().sort();
  assert.deepEqual(
    actualTestNames,
    expectedTestNames,
    "split pending inbox test modules should preserve the complete migrated test-name set",
  );
});
