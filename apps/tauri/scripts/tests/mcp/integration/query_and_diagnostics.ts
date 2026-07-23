import assert from 'node:assert/strict';
import test from 'node:test';
import Database from 'better-sqlite3';

import {
  createHarness,
  insertListSeed,
  insertTaskSeed,
  parseJsonContent,
  parseTaskEnvelope,
  requireArrayItem,
  requireRecordValue,
  upsertPreference,
} from './shared';

const SEED_VERSION = '0000000000000_0000_00000000';

function insertTagLink(
  db: Database.Database,
  taskId: string,
  tag: { id: string; name: string },
): void {
  const now = new Date().toISOString();
  db.prepare(
    `
      INSERT INTO tags (id, display_name, lookup_key, version, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?)
    `,
  ).run(tag.id, tag.name, tag.name.toLowerCase(), SEED_VERSION, now, now);
  db.prepare(
    `
      INSERT INTO task_tags (task_id, tag_id, version, created_at)
      VALUES (?, ?, ?, ?)
    `,
  ).run(taskId, tag.id, SEED_VERSION, now);
}

function seedUiViewState(db: Database.Database, value: Record<string, unknown>): void {
  db.prepare(
    `
      INSERT INTO device_state (key, value) VALUES (?, ?)
      ON CONFLICT(key) DO UPDATE SET value = excluded.value
    `,
  ).run('ui_view_state', JSON.stringify(value));
}

function insertPendingInboxSeed(
  db: Database.Database,
  taskId: string,
  firstAttemptedAt: string,
): void {
  db.prepare(
    `
      INSERT INTO sync_pending_inbox (
        envelope, reason, missing_entity_type, missing_entity_id,
        envelope_entity_type, envelope_entity_id, envelope_version,
        first_attempted_at, last_attempted_at, attempt_count
      ) VALUES (?, 'fk_unresolved', 'list', 'list-missing', 'task', ?, ?, ?, ?, 1)
    `,
  ).run(
    JSON.stringify({
      entity_type: 'task',
      entity_id: taskId,
      operation: 'upsert',
      version: SEED_VERSION,
      payload_schema_version: 1,
      payload: '{}',
      device_id: 'device-test',
    }),
    taskId,
    SEED_VERSION,
    firstAttemptedAt,
    firstAttemptedAt,
  );
}

test('sync diagnostics tools expose direct MCP queue and checkpoint state', async (t) => {
  const harness = await createHarness('query-sync-diagnostics');
  t.after(async () => {
    await harness.cleanup();
  });

  const created = parseTaskEnvelope<{ id: string }>(await harness.client.callTool({
    name: 'create_task',
    arguments: { title: 'Queued sync task' },
  }));

  const db = new Database(harness.dbPath);
  t.after(() => db.close());
  db.prepare(
    `
      INSERT INTO sync_checkpoints (key, value) VALUES (?, ?)
      ON CONFLICT(key) DO UPDATE SET value = excluded.value
    `,
  ).run('reseed_required', 'true');
  insertPendingInboxSeed(db, created.id, '2026-04-01T08:00:00Z');

  const status = parseJsonContent<{
    pending_count: number;
    pending_inbox_count: number;
    pending_inbox_oldest_at: string | null;
    reseed_required: boolean;
  }>(await harness.client.callTool({
    name: 'get_sync_status',
    arguments: {},
  }));
  assert.ok(status.pending_count >= 1);
  assert.equal(status.pending_inbox_count, 1);
  assert.equal(status.pending_inbox_oldest_at, '2026-04-01T08:00:00Z');
  assert.equal(status.reseed_required, true);

  const outboxPage = parseJsonContent<{
    entries: Array<{
      entity_id: string;
      operation: string;
      synced_at: string | null;
    }>;
  }>(await harness.client.callTool({
    name: 'list_pending_outbox_entries',
    arguments: { limit: 10 },
  }));
  assert.ok(outboxPage.entries.length >= 1);
  const taskEntry = outboxPage.entries.find((row) => row.entity_id === created.id);
  assert.ok(taskEntry, 'Expected pending outbox listing to include the created task');
  assert.equal(taskEntry!.operation, 'upsert');
  assert.equal(taskEntry!.synced_at, null);
});

