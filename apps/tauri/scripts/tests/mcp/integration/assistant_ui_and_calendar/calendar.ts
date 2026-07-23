import assert from 'node:assert/strict';
import test from 'node:test';
import Database from 'better-sqlite3';

import {
  asToolResultPayload,
  createHarness,
  getFirstTextContent,
  parseJsonContent,
  parseTaskEnvelope,
  requireArrayItem,
  TEST_AGENT_NAME,
} from '../shared';

function assertCalendarTitleValidationError(result: ReturnType<typeof asToolResultPayload>): void {
  const payload = parseJsonContent<{ kind: string; message: string; retryable: boolean }>(result);
  assert.equal(payload.kind, 'validation');
  assert.match(payload.message, /calendar event title must not be empty/i);
  assert.equal(payload.retryable, false);
}

test('create_calendar_event rejects string boolean all_day values under the strict runtime contract', async (t) => {
  const harness = await createHarness('calendar-strict-all-day');
  t.after(async () => {
    await harness.cleanup();
  });

  await assert.rejects(
    harness.client.callTool({
      name: 'create_calendar_event',
      arguments: {
        title: 'String bool calendar event',
        start_date: '2026-03-10',
        start_time: '09:00',
        end_time: '10:00',
        all_day: 'false',
        source: 'mcp',
      },
    }),
    /expected a boolean/i,
    'Expected string "false" to be rejected for all_day',
  );
});

test('create_calendar_event rejects whitespace-only titles after trimming', async (t) => {
  const harness = await createHarness('calendar-title-trimmed-validation');
  t.after(async () => {
    await harness.cleanup();
  });

  const result = asToolResultPayload(await harness.client.callTool({
    name: 'create_calendar_event',
    arguments: {
      title: '   ',
      start_date: '2026-03-10',
      all_day: true,
      source: 'mcp',
    },
  }));

  assert.equal(result.isError, true, 'Expected whitespace-only calendar titles to be rejected');
  assertCalendarTitleValidationError(result);

  const db = new Database(harness.dbPath, { readonly: true, fileMustExist: true });
  t.after(() => db.close());

  const eventCount = db.prepare('SELECT COUNT(*) AS count FROM calendar_events').get() as { count: number };
  assert.equal(eventCount.count, 0, 'Expected rejected calendar event to leave no rows behind');
});

test('update_calendar_event rejects whitespace-only title patches after trimming', async (t) => {
  const harness = await createHarness('calendar-update-title-trimmed-validation');
  t.after(async () => {
    await harness.cleanup();
  });

  const createResult = parseJsonContent<{ id: string }>(await harness.client.callTool({
    name: 'create_calendar_event',
    arguments: {
      title: 'Existing calendar event',
      start_date: '2026-03-10',
      all_day: true,
      source: 'mcp',
    },
  }));

  const updateResult = asToolResultPayload(await harness.client.callTool({
    name: 'update_calendar_event',
    arguments: {
      id: createResult.id,
      title: '   ',
    },
  }));
  assert.equal(updateResult.isError, true, 'Expected whitespace-only title patches to be rejected');
  assertCalendarTitleValidationError(updateResult);

  const db = new Database(harness.dbPath, { readonly: true, fileMustExist: true });
  t.after(() => db.close());
  const persistedEvent = db.prepare('SELECT title FROM calendar_events WHERE id = ?').get(createResult.id) as {
    title: string;
  } | undefined;
  assert.ok(persistedEvent, 'Expected original calendar event to remain present');
  assert.equal(persistedEvent.title, 'Existing calendar event');
});

