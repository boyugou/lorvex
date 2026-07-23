import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import {
  DEFAULT_DASHBOARD_LAYOUT,
  parseDashboardLayoutPreference,
} from '../../../app/src/lib/ipc/dashboard.logic';

test('dashboard layout parser accepts canonical section payloads', () => {
  assert.deepEqual(
    parseDashboardLayoutPreference(JSON.stringify({
      sections: [
        { type: 'focus' },
        { type: 'overdue_alert', limit: 3 },
      ],
      updated_by: 'assistant',
    })),
    {
      sections: [
        { type: 'focus' },
        { type: 'overdue_alert', limit: 3 },
      ],
      updated_by: 'assistant',
    },
  );
});

test('dashboard layout parser rejects partially malformed sections', () => {
  assert.deepEqual(
    parseDashboardLayoutPreference(JSON.stringify({
      sections: [
        { type: 'focus' },
        { type: 'unknown_section' },
      ],
    })),
    DEFAULT_DASHBOARD_LAYOUT,
  );
  assert.deepEqual(
    parseDashboardLayoutPreference(JSON.stringify({
      sections: [
        { type: 'focus' },
        { type: 'overdue_alert', limit: 0 },
      ],
    })),
    DEFAULT_DASHBOARD_LAYOUT,
  );
  assert.deepEqual(
    parseDashboardLayoutPreference(JSON.stringify({
      sections: [
        { type: 'focus', stale: true },
      ],
    })),
    DEFAULT_DASHBOARD_LAYOUT,
  );
  assert.deepEqual(
    parseDashboardLayoutPreference(JSON.stringify({
      sections: [
        { type: 'focus' },
      ],
      unexpected: true,
    })),
    DEFAULT_DASHBOARD_LAYOUT,
  );
});

test('dashboard layout parser returns defaults for missing or malformed payloads', () => {
  assert.deepEqual(parseDashboardLayoutPreference(null), DEFAULT_DASHBOARD_LAYOUT);
  assert.deepEqual(parseDashboardLayoutPreference('not json'), DEFAULT_DASHBOARD_LAYOUT);
  assert.deepEqual(parseDashboardLayoutPreference(JSON.stringify({ sections: [] })), DEFAULT_DASHBOARD_LAYOUT);
  assert.deepEqual(parseDashboardLayoutPreference(JSON.stringify({ sections: 'focus' })), DEFAULT_DASHBOARD_LAYOUT);
});

test('dashboard layout parser delegates JSON parsing to the shared helper', () => {
  const source = fs.readFileSync(
    path.join(process.cwd(), 'app/src/lib/ipc/dashboard.logic.ts'),
    'utf8',
  );

  assert.match(source, /from '\.\.\/security\/jsonParse';/);
  assert.match(source, /const parsed = parseResult\.value;/);
  assert.doesNotMatch(source, /JSON\.parse\(/);
  assert.doesNotMatch(source, /parseResult\.value as/);
});
