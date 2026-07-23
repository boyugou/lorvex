import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { hasRustUseReexport, repoRoot } from './shared.mjs';

const ROOT_PATH = 'lorvex-cli/src/commands/mutate/calendar/effects/mutations.rs';
const MODULE_DIR = 'lorvex-cli/src/commands/mutate/calendar/effects/mutations';

function read(relativePath) {
  return fs.readFileSync(path.join(repoRoot, relativePath), 'utf8');
}

function assertOwnsFunction(source, functionName, label) {
  assert.match(
    source,
    new RegExp(`\\n(?:pub\\(crate\\) )?fn ${functionName}\\b`),
    `${label} should own ${functionName}`,
  );
}

test('CLI calendar mutations are split by write-path family behind a thin facade', () => {
  const moduleDir = path.join(repoRoot, MODULE_DIR);
  assert.ok(fs.statSync(moduleDir).isDirectory(), 'CLI calendar mutations should be folder-backed');

  const moduleFiles = fs
    .readdirSync(moduleDir)
    .filter((entry) => entry.endsWith('.rs'))
    .sort();
  assert.deepEqual(
    moduleFiles,
    [
      'create.rs',
      'delete.rs',
      'exceptions.rs',
      'links.rs',
      'provider_links.rs',
      'support.rs',
      'update.rs',
    ],
    'CLI calendar mutation modules should stay split by write-path family',
  );

  const facade = read(ROOT_PATH);
  assert.ok(facade.split('\n').length <= 80, 'calendar mutations facade should stay small');
  for (const moduleName of [
    'create',
    'delete',
    'exceptions',
    'links',
    'provider_links',
    'support',
    'update',
  ]) {
    assert.match(facade, new RegExp(`^mod ${moduleName};$`, 'm'));
  }
  assert.doesNotMatch(
    facade,
    /\n(?:pub\(crate\)\s+)?fn |\nstruct PreparedCalendarEventCreate|\nenum ExceptionOp/,
    'calendar mutations facade should not retain implementations or private helper types',
  );

  assert.ok(
    hasRustUseReexport(facade, {
      modulePath: 'create',
      symbols: ['create_calendar_event_with_conn', 'create_calendar_events_with_conn'],
      visibility: 'pub(crate)',
    }),
  );
  assert.ok(
    hasRustUseReexport(facade, {
      modulePath: 'update',
      symbols: ['update_calendar_event_with_conn'],
      visibility: 'pub(crate)',
    }),
  );
  assert.ok(
    hasRustUseReexport(facade, {
      modulePath: 'delete',
      symbols: ['delete_calendar_event_with_conn'],
      visibility: 'pub(crate)',
    }),
  );
  assert.ok(
    hasRustUseReexport(facade, {
      modulePath: 'links',
      symbols: ['link_tasks_to_calendar_event_with_conn', 'unlink_task_from_calendar_event_with_conn'],
      visibility: 'pub(crate)',
    }),
  );
  assert.ok(
    hasRustUseReexport(facade, {
      modulePath: 'provider_links',
      symbols: ['link_task_to_provider_event_with_conn', 'unlink_task_from_provider_event_with_conn'],
      visibility: 'pub(crate)',
    }),
  );
  assert.ok(
    hasRustUseReexport(facade, {
      modulePath: 'exceptions',
      symbols: ['add_calendar_event_exception_with_conn', 'remove_calendar_event_exception_with_conn'],
      visibility: 'pub(crate)',
    }),
  );

  const create = read(`${MODULE_DIR}/create.rs`);
  assert.match(create, /\bCalendarEventCreateInput as WorkflowCreateInput\b/);
  assert.match(create, /\bCreateCalendarEventMutation\b/);
  assert.match(create, /\nstruct BatchCreateCliCalendarEventsMutation\b/);
  assertOwnsFunction(create, 'create_calendar_event_with_conn', 'create.rs');
  assertOwnsFunction(create, 'create_calendar_events_with_conn', 'create.rs');
  assertOwnsFunction(create, 'workflow_input_from_fields', 'create.rs');
  assert.doesNotMatch(create, /unlink_task_from_|ExceptionOp|provider_event/);

  const update = read(`${MODULE_DIR}/update.rs`);
  assertOwnsFunction(update, 'update_calendar_event_with_conn', 'update.rs');
  assert.match(update, /\bCalendarEventUpdateInput as WorkflowUpdateInput\b/);
  assert.match(update, /\bUpdateCalendarEventMutation\b/);
  assert.doesNotMatch(update, /create_calendar_events_with_conn|unlink_task_from_provider_event/);

  const deleteSource = read(`${MODULE_DIR}/delete.rs`);
  assertOwnsFunction(deleteSource, 'delete_calendar_event_with_conn', 'delete.rs');
  assert.match(deleteSource, /\btombstone_edges_for_calendar_event_delete\b/);
  assert.match(deleteSource, /\benqueue_payload_delete\b/);

  const links = read(`${MODULE_DIR}/links.rs`);
  assertOwnsFunction(links, 'link_tasks_to_calendar_event_with_conn', 'links.rs');
  assertOwnsFunction(links, 'unlink_task_from_calendar_event_with_conn', 'links.rs');
  assert.match(links, /\bEDGE_TASK_CALENDAR_EVENT_LINK\b/);
  assert.match(links, /\benqueue_entity_upsert\b/);

  const providerLinks = read(`${MODULE_DIR}/provider_links.rs`);
  assertOwnsFunction(providerLinks, 'link_task_to_provider_event_with_conn', 'provider_links.rs');
  assertOwnsFunction(providerLinks, 'unlink_task_from_provider_event_with_conn', 'provider_links.rs');
  assert.match(providerLinks, /\bEDGE_TASK_PROVIDER_EVENT_LINK\b/);
  assert.doesNotMatch(
    providerLinks,
    /enqueue_payload_|enqueue_entity_upsert/,
    'provider-local links must not enqueue sync envelopes',
  );

  const exceptions = read(`${MODULE_DIR}/exceptions.rs`);
  assert.match(exceptions, /\nenum ExceptionOp\b/);
  assertOwnsFunction(exceptions, 'mutate_recurrence_exception', 'exceptions.rs');
  assertOwnsFunction(exceptions, 'add_calendar_event_exception_with_conn', 'exceptions.rs');
  assertOwnsFunction(exceptions, 'remove_calendar_event_exception_with_conn', 'exceptions.rs');

  const support = read(`${MODULE_DIR}/support.rs`);
  assert.match(support, /\npub\(super\) fn calendar_write_tx\b/);
  assert.match(support, /\bTransactionBehavior::Immediate\b/);
});
