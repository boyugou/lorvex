import assert from 'node:assert/strict';
import test from 'node:test';

import { asToolResultPayload, createHarness, daysFromTodayYmd, parseJsonContent, requireArrayItem } from '../shared';

interface Habit {
  id: string;
  name: string;
  icon: string | null;
  color: string | null;
  frequency_type: string;
  frequency_value: string | null;
  target_count: number;
  archived: boolean;
}

interface HabitCompletion {
  habit_id: string;
  completed_date: string;
  value: number;
}

interface HabitStats {
  id: string;
  name: string;
  frequency_type: string;
  target_count: number;
  current_streak: number;
  best_streak: number;
  total_completions: number;
  completions_today: number;
  completion_rate_30d: number;
}

interface HabitReminderPolicy {
  id: string;
  habit_id: string;
  habit_name: string;
  reminder_time: string;
  enabled: boolean;
}

// ── create_habit ─────────────────────────────────────────────────────────────

test('create_habit creates a daily habit with defaults', async (t) => {
  const harness = await createHarness('habit-create-daily');
  t.after(async () => { await harness.cleanup(); });

  const result = await harness.client.callTool({
    name: 'create_habit',
    arguments: { name: 'Morning exercise' },
  });
  const habit = parseJsonContent<Habit>(result);

  assert.equal(habit.name, 'Morning exercise');
  assert.equal(habit.frequency_type, 'daily');
  assert.equal(habit.target_count, 1);
  assert.equal(habit.archived, false);
  assert.ok(habit.id, 'habit should have an id');
});

test('create_habit creates a weekly habit with icon and color', async (t) => {
  const harness = await createHarness('habit-create-weekly');
  t.after(async () => { await harness.cleanup(); });

  const result = await harness.client.callTool({
    name: 'create_habit',
    arguments: {
      name: 'Long run',
      frequency_type: 'weekly',
      icon: '🏃',
      color: '#E07B39',
    },
  });
  const habit = parseJsonContent<Habit>(result);

  assert.equal(habit.name, 'Long run');
  assert.equal(habit.frequency_type, 'weekly');
  assert.equal(habit.icon, '🏃');
  assert.equal(habit.color, '#E07B39');
});

test('create_habit rejects invalid frequency_type', async (t) => {
  const harness = await createHarness('habit-create-invalid-freq');
  t.after(async () => { await harness.cleanup(); });

  // 'yearly' is not a valid FrequencyType variant (only daily/weekly/monthly/custom).
  // The MCP SDK rejects unknown variants at deserialization level before the tool handler runs.
  await assert.rejects(
    harness.client.callTool({
      name: 'create_habit',
      arguments: { name: 'Invalid', frequency_type: 'yearly' },
    }),
    (err: any) => err.code === -32602 || String(err.message).includes('unknown variant'),
    'should reject invalid frequency_type at protocol level',
  );
});

// ── get_habits_summary ────────────────────────────────────────────────────────

test('get_habits_summary returns only active habits by default', async (t) => {
  const harness = await createHarness('habit-list-active');
  t.after(async () => { await harness.cleanup(); });
  const { client } = harness;

  await client.callTool({ name: 'create_habit', arguments: { name: 'Active habit' } });

  // Create then archive a habit
  const archivedResult = await client.callTool({
    name: 'create_habit',
    arguments: { name: 'To be archived' },
  });
  const archived = parseJsonContent<Habit>(archivedResult);
  await client.callTool({
    name: 'update_habit',
    arguments: { id: archived.id, archived: true },
  });

  const listResult = await client.callTool({ name: 'get_habits_summary', arguments: {} });
  const habits = parseJsonContent<HabitStats[]>(listResult);
  assert.equal(habits.length, 1, 'Only active habit should be listed');
  assert.equal(requireArrayItem(habits, 0, 'expected active habit').name, 'Active habit');
});

test('get_habits_summary with include_archived returns all habits', async (t) => {
  const harness = await createHarness('habit-list-include-archived');
  t.after(async () => { await harness.cleanup(); });
  const { client } = harness;

  await client.callTool({ name: 'create_habit', arguments: { name: 'Active' } });

  const archivedResult = await client.callTool({
    name: 'create_habit',
    arguments: { name: 'Archived' },
  });
  const archived = parseJsonContent<Habit>(archivedResult);
  await client.callTool({
    name: 'update_habit',
    arguments: { id: archived.id, archived: true },
  });

  const listResult = await client.callTool({
    name: 'get_habits_summary',
    arguments: { include_archived: true },
  });
  const habits = parseJsonContent<HabitStats[]>(listResult);
  assert.equal(habits.length, 2, 'Both active and archived habits should be returned');
});