test('batch_create_calendar_events creates multiple events and records sync activity once', async (t) => {
  const harness = await createHarness('calendar-batch-create');
  t.after(async () => {
    await harness.cleanup();
  });

  const rawResult = await harness.client.callTool({
    name: 'batch_create_calendar_events',
    arguments: {
      events: [
        {
          title: 'Team standup',
          start_date: '2026-03-10',
          start_time: '09:00',
          end_time: '09:15',
          all_day: false,
          source: 'mcp',
        },
        {
          title: 'Weekly planning',
          start_date: '2026-03-11',
          start_time: '11:00',
          end_time: '11:45',
          recurrence: '{"FREQ":"WEEKLY","BYDAY":["WE"]}',
          source: 'manual',
        },
      ],
    },
  });
  const result = asToolResultPayload(rawResult);
  assert.equal(result.isError, false, 'Expected batch_create_calendar_events to succeed');

  const payload = parseJsonContent<{
    created_count: number;
    calendar_events: Array<{
      id: string;
      title: string;
      start_date: string;
      start_time: string | null;
      end_time: string | null;
      recurrence: string | null;
      created_at: string;
      updated_at: string;
      version: string;
    }>;
  }>(result);
  assert.equal(payload.created_count, 2);
  assert.equal(payload.calendar_events.length, 2);
  const sortedEvents = payload.calendar_events.sort((a, b) => a.title.localeCompare(b.title));
  const standupEvent = requireArrayItem(sortedEvents, 0, 'expected standup calendar event');
  const planningEvent = requireArrayItem(sortedEvents, 1, 'expected planning calendar event');
  assert.equal(standupEvent.title, 'Team standup');
  assert.equal(standupEvent.start_date, '2026-03-10');
  assert.equal(standupEvent.start_time, '09:00');
  assert.equal(standupEvent.end_time, '09:15');
  assert.match(standupEvent.created_at, /^\d{4}-\d{2}-\d{2}T/);
  assert.match(standupEvent.updated_at, /^\d{4}-\d{2}-\d{2}T/);
  assert.match(standupEvent.version, /^\d+_/);
  assert.equal(planningEvent.title, 'Weekly planning');
  assert.equal(planningEvent.start_date, '2026-03-11');
  assert.match(planningEvent.recurrence ?? '', /"FREQ":"WEEKLY"/);
  assert.match(planningEvent.recurrence ?? '', /"BYDAY":\["WE"\]/);

  const db = new Database(harness.dbPath, { readonly: true, fileMustExist: true });
  t.after(() => db.close());

  const eventCount = db.prepare('SELECT COUNT(*) AS count FROM calendar_events').get() as { count: number };
  assert.equal(eventCount.count, 2);

  const changelogRow = db.prepare(`
    SELECT operation, entity_type, initiated_by, mcp_tool
    FROM ai_changelog
    ORDER BY timestamp DESC
    LIMIT 1
  `).get() as {
    operation: string;
    entity_type: string;
    initiated_by: string;
    mcp_tool: string;
  } | undefined;
  assert.ok(changelogRow, 'Expected ai_changelog record for batch_create_calendar_events');
  assert.equal(changelogRow.operation, 'batch_create');
  assert.equal(changelogRow.entity_type, 'calendar_event');
  assert.equal(changelogRow.initiated_by, TEST_AGENT_NAME);
  assert.equal(changelogRow.mcp_tool, 'batch_create_calendar_events');

  const syncEventCount = db.prepare('SELECT COUNT(*) AS count FROM sync_outbox').get() as { count: number };
  // 2 calendar event upserts + 1 ai_changelog upsert = 3 total sync rows
  assert.equal(syncEventCount.count, 3, 'Expected sync rows for 2 calendar events + 1 ai_changelog entry');
});

