import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { readTypeScriptSources, repoRoot } from './shared.mjs';

test('frontend due-date formatting and overdue checks require explicit day context', () => {
  const formatSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/lib/format/formatting.ts'),
    'utf8',
  );
  const dayContextSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/lib/dayContext.ts'),
    'utf8',
  );
  const todayViewSource = readTypeScriptSources(
    'app/src/components/TodayView.tsx',
    'app/src/components/today-view',
  );

  assert.match(
    dayContextSource,
    /export interface DayContext \{[\s\S]*todayYmd: string;[\s\S]*tomorrowYmd: string;[\s\S]*\}/,
    'frontend day-context helper should expose an explicit today/tomorrow contract',
  );
  assert.match(
    dayContextSource,
    /export function useConfiguredDayContext\(/,
    'frontend should expose a shared configured day-context hook',
  );

  assert.match(
    formatSource,
    /interface DueDateFormatOptions \{[\s\S]*dayContext: DayContext;[\s\S]*\}/,
    'formatDueDate options should require explicit day context',
  );
  assert.match(
    formatSource,
    /export function isDueOverdue\(dueDate: string \| null, dayContext: DayContext\): boolean/,
    'isDueOverdue should require explicit day context',
  );
  assert.doesNotMatch(
    formatSource,
    /function localDateIso\(|const now = new Date\(\);[\s\S]*const today = localDateIso\(now\)/,
    'ipc due-date helpers should not derive today from implicit browser-local time',
  );

  assert.match(
    todayViewSource,
    /useConfiguredDayContext\(/,
    'TodayView should consume the shared configured day-context hook',
  );
  assert.match(
    todayViewSource,
    /isTaskOverdue\(task,\s*dayContext\)|isDueOverdue\(task\.due_date,\s*dayContext\)|queryFn:\s*\(\{\s*signal\s*\}\)\s*=>\s*getOverdueTasks\(signal\)/,
    'TodayView should either use explicit day-context overdue checks locally or delegate overdue bucket loading to the dedicated backend query',
  );
});
