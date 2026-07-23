import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import {
  createBrowserTaskListActionHost,
  dispatchTaskListElementEvent,
  type TaskListActionHost,
} from '../../../app/src/lib/tasks/useTaskListActions.runtime';

test('task list action runtime dispatches named events to the task row', () => {
  const events: string[] = [];
  const host: TaskListActionHost = {
    createEvent: (eventName) => ({ type: eventName } as Event),
    findTaskElement: (taskId) => {
      if (taskId !== 'task-1') return null;
      return {
        dispatchEvent: (event) => {
          events.push(event.type);
          return true;
        },
      };
    },
  };

  assert.equal(dispatchTaskListElementEvent({
    eventName: 'lorvex:start-edit-title',
    host,
    taskId: 'task-1',
  }), true);
  assert.deepEqual(events, ['lorvex:start-edit-title']);

  assert.equal(dispatchTaskListElementEvent({
    eventName: 'lorvex:open-context-menu',
    host,
    taskId: 'missing-task',
  }), false);
  assert.deepEqual(events, ['lorvex:start-edit-title']);
});

test('task list action browser host escapes task ids before querying data attributes', () => {
  const selectors: string[] = [];
  const originalDocument = globalThis.document;

  Object.defineProperty(globalThis, 'document', {
    configurable: true,
    value: {
      querySelector: (selector: string) => {
        selectors.push(selector);
        return null;
      },
    },
  });

  try {
    const host = createBrowserTaskListActionHost();
    host.findTaskElement('task"\\id');
  } finally {
    Object.defineProperty(globalThis, 'document', { configurable: true, value: originalDocument });
  }

  assert.deepEqual(selectors, ['[data-task-id="task\\"\\\\id"]']);
});

test('task list actions hook delegates task row event dispatch through the runtime seam', () => {
  const source = fs.readFileSync(
    path.join(process.cwd(), 'app/src/lib/tasks/taskActions/overlays.ts'),
    'utf8',
  );

  assert.match(
    source,
    /import \{[\s\S]*createBrowserTaskListActionHost,[\s\S]*dispatchTaskListElementEvent,[\s\S]*\} from '\.\.\/useTaskListActions\.runtime';/s,
  );
  assert.match(source, /const taskListActionHost = createBrowserTaskListActionHost\(\);/);
  assert.match(
    source,
    /dispatchTaskListElementEvent\(\{[\s\S]*eventName: 'lorvex:start-edit-title',[\s\S]*host: taskListActionHost,[\s\S]*taskId,[\s\S]*\}\);/,
  );
  assert.match(
    source,
    /dispatchTaskListElementEvent\(\{[\s\S]*eventName: 'lorvex:open-context-menu',[\s\S]*host: taskListActionHost,[\s\S]*taskId,[\s\S]*\}\);/,
  );
  assert.doesNotMatch(source, /document\.querySelector/);
});