test('batch_create_calendar_events rolls back all inserts when any event is invalid', async (t) => {
  const harness = await createHarness('calendar-batch-atomicity');
  t.after(async () => {
    await harness.cleanup();
  });

  const rawResult = await harness.client.callTool({
    name: 'batch_create_calendar_events',
    arguments: {
      events: [
        {
          title: 'Valid first event',
          start_date: '2026-03-10',
          start_time: '09:00',
          end_time: '09:30',
          source: 'mcp',
        },
        {
          title: '   ',
          start_date: '2026-03-11',
          all_day: true,
          source: 'manual',
        },
      ],
    },
  });
  const result = asToolResultPayload(rawResult);
  assert.equal(result.isError, true, 'Expected batch_create_calendar_events to fail when any event is invalid');
  assertCalendarTitleValidationError(result);

  const db = new Database(harness.dbPath, { readonly: true, fileMustExist: true });
  t.after(() => db.close());

  const eventCount = db.prepare('SELECT COUNT(*) AS count FROM calendar_events').get() as { count: number };
  assert.equal(eventCount.count, 0, 'Expected invalid batch create to leave no calendar events behind');

  const changelogCount = db.prepare('SELECT COUNT(*) AS count FROM ai_changelog').get() as { count: number };
  assert.equal(changelogCount.count, 0, 'Expected invalid batch create to avoid writing ai_changelog');

  const syncEventCount = db.prepare('SELECT COUNT(*) AS count FROM sync_outbox').get() as { count: number };
  assert.equal(syncEventCount.count, 0, 'Expected invalid batch create to avoid writing sync_outbox');
});