// ── complete_habit / uncomplete_habit ────────────────────────────────────────

test('complete_habit records a completion for today', async (t) => {
  const harness = await createHarness('habit-complete-today');
  t.after(async () => { await harness.cleanup(); });
  const { client } = harness;

  const createResult = await client.callTool({
    name: 'create_habit',
    arguments: { name: 'Meditation' },
  });
  const habit = parseJsonContent<Habit>(createResult);

  const today = daysFromTodayYmd(0);
  const completeResult = await client.callTool({
    name: 'complete_habit',
    arguments: { id: habit.id },
  });
  const completion = parseJsonContent<HabitCompletion>(completeResult);
  assert.equal(completion.habit_id, habit.id);
  assert.equal(completion.completed_date, today);
  assert.equal(completion.value, 1);
});

test('complete_habit increments value on repeated calls (supports target_count > 1)', async (t) => {
  const harness = await createHarness('habit-complete-increment');
  t.after(async () => { await harness.cleanup(); });
  const { client } = harness;

  const createResult = await client.callTool({
    name: 'create_habit',
    arguments: { name: 'Drink Water', target_count: 3 },
  });
  const habit = parseJsonContent<Habit>(createResult);

  await client.callTool({ name: 'complete_habit', arguments: { id: habit.id } });
  const secondResult = await client.callTool({
    name: 'complete_habit',
    arguments: { id: habit.id },
  });
  const completion = parseJsonContent<HabitCompletion>(secondResult);
  assert.equal(completion.value, 2, 'Second completion should increment value to 2');

  const thirdResult = await client.callTool({
    name: 'complete_habit',
    arguments: { id: habit.id },
  });
  const completion3 = parseJsonContent<HabitCompletion>(thirdResult);
  assert.equal(completion3.value, 3, 'Third completion should reach target_count');

  // Verify only 1 row exists (UNIQUE on habit_id+date); value holds the count
  const completionsResult = await client.callTool({
    name: 'get_habit_completions',
    arguments: { id: habit.id, days: 7 },
  });
  const payload = parseJsonContent<{
    habit_id: string;
    days: number;
    completions: HabitCompletion[];
  }>(completionsResult);
  assert.equal(payload.completions.length, 1, 'Should be 1 row with value = 3');
  assert.equal(requireArrayItem(payload.completions, 0, 'expected habit completion').value, 3);
});

test('uncomplete_habit removes a completion', async (t) => {
  const harness = await createHarness('habit-uncomplete');
  t.after(async () => { await harness.cleanup(); });
  const { client } = harness;

  const createResult = await client.callTool({
    name: 'create_habit',
    arguments: { name: 'Journaling' },
  });
  const habit = parseJsonContent<Habit>(createResult);

  await client.callTool({ name: 'complete_habit', arguments: { id: habit.id } });

  const uncompleteResult = await client.callTool({
    name: 'uncomplete_habit',
    arguments: { id: habit.id },
  });
  const payload = parseJsonContent<{ deleted: boolean; habit_id: string }>(uncompleteResult);
  assert.equal(payload.deleted, true);
  assert.equal(payload.habit_id, habit.id);

  // Verify the completion is gone by querying via MCP
  const completionsResult = await client.callTool({
    name: 'get_habit_completions',
    arguments: { id: habit.id, days: 7 },
  });
  const completionsPayload = parseJsonContent<{
    completions: HabitCompletion[];
  }>(completionsResult);
  const today = daysFromTodayYmd(0);
  const todayCompletion = completionsPayload.completions.find(
    (c) => c.completed_date === today,
  );
  assert.equal(todayCompletion, undefined, 'Completion should be deleted');
});

