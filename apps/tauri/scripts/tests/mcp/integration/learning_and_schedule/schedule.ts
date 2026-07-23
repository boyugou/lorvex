import assert from 'node:assert/strict';
import test from 'node:test';
import Database from 'better-sqlite3';

import {
  createHarness,
  insertTaskSeed,
  daysFromTodayYmd,
  parseJsonContent,
  requireArrayItem,
  resetBehaviorTables,
  upsertPreference,
} from '../shared';

const SCHEDULE_TASK_IDS = {
  defaultDuration: '019dddf2-1000-7000-8000-000000000001',
  bufferA: '019dddf2-1000-7000-8000-000000000002',
  bufferB: '019dddf2-1000-7000-8000-000000000003',
  overflowA: '019dddf2-1000-7000-8000-000000000004',
  overflowB: '019dddf2-1000-7000-8000-000000000005',
  overdue: '019dddf2-1000-7000-8000-000000000006',
  undated: '019dddf2-1000-7000-8000-000000000007',
  future: '019dddf2-1000-7000-8000-000000000008',
} as const;

interface FocusSchedulePayload {
  date: string;
  working_hours: { start: string; end: string };
  total_minutes_available: number;
  slots: Array<{ task: { id: string }; start_time: string; end_time: string }>;
  unscheduled: Array<{ id: string }>;
}

test('propose_daily_schedule deterministic matrix covers defaults, buffers, overflow, and due-date filtering', async (t) => {
  const harness = await createHarness('schedule-deterministic-matrix');
  t.after(async () => {
    await harness.cleanup();
  });
  const db = new Database(harness.dbPath, { fileMustExist: true });
  t.after(() => db.close());

  const today = daysFromTodayYmd(0);
  const tomorrow = daysFromTodayYmd(1);
  const yesterday = daysFromTodayYmd(-1);

  const scheduleCases: Array<{
    name: string;
    setup: (seedDb: Database.Database) => void;
    assertPayload: (payload: FocusSchedulePayload) => void;
  }> = [
    {
      name: 'default working-hours + default 30 minute duration',
      setup: (seedDb) => {
        insertTaskSeed(seedDb, {
          id: SCHEDULE_TASK_IDS.defaultDuration,
          title: 'Default duration task',
          due_date: today,
          estimated_minutes: null,
        });
      },
      assertPayload: (payload) => {
        assert.equal(payload.working_hours.start, '09:00');
        assert.equal(payload.working_hours.end, '18:00');
        assert.equal(payload.total_minutes_available, 540);
        assert.equal(payload.slots.length, 1);
        assert.equal(payload.unscheduled.length, 0);
        const slot = requireArrayItem(payload.slots, 0, 'expected default-duration schedule slot');
        assert.equal(slot.task.id, SCHEDULE_TASK_IDS.defaultDuration);
        assert.equal(slot.start_time, '09:00');
        assert.equal(slot.end_time, '09:30');
      },
    },
    {
      name: '10-minute buffers are inserted between scheduled tasks',
      setup: (seedDb) => {
        insertTaskSeed(seedDb, { id: SCHEDULE_TASK_IDS.bufferA, title: 'Buffer A', due_date: today, priority: 1, estimated_minutes: 30 });
        insertTaskSeed(seedDb, { id: SCHEDULE_TASK_IDS.bufferB, title: 'Buffer B', due_date: today, priority: 2, estimated_minutes: 30 });
      },
      assertPayload: (payload) => {
        assert.equal(payload.slots.length, 2);
        const firstSlot = requireArrayItem(payload.slots, 0, 'expected first buffered schedule slot');
        const secondSlot = requireArrayItem(payload.slots, 1, 'expected second buffered schedule slot');
        assert.equal(firstSlot.start_time, '09:00');
        assert.equal(firstSlot.end_time, '09:30');
        assert.equal(secondSlot.start_time, '09:40');
        assert.equal(secondSlot.end_time, '10:10');
      },
    },
    {
      name: 'working-hours overflow sends remaining tasks to unscheduled',
      setup: (seedDb) => {
        upsertPreference(seedDb, 'working_hours', { start: '09:00', end: '10:00' });
        insertTaskSeed(seedDb, { id: SCHEDULE_TASK_IDS.overflowA, title: 'Overflow A', due_date: today, priority: 1, estimated_minutes: 40 });
        insertTaskSeed(seedDb, { id: SCHEDULE_TASK_IDS.overflowB, title: 'Overflow B', due_date: today, priority: 2, estimated_minutes: 30 });
      },
      assertPayload: (payload) => {
        assert.equal(payload.total_minutes_available, 60);
        assert.equal(payload.slots.length, 1);
        assert.equal(payload.unscheduled.length, 1);
        const slot = requireArrayItem(payload.slots, 0, 'expected overflow schedule slot');
        assert.equal(slot.task.id, SCHEDULE_TASK_IDS.overflowA);
        assert.equal(slot.start_time, '09:00');
        assert.equal(slot.end_time, '09:40');
        assert.deepEqual(payload.unscheduled.map((task) => task.id), [SCHEDULE_TASK_IDS.overflowB]);
      },
    },
    {
      name: 'focus schedule only schedules current focus tasks (not filtered by due_date)',
      setup: (seedDb) => {
        insertTaskSeed(seedDb, { id: SCHEDULE_TASK_IDS.overdue, title: 'Overdue', due_date: yesterday, priority: 1, estimated_minutes: 20 });
        insertTaskSeed(seedDb, { id: SCHEDULE_TASK_IDS.undated, title: 'Undated', due_date: null, priority: 2, estimated_minutes: 20 });
        insertTaskSeed(seedDb, { id: SCHEDULE_TASK_IDS.future, title: 'Future', due_date: tomorrow, priority: 1, estimated_minutes: 20 });
      },
      assertPayload: (payload) => {
        // All 3 tasks are in the focus (set by the loop), so all 3 get scheduled
        assert.equal(payload.slots.length, 3);
        assert.equal(payload.unscheduled.length, 0);
      },
    },
  ];

  for (const scenario of scheduleCases) {
    resetBehaviorTables(db);
    scenario.setup(db);

    // Collect seeded task IDs for current_focus (propose_daily_schedule requires it)
    const seededTaskIds = db.prepare(
      "SELECT id FROM tasks WHERE status = 'open' ORDER BY COALESCE(priority, 3) ASC, due_date ASC NULLS LAST"
    ).all() as { id: string }[];
    if (seededTaskIds.length > 0) {
      await harness.client.callTool({
        name: 'set_current_focus',
        arguments: {
          task_ids: seededTaskIds.map(r => r.id),
          briefing: 'test focus',
          date: today,
        },
      });
    }

    const response = await harness.client.callTool({
      name: 'propose_daily_schedule',
      arguments: {
        date: today,
      },
    });
    const payload = parseJsonContent<FocusSchedulePayload>(response);
    assert.equal(payload.date, today, `[${scenario.name}] date should match request`);
    scenario.assertPayload(payload);
  }

  assert.equal(scheduleCases.length, 4, 'Expected four deterministic schedule scenarios in this matrix');
});
