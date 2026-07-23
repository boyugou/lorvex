import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import {
  DEFAULT_SIDEBAR_MODULE_CONFIG,
  cloneSidebarModuleConfig,
  parseSidebarModuleConfig,
  parseSidebarVisibleModulesPreference,
  sidebarModuleConfigPreferenceValue,
} from '../../../app/src/lib/sidebarModules';

test('parseSidebarVisibleModulesPreference falls back to defaults when preference is missing or malformed', () => {
  const expected = [...DEFAULT_SIDEBAR_MODULE_CONFIG.show, ...DEFAULT_SIDEBAR_MODULE_CONFIG.more];
  assert.deepEqual(parseSidebarVisibleModulesPreference(null), expected);
  assert.deepEqual(parseSidebarVisibleModulesPreference('not json'), expected);
  assert.deepEqual(parseSidebarVisibleModulesPreference('[]'), expected);
});

test('parseSidebarModuleConfig returns defaults for null/undefined/empty', () => {
  assert.deepEqual(parseSidebarModuleConfig(null), DEFAULT_SIDEBAR_MODULE_CONFIG);
  assert.deepEqual(parseSidebarModuleConfig(undefined), DEFAULT_SIDEBAR_MODULE_CONFIG);
  assert.deepEqual(parseSidebarModuleConfig(''), DEFAULT_SIDEBAR_MODULE_CONFIG);
});

test('parseSidebarModuleConfig parses object format correctly', () => {
  const input = JSON.stringify({
    show: ['today', 'calendar'],
    more: ['eisenhower', 'kanban'],
  });
  const result = parseSidebarModuleConfig(input);
  assert.deepEqual(result.show, ['today', 'calendar']);
  assert.deepEqual(result.more, ['eisenhower', 'kanban']);
});

test('parseSidebarModuleConfig rejects partially malformed module arrays', () => {
  assert.deepEqual(
    parseSidebarModuleConfig(JSON.stringify({
      show: ['today', 'unknown_module'],
      more: ['eisenhower'],
    })),
    DEFAULT_SIDEBAR_MODULE_CONFIG,
  );
  assert.deepEqual(
    parseSidebarModuleConfig(JSON.stringify({
      show: ['today'],
      more: ['eisenhower', 42],
    })),
    DEFAULT_SIDEBAR_MODULE_CONFIG,
  );
  assert.deepEqual(
    parseSidebarModuleConfig(JSON.stringify({
      show: ['today'],
      more: ['eisenhower'],
      experimental: true,
    })),
    DEFAULT_SIDEBAR_MODULE_CONFIG,
  );
});

test('parseSidebarModuleConfig returns defaults for flat array (unsupported format)', () => {
  const input = JSON.stringify(['today', 'calendar', 'review']);
  const result = parseSidebarModuleConfig(input);
  assert.deepEqual(result, DEFAULT_SIDEBAR_MODULE_CONFIG);
});

test('parseSidebarModuleConfig deduplicates modules between show and more', () => {
  const input = JSON.stringify({
    show: ['today', 'calendar'],
    more: ['calendar', 'eisenhower'],
  });
  const result = parseSidebarModuleConfig(input);
  assert.ok(!result.more.includes('calendar'), 'calendar should not appear in more when already in show');
  assert.ok(result.show.includes('calendar'));
  assert.ok(result.more.includes('eisenhower'));
});

test('parseSidebarModuleConfig injects primary module when missing from show', () => {
  const input = JSON.stringify({
    show: ['calendar'],
    more: ['eisenhower'],
  });
  const result = parseSidebarModuleConfig(input);
  assert.ok(result.show.includes('today'), 'should inject "today" when no primary present');
  assert.ok(result.show.includes('calendar'));
});

test('sidebar defaults and parsed configs return fresh arrays rather than shared default references', () => {
  const defaults = cloneSidebarModuleConfig(DEFAULT_SIDEBAR_MODULE_CONFIG);
  defaults.show.push('habits');
  assert.deepEqual(DEFAULT_SIDEBAR_MODULE_CONFIG.show, ['today', 'upcoming', 'all_tasks', 'someday', 'calendar', 'eisenhower', 'focus']);

  const parsed = parseSidebarModuleConfig(null);
  parsed.more.push('today');
  assert.ok(!DEFAULT_SIDEBAR_MODULE_CONFIG.more.includes('today'));
});

test('sidebarModuleConfigPreferenceValue returns the structured IPC payload without JSON round-tripping', () => {
  const config = {
    show: ['today', 'calendar'],
    more: ['kanban'],
  } as const;

  const payload = sidebarModuleConfigPreferenceValue(config);

  assert.deepEqual(payload, {
    show: ['today', 'calendar'],
    more: ['kanban'],
  });
  assert.notEqual(payload.show, config.show);
  assert.notEqual(payload.more, config.more);
});

test('sidebar module config parser delegates JSON parsing to the shared helper', () => {
  const source = fs.readFileSync(
    path.join(process.cwd(), 'app/src/lib/sidebarModules.ts'),
    'utf8',
  );

  assert.match(source, /from '\.\/security\/jsonParse';/);
  assert.doesNotMatch(source, /JSON\.parse\(/);
});
