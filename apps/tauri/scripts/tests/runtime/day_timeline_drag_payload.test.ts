import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import {
  parseDayTimelineDragPayload,
  serializeDayTimelineDragPayload,
} from '../../../app/src/components/calendar/day-panel/DayTimeline.logic';

test('day timeline drag payload parser accepts canonical payloads', () => {
  assert.deepEqual(
    parseDayTimelineDragPayload('{"taskId":"task-1","oldTime":"09:30"}'),
    { taskId: 'task-1', oldTime: '09:30' },
  );
  assert.deepEqual(
    parseDayTimelineDragPayload('{"taskId":"task-1","oldTime":null}'),
    { taskId: 'task-1', oldTime: null },
  );
});

test('day timeline drag payload parser rejects malformed payloads fail-closed', () => {
  assert.equal(parseDayTimelineDragPayload('not json'), null);
  assert.equal(parseDayTimelineDragPayload('[]'), null);
  assert.equal(parseDayTimelineDragPayload('{"taskId":"","oldTime":"09:30"}'), null);
  assert.equal(parseDayTimelineDragPayload('{"taskId":123,"oldTime":"09:30"}'), null);
  assert.equal(parseDayTimelineDragPayload('{"taskId":"task-1","oldTime":930}'), null);
  assert.equal(parseDayTimelineDragPayload('{"taskId":"task-1","oldTime":"9:30"}'), null);
  assert.equal(parseDayTimelineDragPayload('{"taskId":"task-1","oldTime":"09:30","extra":true}'), null);
});

test('day timeline drag payload serializer emits parser-compatible canonical JSON', () => {
  const raw = serializeDayTimelineDragPayload('task-1', null);

  assert.deepEqual(parseDayTimelineDragPayload(raw), {
    taskId: 'task-1',
    oldTime: null,
  });
});

test('day timeline drag payload parser delegates JSON parsing to the shared helper', () => {
  const source = fs.readFileSync(
    path.join(process.cwd(), 'app/src/components/calendar/day-panel/DayTimeline.logic.ts'),
    'utf8',
  );

  assert.match(source, /from ['"](?:@\/lib\/security\/jsonParse|\.\.\/\.\.\/\.\.\/lib\/security\/jsonParse)['"];/);
  assert.doesNotMatch(source, /JSON\.parse\(/);
});
