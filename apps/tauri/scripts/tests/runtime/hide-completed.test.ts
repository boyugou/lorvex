import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

import {
  clampHideCompletedOlderThanDays,
  DEFAULT_HIDE_COMPLETED_OLDER_THAN_DAYS,
  hideCompletedCutoffMs,
  MAX_HIDE_COMPLETED_OLDER_THAN_DAYS,
  MIN_HIDE_COMPLETED_OLDER_THAN_DAYS,
  parseHideCompletedOlderThanDays,
  partitionCompletedTasks,
} from '../../../app/src/lib/hideCompletedOlderThan';

// Issue #2515 — pin the date-math that separates "visible" vs "hidden"
// completed tasks in list views so a refactor to the cutoff or the
// preference parser cannot silently shift the boundary.

const DAY_MS = 86_400_000;
const NOW = Date.parse('2026-04-18T12:00:00.000Z');

test('default is 30 days when preference is missing or unparseable', () => {
  assert.equal(parseHideCompletedOlderThanDays(null), DEFAULT_HIDE_COMPLETED_OLDER_THAN_DAYS);
  assert.equal(parseHideCompletedOlderThanDays(''), DEFAULT_HIDE_COMPLETED_OLDER_THAN_DAYS);
  assert.equal(parseHideCompletedOlderThanDays('not-json'), DEFAULT_HIDE_COMPLETED_OLDER_THAN_DAYS);
  assert.equal(parseHideCompletedOlderThanDays('"oops"'), DEFAULT_HIDE_COMPLETED_OLDER_THAN_DAYS);
  assert.equal(parseHideCompletedOlderThanDays('7.9'), DEFAULT_HIDE_COMPLETED_OLDER_THAN_DAYS);
  assert.equal(parseHideCompletedOlderThanDays('1e2'), DEFAULT_HIDE_COMPLETED_OLDER_THAN_DAYS);
  assert.equal(DEFAULT_HIDE_COMPLETED_OLDER_THAN_DAYS, 30);
});

test('parseHideCompletedOlderThanDays accepts canonical decimal integer payloads', () => {
  assert.equal(parseHideCompletedOlderThanDays('7'), 7);
  assert.equal(parseHideCompletedOlderThanDays('0'), 0);
  assert.equal(parseHideCompletedOlderThanDays('365'), 365);
  assert.equal(parseHideCompletedOlderThanDays('60'), 60);
});

test('parseHideCompletedOlderThanDays avoids broad JSON number parsing', () => {
  const source = readFileSync('app/src/lib/hideCompletedOlderThan.ts', 'utf8');
  assert.doesNotMatch(source, /JSON\.parse\(trimmed\)/);
});

test('completed tasks section subscribes to hide-completed preference updates', () => {
  const source = readFileSync('app/src/components/list-view/CompletedTasksSection.tsx', 'utf8');

  assert.match(source, /usePreference\(/);
  assert.doesNotMatch(source, /getPreference\(/);
  assert.doesNotMatch(source, /Load the preference once per mount/);
});

test('clampHideCompletedOlderThanDays enforces [0, 3650] and truncates fractions', () => {
  assert.equal(clampHideCompletedOlderThanDays(-5), MIN_HIDE_COMPLETED_OLDER_THAN_DAYS);
  assert.equal(clampHideCompletedOlderThanDays(10_000), MAX_HIDE_COMPLETED_OLDER_THAN_DAYS);
  assert.equal(clampHideCompletedOlderThanDays(7.9), 7);
  assert.equal(clampHideCompletedOlderThanDays(Number.NaN), DEFAULT_HIDE_COMPLETED_OLDER_THAN_DAYS);
});

test('hideCompletedCutoffMs returns null when days is 0 (meaning never hide)', () => {
  assert.equal(hideCompletedCutoffMs(NOW, 0), null);
});

test('hideCompletedCutoffMs subtracts N days of milliseconds from now', () => {
  assert.equal(hideCompletedCutoffMs(NOW, 30), NOW - 30 * DAY_MS);
  assert.equal(hideCompletedCutoffMs(NOW, 1), NOW - DAY_MS);
});

test('partitionCompletedTasks hides only tasks completed strictly before the cutoff', () => {
  const tasks = [
    { id: 'fresh', completed_at: new Date(NOW - 5 * DAY_MS).toISOString() },
    { id: 'edge', completed_at: new Date(NOW - 30 * DAY_MS).toISOString() },
    { id: 'old', completed_at: new Date(NOW - 45 * DAY_MS).toISOString() },
    { id: 'ancient', completed_at: new Date(NOW - 400 * DAY_MS).toISOString() },
  ];
  const { visible, hidden } = partitionCompletedTasks(tasks, NOW, 30);
  // The edge case (exactly 30 days old) is inclusive — we keep it
  // visible so users don't see a task disappear the moment the clock
  // ticks past the cutoff by a millisecond.
  assert.deepEqual(visible.map((t) => t.id), ['fresh', 'edge']);
  assert.deepEqual(hidden.map((t) => t.id), ['old', 'ancient']);
});

test('partitionCompletedTasks keeps everything visible when days is 0', () => {
  const tasks = [
    { id: 'fresh', completed_at: new Date(NOW - 1 * DAY_MS).toISOString() },
    { id: 'ancient', completed_at: new Date(NOW - 10_000 * DAY_MS).toISOString() },
  ];
  const { visible, hidden } = partitionCompletedTasks(tasks, NOW, 0);
  assert.equal(visible.length, 2);
  assert.equal(hidden.length, 0);
});

test('partitionCompletedTasks never hides rows with null or malformed completed_at', () => {
  const tasks = [
    { id: 'null-date', completed_at: null },
    { id: 'bad-date', completed_at: 'not-a-date' },
    { id: 'ancient', completed_at: new Date(NOW - 400 * DAY_MS).toISOString() },
  ];
  const { visible, hidden } = partitionCompletedTasks(tasks, NOW, 30);
  assert.deepEqual(visible.map((t) => t.id), ['null-date', 'bad-date']);
  assert.deepEqual(hidden.map((t) => t.id), ['ancient']);
});

test('partitionCompletedTasks returns a fresh array — callers can mutate safely', () => {
  const tasks = [{ id: 'a', completed_at: new Date(NOW).toISOString() }];
  const { visible } = partitionCompletedTasks(tasks, NOW, 30);
  assert.notEqual(visible, tasks);
});
