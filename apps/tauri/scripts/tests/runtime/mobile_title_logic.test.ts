import assert from 'node:assert/strict';
import test from 'node:test';

import { MOBILE_TITLE_KEYS, resolveMobileTitleKey } from '../../../app/src/app-shell/main-window/useMobileTitle.logic';

test('mobile title keys include recurring and stay exhaustive for non-list views', () => {
  assert.equal(resolveMobileTitleKey('recurring'), 'nav.recurring');
  assert.equal(MOBILE_TITLE_KEYS.today, 'nav.today');
  assert.equal(MOBILE_TITLE_KEYS.all_tasks, 'nav.allTasks');
});