test('reminder query tools have direct MCP integration coverage for due and upcoming rows', async (t) => {
  const harness = await createHarness('query-reminders');
  t.after(async () => {
    await harness.cleanup();
  });

  const now = Date.now();
  const dueAt = new Date(now - 60_000).toISOString();
  const upcomingAt = new Date(now + 60 * 60 * 1000).toISOString();

  const dueTask = parseTaskEnvelope<{ id: string }>(await harness.client.callTool({
    name: 'create_task',
    arguments: { title: 'Due reminder task' },
  }));
  const upcomingTask = parseTaskEnvelope<{ id: string }>(await harness.client.callTool({
    name: 'create_task',
    arguments: { title: 'Upcoming reminder task' },
  }));

  await harness.client.callTool({
    name: 'add_task_reminder',
    arguments: { id: dueTask.id, reminder_at: dueAt },
  });
  await harness.client.callTool({
    name: 'add_task_reminder',
    arguments: { id: upcomingTask.id, reminder_at: upcomingAt },
  });

  const due = parseJsonContent<{
    count: number;
    reminders: Array<{ task_id: string; task_title: string }>;
  }>(await harness.client.callTool({
    name: 'get_due_task_reminders',
    arguments: { limit: 10 },
  }));
  assert.equal(due.count, 1);
  const dueReminder = requireArrayItem(due.reminders, 0, 'expected due reminder row');
  assert.equal(dueReminder.task_id, dueTask.id);
  assert.match(dueReminder.task_title, /Due reminder task/);

  const upcoming = parseJsonContent<{
    count: number;
    hours_window: number;
    reminders: Array<{ task_id: string; task_title: string }>;
  }>(await harness.client.callTool({
    name: 'get_upcoming_task_reminders',
    arguments: { hours: 2, limit: 10 },
  }));
  assert.equal(upcoming.hours_window, 2);
  assert.equal(upcoming.count, 1);
  const upcomingReminder = requireArrayItem(upcoming.reminders, 0, 'expected upcoming reminder row');
  assert.equal(upcomingReminder.task_id, upcomingTask.id);
  assert.match(upcomingReminder.task_title, /Upcoming reminder task/);
});

test('get_ui_view_state reports never-written and fresh projected snapshots through direct MCP tool calls', async (t) => {
  const harness = await createHarness('query-ui-view-state');
  t.after(async () => {
    await harness.cleanup();
  });
  const selectedTaskId = '01966a3f-7c8b-7d4e-8f3a-000000000203';

  const before = parseJsonContent<{
    available: boolean;
    reason: string;
  }>(await harness.client.callTool({
    name: 'get_ui_view_state',
    arguments: {},
  }));
  assert.equal(before.available, false);
  assert.equal(before.reason, 'never_written');

  const db = new Database(harness.dbPath);
  t.after(() => db.close());
  seedUiViewState(db, {
    last_updated_at: new Date().toISOString(),
    active_view: 'list:list-work',
    selected_task_id: selectedTaskId,
    search_query: 'focus',
    list_filter_id: 'list-work',
    tag_filters: ['urgent'],
    priority_filter: 1,
    focus_mode_active: false,
    focus_mode_task_id: null,
  });

  const after = parseJsonContent<{
    available: boolean;
    active_view: string;
    selected_task_id: string | null;
    list_filter_id: string | null;
    tag_filters: string[];
    priority_filter: number | null;
  }>(await harness.client.callTool({
    name: 'get_ui_view_state',
    arguments: {},
  }));
  assert.equal(after.available, true);
  assert.equal(after.active_view, 'list:list-work');
  assert.equal(after.selected_task_id, selectedTaskId);
  assert.equal(after.list_filter_id, 'list-work');
  assert.deepEqual(after.tag_filters, ['urgent']);
  assert.equal(after.priority_filter, 1);
});

