import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { hasRustUseReexport, repoRoot } from './shared.mjs';

// `outbox_enqueue` was promoted from a single file to a directory module;
// `mod.rs` is now the canonical root. Pre-fix the test pointed at the old
// `outbox_enqueue.rs` path, which never existed after the refactor — silently
// failing this gate.
const ROOT = 'lorvex-sync/src/outbox_enqueue/mod.rs';
const CHILD_TOMBSTONES = 'lorvex-sync/src/outbox_enqueue/child_tombstones.rs';

function read(relativePath) {
  return fs.readFileSync(path.join(repoRoot, relativePath), 'utf8');
}

test('outbox enqueue delegates child cascade tombstones to a dedicated module', () => {
  const rootSource = read(ROOT);
  const childSource = read(CHILD_TOMBSTONES);

  assert.match(
    rootSource,
    /^mod child_tombstones;$/m,
    'outbox_enqueue root should register child_tombstones.rs',
  );
  assert.ok(
    hasRustUseReexport(rootSource, {
      modulePath: 'child_tombstones',
      symbols: [
        'DeletedHabitCompletionSnapshot',
        'DeletedHabitReminderPolicySnapshot',
        'DeletedTaskCalendarEventLinkSnapshot',
        'enqueue_edge_tombstones_for_calendar_event_delete',
        'tombstone_edges_for_calendar_event_delete',
        'tombstone_completions_for_habit_delete',
        'tombstone_reminder_policies_for_habit_delete',
      ],
      visibility: 'pub',
    }),
    'outbox_enqueue root should publicly re-export child tombstone APIs',
  );
  assert.ok(
    rootSource.split('\n').length <= 820,
    'outbox_enqueue root should shrink after child tombstone extraction',
  );
  assert.doesNotMatch(
    rootSource,
    /\npub struct Deleted(?:HabitCompletion|HabitReminderPolicy|TaskCalendarEventLink)Snapshot\b|\nfn collect_calendar_event_link_snapshots\b|\npub fn tombstone_(?:edges_for_calendar_event_delete|completions_for_habit_delete|reminder_policies_for_habit_delete)\b/,
    'outbox_enqueue root should not keep child tombstone implementations inline',
  );

  for (const symbol of [
    'DeletedHabitCompletionSnapshot',
    'DeletedHabitReminderPolicySnapshot',
    'DeletedTaskCalendarEventLinkSnapshot',
  ]) {
    assert.match(
      childSource,
      new RegExp(`\\npub struct ${symbol}\\b`),
      `child_tombstones.rs should own ${symbol}`,
    );
  }
  for (const functionName of [
    'enqueue_edge_tombstones_for_calendar_event_delete',
    'tombstone_edges_for_calendar_event_delete',
    'tombstone_completions_for_habit_delete',
    'tombstone_reminder_policies_for_habit_delete',
  ]) {
    assert.match(
      childSource,
      new RegExp(`\\npub fn ${functionName}\\b`),
      `child_tombstones.rs should own ${functionName}`,
    );
  }
});
