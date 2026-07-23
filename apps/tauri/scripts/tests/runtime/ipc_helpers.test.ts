import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

import { createCalendarEvent, updateCalendarEvent } from '../../../app/src/lib/ipc/calendar';
import { buildPayload } from '../../../app/src/lib/ipc/buildPayload';

test('buildPayload preserves null and defined values while omitting undefined fields', () => {
  assert.deepEqual(
    buildPayload({
      title: 'Planning',
      notes: null,
      start_time: undefined,
      all_day: false,
      estimate_minutes: 0,
    }),
    {
      title: 'Planning',
      notes: null,
      all_day: false,
      estimate_minutes: 0,
    },
  );
});

test('buildPayload copies own data fields without invoking accessors', () => {
  const fields = {
    stable: 'value',
  } as Record<string, unknown>;

  Object.defineProperty(fields, 'danger', {
    enumerable: true,
    get() {
      throw new Error('getter should not be invoked');
    },
  });
  Object.defineProperty(fields, 'hidden', {
    enumerable: false,
    value: 'copied',
  });

  assert.deepEqual(buildPayload(fields), {
    stable: 'value',
  });
});

test('buildPayload safely merges multiple field sources in order', () => {
  const updates = {
    title: 'Updated',
    location: null,
    start_time: undefined,
  } as Record<string, unknown>;

  Object.defineProperty(updates, 'danger', {
    enumerable: true,
    get() {
      throw new Error('getter should not be invoked');
    },
  });

  assert.deepEqual(buildPayload({ id: 'event-1', title: 'Initial' }, updates), {
    id: 'event-1',
    title: 'Updated',
    location: null,
  });
});

test('calendar update wrapper keeps update merging inside buildPayload', () => {
  const source = readFileSync('app/src/lib/ipc/calendar.ts', 'utf8');

  assert.doesNotMatch(source, /buildPayload\(\{ id,\s*\.\.\.updates \}\)/);
});

test('calendar update wrapper does not invoke update accessors while building payload', async () => {
  let getterInvoked = false;
  const updates = {
    title: 'Updated',
    location: null,
  } as Parameters<typeof updateCalendarEvent>[1];

  Object.defineProperty(updates, 'description', {
    enumerable: true,
    get() {
      getterInvoked = true;
      throw new Error('getter should not be invoked');
    },
  });

  try {
    await updateCalendarEvent('event-1', updates);
  } catch {
    assert.equal(getterInvoked, false);
    return;
  }

  assert.fail('expected the Tauri IPC call to reject outside a Tauri runtime');
});

test('calendar create wrapper does not invoke optional input accessors while building payload', async () => {
  let getterInvoked = false;
  const params = {
    title: 'Planning',
    start_date: '2026-01-01',
  } as Parameters<typeof createCalendarEvent>[0];

  Object.defineProperty(params, 'description', {
    enumerable: true,
    get() {
      getterInvoked = true;
      throw new Error('getter should not be invoked');
    },
  });

  try {
    await createCalendarEvent(params);
  } catch {
    assert.equal(getterInvoked, false);
    return;
  }

  assert.fail('expected the Tauri IPC call to reject outside a Tauri runtime');
});