test('calendar event link, exception, export, and cascade delete contracts stay coherent', async (t) => {
  const harness = await createHarness('calendar-link-export-lifecycle');
  t.after(async () => {
    await harness.cleanup();
  });

  const createTask = async (title: string) =>
    parseTaskEnvelope<{ id: string }>(await harness.client.callTool({
      name: 'create_task',
      arguments: {
        title,
        raw_input: title,
      },
    }));

  const [taskA, taskB, taskC] = await Promise.all([
    createTask('Calendar linked task A'),
    createTask('Calendar linked task B'),
    createTask('Calendar linked task C'),
  ]);

  const createdEvent = parseJsonContent<{
    id: string;
    title: string;
    recurrence_exceptions: string | null;
  }>(await harness.client.callTool({
    name: 'create_calendar_event',
    arguments: {
      title: 'Recurring Link Event',
      start_date: '2026-03-15',
      start_time: '09:00',
      end_time: '10:00',
      recurrence: '{"FREQ":"WEEKLY","BYDAY":["SU"]}',
      source: 'mcp',
    },
  }));
  assert.equal(createdEvent.title, 'Recurring Link Event');
  assert.equal(createdEvent.recurrence_exceptions, '[]');

  const linkedTaskA = parseJsonContent<{
    task_id: string;
    calendar_event_id: string;
    created_at: string;
    updated_at: string;
  }>(await harness.client.callTool({
    name: 'link_task_to_event',
    arguments: {
      task_id: taskA.id,
      event_id: createdEvent.id,
    },
  }));
  assert.equal(linkedTaskA.task_id, taskA.id);
  assert.equal(linkedTaskA.calendar_event_id, createdEvent.id);

  const batchLinked = parseJsonContent<{
    linked_count: number;
    links: Array<{ task_id: string; calendar_event_id: string }>;
  }>(await harness.client.callTool({
    name: 'batch_link_tasks_to_event',
    arguments: {
      task_ids: [taskB.id, taskC.id],
      event_id: createdEvent.id,
    },
  }));
  assert.equal(batchLinked.linked_count, 2);
  assert.deepEqual(
    batchLinked.links.map((link) => link.task_id).sort(),
    [taskB.id, taskC.id].sort(),
  );

  const taskALinks = parseJsonContent<Array<{
    task_id: string;
    calendar_event_id: string;
    created_at: string;
    updated_at: string;
  }>>(await harness.client.callTool({
    name: 'get_linked_events_for_task',
    arguments: { task_id: taskA.id },
  }));
  assert.equal(taskALinks.length, 1);
  const taskALink = requireArrayItem(taskALinks, 0, 'expected task A calendar link');
  assert.equal(taskALink.task_id, taskA.id);
  assert.equal(taskALink.calendar_event_id, createdEvent.id);
  assert.match(taskALink.created_at, /^\d{4}-\d{2}-\d{2}T/);
  assert.match(taskALink.updated_at, /^\d{4}-\d{2}-\d{2}T/);

  const linkedTasksBeforeUnlink = parseJsonContent<Array<{
    task_id: string;
    calendar_event_id: string;
  }>>(await harness.client.callTool({
    name: 'get_linked_tasks_for_event',
    arguments: { event_id: createdEvent.id },
  }));
  assert.deepEqual(
    linkedTasksBeforeUnlink.map((link) => link.task_id).sort(),
    [taskA.id, taskB.id, taskC.id].sort(),
  );

  const taskAUnlinkResult = parseJsonContent<{
    deleted: boolean;
    task_id: string;
    event_id: string;
    links: Array<{ task_id: string; calendar_event_id: string }>;
  }>(await harness.client.callTool({
    name: 'unlink_task_from_event',
    arguments: {
      task_id: taskA.id,
      event_id: createdEvent.id,
    },
  }));
  assert.equal(taskAUnlinkResult.deleted, true);
  assert.equal(taskAUnlinkResult.task_id, taskA.id);
  assert.equal(taskAUnlinkResult.event_id, createdEvent.id);
  assert.deepEqual(taskAUnlinkResult.links, []);

  const linkedTasksAfterUnlink = parseJsonContent<Array<{
    task_id: string;
    calendar_event_id: string;
  }>>(await harness.client.callTool({
    name: 'get_linked_tasks_for_event',
    arguments: { event_id: createdEvent.id },
  }));
  assert.deepEqual(
    linkedTasksAfterUnlink.map((link) => link.task_id).sort(),
    [taskB.id, taskC.id].sort(),
  );

  const eventWithException = parseJsonContent<{
    id: string;
    recurrence_exceptions: string | null;
  }>(await harness.client.callTool({
    name: 'add_event_exception',
    arguments: {
      event_id: createdEvent.id,
      date: '2026-03-22',
    },
  }));
  assert.equal(eventWithException.id, createdEvent.id);
  assert.equal(eventWithException.recurrence_exceptions, '["2026-03-22"]');

  const icsWithException = getFirstTextContent(await harness.client.callTool({
    name: 'export_calendar_ics',
    arguments: {
      from: '2026-03-01',
      to: '2026-03-31',
    },
  }));
  assert.match(icsWithException, /^BEGIN:VCALENDAR/m);
  assert.match(icsWithException, new RegExp(`UID:${createdEvent.id}@lorvex`));
  assert.match(icsWithException, /SUMMARY:Recurring Link Event/);
  assert.match(icsWithException, /RRULE:FREQ=WEEKLY;BYDAY=SU/);
  assert.match(icsWithException, /EXDATE:20260322T090000Z/);

  const eventWithoutException = parseJsonContent<{
    id: string;
    recurrence_exceptions: string | null;
  }>(await harness.client.callTool({
    name: 'remove_event_exception',
    arguments: {
      event_id: createdEvent.id,
      date: '2026-03-22',
    },
  }));
  assert.equal(eventWithoutException.id, createdEvent.id);
  assert.equal(eventWithoutException.recurrence_exceptions, '[]');

  const icsWithoutException = getFirstTextContent(await harness.client.callTool({
    name: 'export_calendar_ics',
    arguments: {
      from: '2026-03-01',
      to: '2026-03-31',
    },
  }));
  assert.match(icsWithoutException, /^BEGIN:VCALENDAR/m);
  assert.match(icsWithoutException, new RegExp(`UID:${createdEvent.id}@lorvex`));
  assert.match(icsWithoutException, /SUMMARY:Recurring Link Event/);
  assert.match(icsWithoutException, /RRULE:FREQ=WEEKLY;BYDAY=SU/);
  assert.doesNotMatch(icsWithoutException, /EXDATE:/);

  const deletedEvent = parseJsonContent<{
    id: string;
    deleted: boolean;
    unlinked_task_ids: string[];
  }>(await harness.client.callTool({
    name: 'delete_calendar_event',
    arguments: { id: createdEvent.id },
  }));
  assert.equal(deletedEvent.id, createdEvent.id);
  assert.equal(deletedEvent.deleted, true);
  assert.deepEqual(deletedEvent.unlinked_task_ids.sort(), [taskB.id, taskC.id].sort());

  const db = new Database(harness.dbPath, { readonly: true, fileMustExist: true });
  t.after(() => db.close());

  const persistedEvent = db.prepare('SELECT id FROM calendar_events WHERE id = ?').get(createdEvent.id);
  assert.equal(persistedEvent, undefined, 'Expected delete_calendar_event to remove the event row');

  const danglingLinks = db.prepare(
    'SELECT COUNT(*) AS count FROM task_calendar_event_links WHERE calendar_event_id = ?',
  ).get(createdEvent.id) as { count: number };
  assert.equal(danglingLinks.count, 0, 'Expected cascade delete to remove all event links');

  const changelogRows = db.prepare(`
    SELECT mcp_tool, COUNT(*) AS count
    FROM ai_changelog
    WHERE mcp_tool IN (
      'link_task_to_event',
      'batch_link_tasks_to_event',
      'unlink_task_from_event',
      'add_event_exception',
      'remove_event_exception',
      'delete_calendar_event'
    )
    GROUP BY mcp_tool
  `).all() as Array<{ mcp_tool: string; count: number }>;
  const changelogCounts = Object.fromEntries(changelogRows.map((row) => [row.mcp_tool, row.count]));
  assert.equal(changelogCounts.link_task_to_event, 1);
  assert.equal(changelogCounts.batch_link_tasks_to_event, 2);
  assert.equal(changelogCounts.unlink_task_from_event, 1);
  assert.equal(changelogCounts.add_event_exception, 1);
  assert.equal(changelogCounts.remove_event_exception, 1);
  assert.equal(changelogCounts.delete_calendar_event, 3);

  const edgeDeleteRows = db.prepare(`
    SELECT entity_id
    FROM sync_outbox
    WHERE entity_type = 'task_calendar_event_link' AND operation = 'delete'
    ORDER BY entity_id
  `).all() as Array<{ entity_id: string }>;
  assert.deepEqual(
    edgeDeleteRows.map((row) => row.entity_id),
    [
      `${taskA.id}:${createdEvent.id}`,
      `${taskB.id}:${createdEvent.id}`,
      `${taskC.id}:${createdEvent.id}`,
    ].sort(),
    'Expected sync_outbox to retain delete envelopes for every removed task-calendar edge',
  );

  const calendarDeleteRow = db.prepare(`
    SELECT operation
    FROM sync_outbox
    WHERE entity_type = 'calendar_event' AND entity_id = ?
  `).get(createdEvent.id) as { operation: string } | undefined;
  assert.ok(calendarDeleteRow, 'Expected delete_calendar_event to leave a calendar_event sync row behind');
  assert.equal(calendarDeleteRow.operation, 'delete');
});