test('uncomplete_habit errors if no completion exists', async (t) => {
  const harness = await createHarness('habit-uncomplete-missing');
  t.after(async () => { await harness.cleanup(); });
  const { client } = harness;

  const createResult = await client.callTool({
    name: 'create_habit',
    arguments: { name: 'No completions' },
  });
  const habit = parseJsonContent<Habit>(createResult);

  const result = await client.callTool({
    name: 'uncomplete_habit',
    arguments: { id: habit.id },
  });
  const payload = asToolResultPayload(result);
  assert.equal(payload.isError, true, 'should return an MCP error when no completion exists');
  const error = parseJsonContent<{ kind: string; message: string; retryable: boolean }>(result);
  assert.equal(error.kind, 'not_found');
  assert.match(error.message, /no completion found for habit/i);
  assert.equal(error.retryable, false);
});

// ── get_habit_stats ───────────────────────────────────────────────────────────

test('get_habit_stats returns zero-stats for new habit with no completions', async (t) => {
  const harness = await createHarness('habit-stats-empty');
  t.after(async () => { await harness.cleanup(); });
  const { client } = harness;

  const createResult = await client.callTool({
    name: 'create_habit',
    arguments: { name: 'New habit' },
  });
  const habit = parseJsonContent<Habit>(createResult);

  const statsResult = await client.callTool({
    name: 'get_habit_stats',
    arguments: { id: habit.id },
  });
  const stats = parseJsonContent<HabitStats>(statsResult);
  assert.equal(stats.current_streak, 0);
  assert.equal(stats.best_streak, 0);
  assert.equal(stats.total_completions, 0);
  assert.equal(stats.completions_today, 0);
});

test('get_habit_stats computes current_streak after completing today', async (t) => {
  const harness = await createHarness('habit-stats-streak');
  t.after(async () => { await harness.cleanup(); });
  const { client } = harness;

  const createResult = await client.callTool({
    name: 'create_habit',
    arguments: { name: 'Streak habit' },
  });
  const habit = parseJsonContent<Habit>(createResult);

  await client.callTool({ name: 'complete_habit', arguments: { id: habit.id } });

  const statsResult = await client.callTool({
    name: 'get_habit_stats',
    arguments: { id: habit.id },
  });
  const stats = parseJsonContent<HabitStats>(statsResult);
  assert.equal(stats.current_streak, 1, 'streak should be 1 after completing today');
  assert.equal(stats.total_completions, 1);
  assert.equal(stats.completions_today, 1);
});

// ── update_habit ──────────────────────────────────────────────────────────────

test('update_habit updates name and cascades to reminder policies', async (t) => {
  const harness = await createHarness('habit-update-name-cascade');
  t.after(async () => { await harness.cleanup(); });
  const { client } = harness;

  const createResult = await client.callTool({
    name: 'create_habit',
    arguments: { name: 'Old name' },
  });
  const habit = parseJsonContent<Habit>(createResult);

  // Create a reminder policy linked by habit_id
  await client.callTool({
    name: 'upsert_habit_reminder_policy',
    arguments: { habit_id: habit.id, reminder_time: '08:00' },
  });

  await client.callTool({
    name: 'update_habit',
    arguments: { id: habit.id, name: 'New name' },
  });

  // Verify the cascade via get_habit_reminder_policies
  const policiesResult = await client.callTool({
    name: 'get_habit_reminder_policies',
    arguments: {},
  });
  const policies = parseJsonContent<HabitReminderPolicy[]>(policiesResult);
  const policy = policies.find((p) => p.habit_id === habit.id);
  assert.ok(policy, 'Reminder policy should still exist after rename');
  assert.equal(policy.habit_name, 'New name', 'Reminder policy habit_name should cascade on rename');
});

// ── delete_habit ──────────────────────────────────────────────────────────────

