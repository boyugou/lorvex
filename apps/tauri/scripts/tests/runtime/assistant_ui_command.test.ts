import assert from 'node:assert/strict';
import test from 'node:test';

import {
  assistantCommandViewToAppView,
  normalizeAssistantUiCommand,
} from '../../../app/src/lib/assistantUiCommand';

test('normalizeAssistantUiCommand rejects missing ids and invalid actions', () => {
  assert.equal(normalizeAssistantUiCommand(null), null);
  assert.equal(normalizeAssistantUiCommand({ command_id: 'cmd-1' }), null);
  assert.equal(
    normalizeAssistantUiCommand({ command_id: 'cmd-1', action: 'launch_missiles' }),
    null,
  );
});

test('normalizeAssistantUiCommand keeps canonical optional fields', () => {
  const command = normalizeAssistantUiCommand({
    command_id: 'cmd-1',
    action: 'switch_view',
    view: 'calendar',
    theme: 'system',
    appearance_profile: 'clarity',
    language: 'zh',
    requested_at: '2026-04-22T10:00:00Z',
    requested_by: 'agent',
    task_id: 'task-1',
    list_id: 'list-1',
    note: 'Open calendar for review',
  });

  assert.deepEqual(command, {
    command_id: 'cmd-1',
    action: 'switch_view',
    view: 'calendar',
    theme: 'system',
    appearance_profile: 'clarity',
    language: 'zh',
    requested_at: '2026-04-22T10:00:00Z',
    task_id: 'task-1',
    list_id: 'list-1',
  });
});

test('normalizeAssistantUiCommand accepts MCP null optional fields as absent metadata', () => {
  const command = normalizeAssistantUiCommand({
    command_id: 'cmd-1',
    action: 'exit_focus_mode',
    requested_at: '2026-04-22T10:00:00Z',
    requested_by: 'agent',
    task_id: null,
    view: null,
    list_id: null,
    theme: null,
    appearance_profile: null,
    language: null,
    note: null,
  });

  assert.deepEqual(command, {
    command_id: 'cmd-1',
    action: 'exit_focus_mode',
    requested_at: '2026-04-22T10:00:00Z',
    task_id: undefined,
    view: undefined,
    list_id: undefined,
    theme: undefined,
    appearance_profile: undefined,
    language: undefined,
  });
});

test('normalizeAssistantUiCommand preserves the explicit system language branch', () => {
  const command = normalizeAssistantUiCommand({
    command_id: 'cmd-system-language',
    action: 'switch_view',
    view: 'today',
    language: 'system',
  });

  assert.deepEqual(command, {
    command_id: 'cmd-system-language',
    action: 'switch_view',
    requested_at: undefined,
    task_id: undefined,
    view: 'today',
    list_id: undefined,
    theme: undefined,
    appearance_profile: undefined,
    language: 'system',
  });
});

test('normalizeAssistantUiCommand rejects malformed optional fields', () => {
  assert.equal(normalizeAssistantUiCommand({
    command_id: 'cmd-2',
    action: 'switch_view',
    view: 'totally_invalid',
    theme: 'neon',
    appearance_profile: 'retro_future',
    language: 'zz',
    list_id: 42,
  }), null);
});

test('normalizeAssistantUiCommand rejects non-canonical command envelopes', () => {
  assert.equal(normalizeAssistantUiCommand({
    command_id: ' cmd-1 ',
    action: 'exit_focus_mode',
  }), null);
  assert.equal(normalizeAssistantUiCommand({
    command_id: 'cmd-2',
    action: 'exit_focus_mode',
    debug: true,
  }), null);
});

test('normalizeAssistantUiCommand rejects action payloads that would no-op at execution time', () => {
  assert.equal(normalizeAssistantUiCommand({ command_id: 'cmd-open', action: 'open_task' }), null);
  assert.equal(normalizeAssistantUiCommand({ command_id: 'cmd-focus', action: 'focus_task', task_id: '' }), null);
  assert.equal(normalizeAssistantUiCommand({ command_id: 'cmd-switch', action: 'switch_view' }), null);
  assert.equal(normalizeAssistantUiCommand({
    command_id: 'cmd-list',
    action: 'switch_view',
    view: 'list',
  }), null);
  assert.equal(normalizeAssistantUiCommand({ command_id: 'cmd-theme', action: 'set_theme' }), null);
  assert.equal(normalizeAssistantUiCommand({ command_id: 'cmd-profile', action: 'set_appearance_profile' }), null);
  assert.equal(normalizeAssistantUiCommand({ command_id: 'cmd-language', action: 'set_language' }), null);
});

test('assistantCommandViewToAppView maps canonical views and rejects list without list_id', () => {
  assert.deepEqual(assistantCommandViewToAppView('today'), { type: 'today' });
  assert.deepEqual(assistantCommandViewToAppView('list', 'list-123'), { type: 'list', listId: 'list-123' });
  assert.equal(assistantCommandViewToAppView('list'), null);
});