test('provider event link lifecycle returns resolved metadata and clears cleanly', async (t) => {
  const harness = await createHarness('calendar-provider-link-lifecycle');
  t.after(async () => {
    await harness.cleanup();
  });

  const createTask = async (title: string) =>
    parseTaskEnvelope<{ id: string }>(await harness.client.callTool({
      name: 'create_task',
      arguments: {
        title,
        raw_input: title,
      },
    }));

  const resolvedTask = await createTask('Provider resolved task');
  const missingTask = await createTask('Provider missing task');
  const unavailableTask = await createTask('Provider unavailable task');

  const db = new Database(harness.dbPath, { fileMustExist: true });
  t.after(() => db.close());
  const providerRefreshAt = new Date().toISOString();

  db.prepare(`
    INSERT INTO provider_calendar_events
      (provider_kind, provider_scope, provider_event_key, title, start_date, start_time, all_day, last_seen_at, last_refreshed_at)
    VALUES
      (@provider_kind, @provider_scope, @provider_event_key, @title, @start_date, @start_time, @all_day, @last_seen_at, @last_refreshed_at)
  `).run({
    provider_kind: 'ical_subscription',
    provider_scope: 'team-feed',
    provider_event_key: 'evt-demo-1',
    title: 'Imported provider event',
    start_date: '2026-04-18',
    start_time: '13:30',
    all_day: 0,
    last_seen_at: '2026-04-18T13:00:00Z',
    last_refreshed_at: '2026-04-18T13:00:00Z',
  });
  db.prepare(`
    INSERT OR REPLACE INTO provider_scope_runtime_state
      (provider_kind, provider_scope, enabled, availability_state, last_refresh_success_at)
    VALUES
      (@provider_kind, @provider_scope, 1, 'enabled', @last_refresh_success_at)
  `).run({
    provider_kind: 'ical_subscription',
    provider_scope: 'team-feed',
    last_refresh_success_at: providerRefreshAt,
  });
  db.prepare(`
    INSERT INTO calendar_subscriptions (id, name, url, color, enabled, version, created_at, updated_at)
    VALUES (?, ?, ?, ?, 1, ?, ?, ?)
  `).run(
    'missing-feed',
    'Missing Feed',
    'https://example.com/missing.ics',
    null,
    '0000000000000_0000_00000000',
    providerRefreshAt,
    providerRefreshAt,
  );
  db.prepare(`
    INSERT OR REPLACE INTO provider_scope_runtime_state
      (provider_kind, provider_scope, enabled, availability_state, last_refresh_success_at)
    VALUES
      (@provider_kind, @provider_scope, 1, 'enabled', @last_refresh_success_at)
  `).run({
    provider_kind: 'ical_subscription',
    provider_scope: 'missing-feed',
    last_refresh_success_at: providerRefreshAt,
  });
  db.prepare(`
    INSERT OR REPLACE INTO provider_scope_runtime_state
      (provider_kind, provider_scope, enabled, availability_state, last_refresh_success_at)
    VALUES
      (@provider_kind, @provider_scope, 1, 'disabled', @last_refresh_success_at)
  `).run({
    provider_kind: 'ical_subscription',
    provider_scope: 'disabled-feed',
    last_refresh_success_at: providerRefreshAt,
  });

  const linkedProviderEvent = parseJsonContent<{
    task_id: string;
    provider_kind: string;
    provider_scope: string;
    provider_event_key: string;
  }>(await harness.client.callTool({
    name: 'link_task_to_provider_event',
    arguments: {
      task_id: resolvedTask.id,
      provider_kind: 'ical_subscription',
      provider_scope: 'team-feed',
      provider_event_key: 'evt-demo-1',
    },
  }));
  assert.equal(linkedProviderEvent.task_id, resolvedTask.id);
  assert.equal(linkedProviderEvent.provider_kind, 'ical_subscription');
  assert.equal(linkedProviderEvent.provider_scope, 'team-feed');
  assert.equal(linkedProviderEvent.provider_event_key, 'evt-demo-1');

  await harness.client.callTool({
    name: 'link_task_to_provider_event',
    arguments: {
      task_id: missingTask.id,
      provider_kind: 'ical_subscription',
      provider_scope: 'missing-feed',
      provider_event_key: 'evt-missing-1',
    },
  });
  await harness.client.callTool({
    name: 'link_task_to_provider_event',
    arguments: {
      task_id: unavailableTask.id,
      provider_kind: 'ical_subscription',
      provider_scope: 'disabled-feed',
      provider_event_key: 'evt-unavailable-1',
    },
  });

  const resolvedLinks = parseJsonContent<Array<{
    task_id: string;
    provider_kind: string;
    provider_scope: string;
    provider_event_key: string;
    event_title: string | null;
    event_start_date: string | null;
    event_start_time: string | null;
    resolution_state: string;
  }>>(await harness.client.callTool({
    name: 'get_provider_event_links_for_task',
    arguments: { task_id: resolvedTask.id },
  }));
  assert.equal(resolvedLinks.length, 1);
  const resolvedLink = requireArrayItem(resolvedLinks, 0, 'expected resolved provider link');
  assert.equal(resolvedLink.task_id, resolvedTask.id);
  assert.equal(resolvedLink.provider_kind, 'ical_subscription');
  assert.equal(resolvedLink.provider_scope, 'team-feed');
  assert.equal(resolvedLink.provider_event_key, 'evt-demo-1');
  assert.equal(resolvedLink.event_title, 'Imported provider event');
  assert.equal(resolvedLink.event_start_date, '2026-04-18');
  assert.equal(resolvedLink.event_start_time, '13:30');
  assert.equal(resolvedLink.resolution_state, 'resolved');

  const missingLinks = parseJsonContent<Array<{
    task_id: string;
    provider_scope: string;
    provider_event_key: string;
    resolution_state: string;
  }>>(await harness.client.callTool({
    name: 'get_provider_event_links_for_task',
    arguments: { task_id: missingTask.id },
  }));
  assert.equal(missingLinks.length, 1);
  const missingLink = requireArrayItem(missingLinks, 0, 'expected missing provider link');
  assert.equal(missingLink.task_id, missingTask.id);
  assert.equal(missingLink.provider_scope, 'missing-feed');
  assert.equal(missingLink.provider_event_key, 'evt-missing-1');
  assert.equal(missingLink.resolution_state, 'missing');

  const unavailableLinks = parseJsonContent<Array<{
    task_id: string;
    provider_scope: string;
    provider_event_key: string;
    resolution_state: string;
  }>>(await harness.client.callTool({
    name: 'get_provider_event_links_for_task',
    arguments: { task_id: unavailableTask.id },
  }));
  assert.equal(unavailableLinks.length, 1);
  const unavailableLink = requireArrayItem(unavailableLinks, 0, 'expected unavailable provider link');
  assert.equal(unavailableLink.task_id, unavailableTask.id);
  assert.equal(unavailableLink.provider_scope, 'disabled-feed');
  assert.equal(unavailableLink.provider_event_key, 'evt-unavailable-1');
  assert.equal(unavailableLink.resolution_state, 'unavailable');

  const remainingProviderLinks = parseJsonContent<Array<{
    task_id: string;
    provider_kind: string;
    provider_scope: string;
    provider_event_key: string;
  }>>(await harness.client.callTool({
    name: 'unlink_task_from_provider_event',
    arguments: {
      task_id: resolvedTask.id,
      provider_kind: 'ical_subscription',
      provider_scope: 'team-feed',
      provider_event_key: 'evt-demo-1',
    },
  }));
  assert.deepEqual(remainingProviderLinks, []);

  const persistedProviderLinks = db.prepare(
    'SELECT COUNT(*) AS count FROM task_provider_event_links WHERE task_id = ?',
  ).get(resolvedTask.id) as { count: number };
  assert.equal(persistedProviderLinks.count, 0, 'Expected unlink_task_from_provider_event to remove the link row');

  const providerLinkOutboxRows = db.prepare(
    'SELECT COUNT(*) AS count FROM sync_outbox WHERE entity_type = ?',
  ).get('task_provider_event_link') as { count: number };
  assert.equal(providerLinkOutboxRows.count, 0, 'Expected provider event links to remain local-only and never enter sync_outbox');

  const providerLinkChangelogRows = db.prepare(`
    SELECT COUNT(*) AS count
    FROM ai_changelog
    WHERE mcp_tool IN ('link_task_to_provider_event', 'unlink_task_from_provider_event')
  `).get() as { count: number };
  assert.equal(providerLinkChangelogRows.count, 4, 'Expected provider link lifecycle operations to still log ai_changelog rows');
});