test('delete_habit removes habit and cascades to completions', async (t) => {
  const harness = await createHarness('habit-delete-cascade');
  t.after(async () => { await harness.cleanup(); });
  const { client } = harness;

  const createResult = await client.callTool({
    name: 'create_habit',
    arguments: { name: 'To delete' },
  });
  const habit = parseJsonContent<Habit>(createResult);
  await client.callTool({ name: 'complete_habit', arguments: { id: habit.id } });

  const deleteResult = await client.callTool({
    name: 'delete_habit',
    arguments: { id: habit.id },
  });
  const payload = parseJsonContent<{
    deleted: boolean;
    id: string;
    completions_destroyed: number;
    reminder_policies_destroyed: number;
  }>(deleteResult);
  assert.equal(payload.deleted, true);
  assert.equal(payload.id, habit.id);
  // Issue #2366: the response must surface the count of cascaded
  // child rows so long-term streak loss is never silent.
  assert.equal(
    payload.completions_destroyed,
    1,
    'delete_habit must report the number of completions cascaded',
  );
  assert.equal(
    payload.reminder_policies_destroyed,
    0,
    'delete_habit must report the number of reminder policies cascaded',
  );

  // Verify the habit is gone — get_habits_summary (including archived) must not return it
  const listResult = await client.callTool({
    name: 'get_habits_summary',
    arguments: { include_archived: true },
  });
  const habits = parseJsonContent<HabitStats[]>(listResult);
  const found = habits.find((h) => h.id === habit.id);
  assert.equal(found, undefined, 'Habit should be deleted');

  // Verify completions cascade — get_habit_completions returns "habit not found" error
  // because the habit row (and its ON DELETE CASCADE completions) are gone
  const completionsResult = await client.callTool({
    name: 'get_habit_completions',
    arguments: { id: habit.id, days: 7 },
  });
  const completionsText =
    asToolResultPayload(completionsResult).content?.find((c) => c.type === 'text')?.text ?? '';
  assert.ok(
    completionsText.toLowerCase().includes('error') ||
      completionsText.toLowerCase().includes('not found'),
    'get_habit_completions should error for a deleted habit (confirms cascade)',
  );
});

// ── get_habit_completions ─────────────────────────────────────────────────────

test('get_habit_completions returns completions within range', async (t) => {
  const harness = await createHarness('habit-get-completions');
  t.after(async () => { await harness.cleanup(); });
  const { client } = harness;

  const createResult = await client.callTool({
    name: 'create_habit',
    arguments: { name: 'Daily reading' },
  });
  const habit = parseJsonContent<Habit>(createResult);

  const today = daysFromTodayYmd(0);
  await client.callTool({
    name: 'complete_habit',
    arguments: { id: habit.id, date: today },
  });

  const completionsResult = await client.callTool({
    name: 'get_habit_completions',
    arguments: { id: habit.id, days: 7 },
  });
  const completionsPayload = parseJsonContent<{
    habit_id: string;
    days: number;
    completions: HabitCompletion[];
  }>(completionsResult);

  assert.equal(completionsPayload.habit_id, habit.id);
  assert.equal(completionsPayload.days, 7);
  assert.equal(completionsPayload.completions.length, 1);
  assert.equal(requireArrayItem(completionsPayload.completions, 0, 'expected habit completion').completed_date, today);
});

// ── get_habits_summary ────────────────────────────────────────────────────────

test('get_habits_summary returns all habits with stats in one call', async (t) => {
  const harness = await createHarness('habits-summary-batch');
  t.after(async () => { await harness.cleanup(); });
  const { client } = harness;

  // Create two habits
  const r1 = await client.callTool({
    name: 'create_habit',
    arguments: { name: 'Meditate', frequency_type: 'daily' },
  });
  const h1 = parseJsonContent<Habit>(r1);

  const r2 = await client.callTool({
    name: 'create_habit',
    arguments: { name: 'Long run', frequency_type: 'weekly' },
  });
  const h2 = parseJsonContent<Habit>(r2);

  // Complete the first habit today
  await client.callTool({ name: 'complete_habit', arguments: { id: h1.id } });

  // get_habits_summary should return both habits with stats
  const summaryResult = await client.callTool({
    name: 'get_habits_summary',
    arguments: {},
  });
  const summary = parseJsonContent<HabitStats[]>(summaryResult);

  assert.equal(summary.length, 2, 'Should return both habits');

  const s1 = summary.find((h) => h.id === h1.id);
  const s2 = summary.find((h) => h.id === h2.id);
  assert.ok(s1, 'Should include first habit');
  assert.ok(s2, 'Should include second habit');

  // Completed habit should show stats
  assert.equal(s1.completions_today, 1);
  assert.equal(s1.current_streak, 1);
  assert.equal(s1.total_completions, 1);

  // Unstarted habit should show zeros
  assert.equal(s2.completions_today, 0);
  assert.equal(s2.current_streak, 0);
  assert.equal(s2.total_completions, 0);
});

