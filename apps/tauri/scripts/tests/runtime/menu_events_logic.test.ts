import assert from 'node:assert/strict';
import test from 'node:test';

import {
  MENU_VIEW_TYPE_MAP,
  resolveMenuDataView,
  resolveMenuView,
} from '../../../app/src/app-shell/main-window/runtime/useMenuEvents.logic';

test('menu navigation map resolves every supported menu payload and keeps recurring wired', () => {
  assert.deepEqual(resolveMenuView('today'), { type: 'today' });
  assert.deepEqual(resolveMenuView('all'), { type: 'all_tasks' });
  assert.deepEqual(resolveMenuView('recurring'), { type: 'recurring' });
  assert.deepEqual(resolveMenuView('settings'), { type: 'settings' });
  assert.equal(resolveMenuView('missing'), null);
  assert.deepEqual(Object.keys(MENU_VIEW_TYPE_MAP).sort(), [
    'ai_changelog',
    'all',
    'calendar',
    'daily_review',
    'dependencies',
    'eisenhower',
    'habits',
    'kanban',
    'memory',
    'recurring',
    'review',
    'settings',
    'someday',
    'today',
    'upcoming',
  ]);
});

test('menu data actions route directly to the Settings Data section', () => {
  assert.deepEqual(resolveMenuDataView(), {
    type: 'settings',
    sectionId: 'settings-section-data',
  });
});