test('setup, list, session-context, and log readback tools have direct MCP integration coverage', async (t) => {
  const harness = await createHarness('query-session-and-logs');
  t.after(async () => {
    await harness.cleanup();
  });

  const db = new Database(harness.dbPath);
  t.after(() => db.close());

  const taskOpsId = '019dddf2-0000-7000-8000-000000000001';
  insertListSeed(db, { id: '01966a3f-7c8b-7d4e-8f3a-000000000801', name: 'Ops backlog', color: '#228B22' });
  insertTaskSeed(db, {
    id: taskOpsId,
    title: 'Ops task for session context',
    list_id: '01966a3f-7c8b-7d4e-8f3a-000000000801',
    priority: 2,
  });
  upsertPreference(db, 'working_hours', { start: '09:00', end: '17:00' });

  const sessionDate = parseJsonContent<{ date: string }>(await harness.client.callTool({
    name: 'get_session_context',
    arguments: {},
  })).date;

  const createdEvent = parseJsonContent<{ id: string }>(await harness.client.callTool({
    name: 'create_calendar_event',
    arguments: {
      title: 'Ops calendar review',
      start_date: sessionDate,
      start_time: '10:30',
      end_time: '11:00',
      all_day: false,
    },
  }));

  await harness.client.callTool({
    name: 'set_current_focus',
    arguments: {
      date: sessionDate,
      task_ids: [taskOpsId],
      briefing: 'Keep the ops task moving.',
    },
  });

  db.prepare(
    `
      INSERT INTO ai_changelog (
        id, timestamp, operation, entity_type, entity_id, summary,
        initiated_by, mcp_tool
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    `,
  ).run(
    'log-session',
    `${sessionDate}T10:00:00Z`,
    'update',
    'task',
    taskOpsId,
    'session context changelog entry',
    'ai',
    'integration_seed',
  );
  db.prepare(
    `
      INSERT INTO ai_changelog_entities (changelog_id, entity_id)
      VALUES (?, ?)
    `,
  ).run('log-session', taskOpsId);
  db.prepare(
    `
      INSERT INTO error_logs (id, source, level, message, details, created_at)
      VALUES (?, ?, ?, ?, ?, ?)
    `,
  ).run(
    'error-session',
    'integration-suite',
    'error',
    'Authorization: Bearer session-secret',
    'password=session-password',
    `${sessionDate}T09:00:00Z`,
  );

  const listPage = parseJsonContent<{
    count: number;
    lists: Array<{
      id: string;
      name: string;
      open_count: number;
      total_count: number;
    }>;
  }>(await harness.client.callTool({
    name: 'list_lists',
    arguments: {},
  }));
  assert.ok(listPage.count >= 1);
  const opsList = listPage.lists.find((row) => row.id === '01966a3f-7c8b-7d4e-8f3a-000000000801');
  assert.ok(opsList, 'Expected list_lists to include the seeded ops list');
  assert.equal(opsList!.open_count, 1);
  assert.equal(opsList!.total_count, 1);
  assert.match(opsList!.name, /Ops backlog/);

  const setup = parseJsonContent<{
    setup_completed: boolean;
    setup_state: { working_hours_ready: boolean; normal_task_creation_ready: boolean };
    existing_preferences: Record<string, unknown>;
    list_count: number;
    task_count: number;
  }>(await harness.client.callTool({
    name: 'get_setup_status',
    arguments: {},
  }));
  assert.equal(setup.setup_completed, true);
  assert.equal(setup.setup_state.working_hours_ready, true);
  assert.equal(setup.setup_state.normal_task_creation_ready, true);
  assert.ok('working_hours' in setup.existing_preferences);
  assert.ok(setup.list_count >= 2);
  assert.equal(setup.task_count, 1);

  const currentFocus = parseJsonContent<{
    date: string;
    task_ids: string[];
    briefing: string | null;
    tasks: Array<{ id: string }>;
  }>(await harness.client.callTool({
    name: 'get_current_focus',
    arguments: { date: sessionDate },
  }));
  assert.equal(currentFocus.date, sessionDate);
  assert.deepEqual(currentFocus.task_ids, [taskOpsId]);
  assert.equal(currentFocus.briefing, 'Keep the ops task moving.');
  assert.deepEqual(
    currentFocus.tasks.map((task) => task.id),
    [taskOpsId],
  );

  const calendarEvents = parseJsonContent<{
    from: string;
    to: string;
    count: number;
    events: Array<{ id: string; title: string }>;
  }>(await harness.client.callTool({
    name: 'get_calendar_events',
    arguments: {
      from: sessionDate,
      to: sessionDate,
      limit: 10,
      include_provider: false,
    },
  }));
  assert.equal(calendarEvents.from, sessionDate);
  assert.equal(calendarEvents.to, sessionDate);
  assert.equal(calendarEvents.count, 1);
  assert.deepEqual(
    calendarEvents.events.map((event) => event.id),
    [createdEvent.id],
  );
  assert.match(requireArrayItem(calendarEvents.events, 0, 'expected calendar event').title, /Ops calendar review/);

  const calendarEvent = parseJsonContent<{
    id: string;
    title: string;
    start_date: string;
  }>(await harness.client.callTool({
    name: 'get_calendar_event',
    arguments: { id: createdEvent.id },
  }));
  assert.equal(calendarEvent.id, createdEvent.id);
  assert.equal(calendarEvent.start_date, sessionDate);
  assert.match(calendarEvent.title, /Ops calendar review/);

  const searchedCalendarEvents = parseJsonContent<{
    count: number;
    events: Array<{ id: string; title: string }>;
  }>(await harness.client.callTool({
    name: 'search_calendar_events',
    arguments: {
      query: 'ops',
      from: sessionDate,
      to: sessionDate,
      limit: 10,
    },
  }));
  assert.equal(searchedCalendarEvents.count, 1);
  assert.deepEqual(
    searchedCalendarEvents.events.map((event) => event.id),
    [createdEvent.id],
  );
  assert.match(requireArrayItem(searchedCalendarEvents.events, 0, 'expected searched calendar event').title, /Ops calendar review/);

  const allPreferences = parseJsonContent<Record<string, unknown>>(await harness.client.callTool({
    name: 'get_all_preferences',
    arguments: {},
  }));
  assert.deepEqual(
    allPreferences.working_hours,
    { start: '09:00', end: '17:00' },
  );

  const completedSetup = parseJsonContent<{
    setup_completed: boolean;
    summary: string;
    setup_completed_preference: { key: string; value: boolean };
    setup_summary_preference: { key: string; value: string };
    setup_state_preference: { key: string; value: { completed_summary: string; completed_via: string } };
  }>(await harness.client.callTool({
    name: 'complete_setup',
    arguments: {
      summary: 'Configured working hours and verified the starter ops workspace.',
    },
  }));
  assert.equal(completedSetup.setup_completed, true);
  assert.equal(
    completedSetup.summary,
    'Configured working hours and verified the starter ops workspace.',
  );
  assert.equal(completedSetup.setup_completed_preference.key, 'setup_completed');
  assert.equal(completedSetup.setup_completed_preference.value, true);
  assert.equal(completedSetup.setup_summary_preference.key, 'setup_summary');
  assert.equal(
    completedSetup.setup_summary_preference.value,
    'Configured working hours and verified the starter ops workspace.',
  );
  assert.equal(completedSetup.setup_state_preference.key, 'setup_state');
  assert.equal(
    completedSetup.setup_state_preference.value.completed_summary,
    'Configured working hours and verified the starter ops workspace.',
  );
  assert.equal(completedSetup.setup_state_preference.value.completed_via, 'complete_setup');

  const setupAfterComplete = parseJsonContent<{
    setup_completed: boolean;
    setup_state: {
      explicit_setup_completed: boolean;
      setup_completed: boolean;
    };
    existing_preferences: Record<string, unknown>;
  }>(await harness.client.callTool({
    name: 'get_setup_status',
    arguments: {},
  }));
  assert.equal(setupAfterComplete.setup_completed, true);
  assert.equal(setupAfterComplete.setup_state.explicit_setup_completed, true);
  assert.equal(setupAfterComplete.setup_state.setup_completed, true);
  assert.equal(setupAfterComplete.existing_preferences.setup_completed, true);
  assert.equal(
    setupAfterComplete.existing_preferences.setup_summary,
    'Configured working hours and verified the starter ops workspace.',
  );

  const sessionContext = parseJsonContent<{
    date: string;
    current_focus: { task_ids: string[] } | null;
    today_events: { events: Array<{ id: string }> };
    overview: { stats: { open_count: number } };
    recent_changelog: { entries: Array<{ id: string }> };
    guide: { topic: string };
  }>(await harness.client.callTool({
    name: 'get_session_context',
    arguments: {},
  }));
  assert.equal(sessionContext.date, sessionDate);
  assert.equal(sessionContext.overview.stats.open_count, 1);
  assert.ok(sessionContext.current_focus, 'Expected get_session_context to include current focus');
  assert.deepEqual(sessionContext.current_focus.task_ids, [taskOpsId]);
  assert.ok(
    sessionContext.today_events.events.some((event) => event.id === createdEvent.id),
    'Expected get_session_context to include the seeded calendar event',
  );
  assert.ok(
    sessionContext.recent_changelog.entries.some((entry) => entry.id === 'log-session'),
    'Expected session context to include the seeded AI changelog entry',
  );
  assert.equal(typeof sessionContext.guide.topic, 'string');

  const changelog = parseJsonContent<{
    entries: Array<{
      id: string;
      entity_id: string | null;
      mcp_tool: string | null;
    }>;
  }>(await harness.client.callTool({
    name: 'get_ai_changelog',
    arguments: { entity_id: taskOpsId, limit: 10 },
  }));
  assert.equal(changelog.entries.length, 1);
  const changelogEntry = requireArrayItem(changelog.entries, 0, 'expected changelog row');
  assert.equal(changelogEntry.id, 'log-session');
  assert.equal(changelogEntry.entity_id, taskOpsId);
  assert.equal(changelogEntry.mcp_tool, 'integration_seed');

  const recentLogs = parseJsonContent<{
    count: number;
    redaction_applied: boolean;
    details_included: boolean;
    source_counts: Record<string, number>;
    entries: Array<{ source: string; summary: string; details?: string }>;
  }>(await harness.client.callTool({
    name: 'get_recent_logs',
    arguments: {
      limit: 10,
      include_details: true,
      redact: true,
      levels: ['error', 'warn', 'info', 'debug'],
      sources: ['error_log', 'ai_changelog'],
    },
  }));
  assert.equal(recentLogs.redaction_applied, true);
  assert.equal(recentLogs.details_included, true);
  assert.ok(requireRecordValue(recentLogs.source_counts, 'error_log', 'expected error_log source count') >= 1);
  assert.ok(requireRecordValue(recentLogs.source_counts, 'ai_changelog', 'expected ai_changelog source count') >= 1);
  assert.ok(recentLogs.count >= 2);
  const errorEntry = recentLogs.entries.find(
    (entry) => entry.source === 'error_log' && entry.summary === 'Authorization: Bearer [REDACTED]',
  );
  assert.ok(errorEntry, 'Expected get_recent_logs to include the seeded error log row');
  assert.equal(errorEntry!.summary, 'Authorization: Bearer [REDACTED]');
  assert.equal(errorEntry!.details, 'password=[REDACTED]');
  assert.ok(
    recentLogs.entries.some(
      (entry) =>
        entry.source === 'ai_changelog' &&
        entry.summary.includes('session context changelog entry'),
    ),
    'Expected get_recent_logs to include the seeded AI changelog row',
  );
});