test('get_habits_summary excludes archived habits by default', async (t) => {
  const harness = await createHarness('habits-summary-archived');
  t.after(async () => { await harness.cleanup(); });
  const { client } = harness;

  const r1 = await client.callTool({
    name: 'create_habit',
    arguments: { name: 'Active habit' },
  });
  const active = parseJsonContent<Habit>(r1);

  const r2 = await client.callTool({
    name: 'create_habit',
    arguments: { name: 'Archived habit' },
  });
  const archived = parseJsonContent<Habit>(r2);

  await client.callTool({
    name: 'update_habit',
    arguments: { id: archived.id, archived: true },
  });

  // Default: exclude archived
  const defaultResult = await client.callTool({
    name: 'get_habits_summary',
    arguments: {},
  });
  const defaultSummary = parseJsonContent<HabitStats[]>(defaultResult);
  assert.ok(defaultSummary.find((h) => h.id === active.id), 'Active habit should appear');
  assert.equal(defaultSummary.find((h) => h.id === archived.id), undefined, 'Archived should be excluded by default');

  // With include_archived: true
  const allResult = await client.callTool({
    name: 'get_habits_summary',
    arguments: { include_archived: true },
  });
  const allSummary = parseJsonContent<HabitStats[]>(allResult);
  assert.ok(allSummary.find((h) => h.id === active.id), 'Active should appear');
  assert.ok(allSummary.find((h) => h.id === archived.id), 'Archived should appear with include_archived: true');
});

// ── batch_complete_habit ──────────────────────────────────────────────────────

test('batch_complete_habit completes multiple habits in one call', async (t) => {
  const harness = await createHarness('habits-batch-complete');
  t.after(async () => { await harness.cleanup(); });
  const { client } = harness;

  // Create three habits
  const [r1, r2, r3] = await Promise.all([
    client.callTool({ name: 'create_habit', arguments: { name: 'Meditate' } }),
    client.callTool({ name: 'create_habit', arguments: { name: 'Exercise' } }),
    client.callTool({ name: 'create_habit', arguments: { name: 'Read' } }),
  ]);
  const h1 = parseJsonContent<Habit>(r1);
  const h2 = parseJsonContent<Habit>(r2);
  const h3 = parseJsonContent<Habit>(r3);

  const batchResult = await client.callTool({
    name: 'batch_complete_habit',
    arguments: { habit_ids: [h1.id, h2.id, h3.id] },
  });
  const payload = parseJsonContent<{
    results: Array<{ habit_id: string; completion?: HabitCompletion; error?: string }>;
    count: number;
  }>(batchResult);

  assert.equal(payload.count, 3, 'count should be 3');
  assert.equal(payload.results.length, 3, 'results array should have 3 entries');

  // Each result should have a completion, not an error
  for (const r of payload.results) {
    assert.ok(r.completion, `habit ${r.habit_id} should have a completion`);
    assert.equal(r.completion!.value, 1, 'value should be 1 after first completion');
    assert.ok(!r.error, `habit ${r.habit_id} should not have an error`);
  }
});

test('batch_complete_habit reports individual errors without failing the whole batch', async (t) => {
  const harness = await createHarness('habits-batch-complete-partial-fail');
  t.after(async () => { await harness.cleanup(); });
  const { client } = harness;

  const r1 = await client.callTool({ name: 'create_habit', arguments: { name: 'Valid habit' } });
  const validHabit = parseJsonContent<Habit>(r1);

  const batchResult = asToolResultPayload(await client.callTool({
    name: 'batch_complete_habit',
    arguments: { habit_ids: [validHabit.id, 'nonexistent-id-xyz'] },
  }));
  const payload = parseJsonContent<{ kind: string; message: string; retryable: boolean }>(batchResult);

  assert.equal(batchResult.isError, true);
  assert.equal(payload.kind, 'not_found');
  assert.match(payload.message, /habit not found: nonexistent-id-xyz/);
  assert.equal(payload.retryable, false);

  const completionsPayload = parseJsonContent<{ completions: HabitCompletion[] }>(await client.callTool({
    name: 'get_habit_completions',
    arguments: { id: validHabit.id },
  }));
  assert.deepEqual(
    completionsPayload.completions,
    [],
    'atomic batch_complete_habit should roll back valid completions on failure',
  );
});
