import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';

import { formatCalendarDate } from '../../../app/src/lib/dates/dateLocale';
import { runGuardedReminderSubmit } from '../../../app/src/components/task-detail/metadata-editor/editable-grid/RemindersField';

test('TaskUnifiedMetaCard planned-date display uses the shared locale-aware formatter', () => {
  const source = fs.readFileSync('app/src/components/task-detail/metadata-editor/TaskUnifiedMetaCard.tsx', 'utf8');
  assert.match(source, /import \{ formatCalendarDate \} from '@\/lib\/dates\/dateLocale';/);
  assert.match(source, /formatCalendarDate\(task\.planned_date, locale\)/);
  assert.equal(formatCalendarDate('2026-04-23', 'en-US'), 'Apr 23');
  assert.equal(formatCalendarDate('2026-04-23', 'zh-CN'), '4月23日');
});

test('TaskUnifiedMetaCard fails closed for missing planned dates', () => {
  const source = fs.readFileSync('app/src/components/task-detail/metadata-editor/TaskUnifiedMetaCard.tsx', 'utf8');
  assert.match(source, /const plannedStr = task\.planned_date[\s\S]*\? formatCalendarDate\(task\.planned_date, locale\)[\s\S]*: null;/);
});

test('runGuardedReminderSubmit rejects empty values and suppresses concurrent duplicate submits', async () => {
  const inFlightRef = { current: false };
  let calls = 0;
  const submit = async (value: string) => {
    calls += 1;
    await new Promise((resolve) => setTimeout(resolve, 0));
    return value === '2026-04-23T12:00';
  };

  assert.equal(await runGuardedReminderSubmit(inFlightRef, '', submit), false);

  const first = runGuardedReminderSubmit(inFlightRef, '2026-04-23T12:00', submit);
  const second = runGuardedReminderSubmit(inFlightRef, '2026-04-23T12:00', submit);

  assert.equal(await second, false);
  assert.equal(await first, true);
  assert.equal(calls, 1);
  assert.equal(inFlightRef.current, false);
});
