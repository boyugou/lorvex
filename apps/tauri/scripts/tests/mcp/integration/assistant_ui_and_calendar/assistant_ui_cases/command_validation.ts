import assert from 'node:assert/strict';
import test from 'node:test';
import Database from 'better-sqlite3';

import {
  asToolResultPayload,
  createHarness,
  getFirstTextContent,
  insertTaskSeed,
  parseJsonContent,
} from '../../shared';

test('control_app_ui validates switch_view inputs and writes pending command payloads', async (t) => {
  const harness = await createHarness('ui-validation');
  t.after(async () => {
    await harness.cleanup();
  });

  const seedDb = new Database(harness.dbPath);
  t.after(() => seedDb.close());
  insertTaskSeed(seedDb, {
    id: 'task-completed',
    title: 'Completed task',
    status: 'completed',
  });
  insertTaskSeed(seedDb, {
    id: 'task-open',
    title: 'Open task',
    status: 'open',
  });

  const focusMissing = asToolResultPayload(await harness.client.callTool({
    name: 'control_app_ui',
    arguments: {
      action: 'focus_task',
      task_id: 'task-does-not-exist',
    },
  }));
  assert.equal(focusMissing.isError, true, 'Expected focus_task to fail when task does not exist');
  assert.match(getFirstTextContent(focusMissing), /not found/i);

  const openMissing = asToolResultPayload(await harness.client.callTool({
    name: 'control_app_ui',
    arguments: {
      action: 'open_task',
      task_id: 'task-does-not-exist',
    },
  }));
  assert.equal(openMissing.isError, true, 'Expected open_task to fail when task does not exist');
  assert.match(getFirstTextContent(openMissing), /not found/i);

  const focusCompleted = asToolResultPayload(await harness.client.callTool({
    name: 'control_app_ui',
    arguments: {
      action: 'focus_task',
      task_id: 'task-completed',
    },
  }));
  assert.equal(focusCompleted.isError, true, 'Expected focus_task to reject non-open tasks');
  assert.match(getFirstTextContent(focusCompleted), /requires task .* to be open/i);

  const enterFocusCompleted = asToolResultPayload(await harness.client.callTool({
    name: 'control_app_ui',
    arguments: {
      action: 'enter_focus_mode',
      task_id: 'task-completed',
    },
  }));
  assert.equal(enterFocusCompleted.isError, true, 'Expected enter_focus_mode to reject non-open target tasks');
  assert.match(getFirstTextContent(enterFocusCompleted), /requires task .* to be open/i);

  const enterFocusOpen = asToolResultPayload(await harness.client.callTool({
    name: 'control_app_ui',
    arguments: {
      action: 'enter_focus_mode',
      task_id: 'task-open',
    },
  }));
  assert.notStrictEqual(enterFocusOpen.isError, true, 'Expected enter_focus_mode to accept open target tasks');

  const enterFocusOpenPayload = parseJsonContent<{
    action: string;
    command: { value: { action: string; task_id?: string } };
  }>(enterFocusOpen);
  assert.equal(enterFocusOpenPayload.action, 'enter_focus_mode');
  assert.equal(enterFocusOpenPayload.command.value.action, 'enter_focus_mode');
  assert.equal(enterFocusOpenPayload.command.value.task_id, 'task-open');

  const openCompleted = asToolResultPayload(await harness.client.callTool({
    name: 'control_app_ui',
    arguments: {
      action: 'open_task',
      task_id: 'task-completed',
    },
  }));
  assert.notStrictEqual(openCompleted.isError, true, 'Expected open_task to accept existing completed tasks');

  const openCompletedPayload = parseJsonContent<{
    action: string;
    command: { value: { action: string; task_id?: string } };
  }>(openCompleted);
  assert.equal(openCompletedPayload.action, 'open_task');
  assert.equal(openCompletedPayload.command.value.action, 'open_task');
  assert.equal(openCompletedPayload.command.value.task_id, 'task-completed');

  const missingList = asToolResultPayload(await harness.client.callTool({
    name: 'control_app_ui',
    arguments: {
      action: 'switch_view',
      view: 'list',
      list_id: 'list-does-not-exist',
    },
  }));
  assert.equal(missingList.isError, true, 'Expected list view switch to fail when list does not exist');
  assert.match(getFirstTextContent(missingList), /list/i);
  assert.match(getFirstTextContent(missingList), /not found/i);

  // The closed `AssistantUiView` Rust enum on `ControlAppUiArgs.view`
  // rejects unknown variants at the serde-deserialize layer (#3318 H3);
  // the runtime "view must be one of …" diagnostic is now unreachable
  // for unknown wire values.
  await assert.rejects(
    harness.client.callTool({
      name: 'control_app_ui',
      arguments: {
        action: 'switch_view',
        view: 'definitely-not-a-view',
      },
    }),
    (err: any) => err.code === -32602 || /definitely-not-a-view|unknown variant|invalid|view/i.test(String(err.message)),
    'Expected switch_view to reject invalid views at the protocol boundary',
  );

  const changelogSwitch = asToolResultPayload(await harness.client.callTool({
    name: 'control_app_ui',
    arguments: {
      action: 'switch_view',
      view: 'ai_changelog',
    },
  }));
  assert.notStrictEqual(changelogSwitch.isError, true, 'Expected changelog view switch to succeed');

  const commandResult = parseJsonContent<{
    action: string;
    command_id: string;
    command: { key: string; value: { action: string; view?: string } };
  }>(changelogSwitch);
  assert.equal(commandResult.action, 'switch_view');
  assert.equal(commandResult.command.key, 'assistant_ui_command');
  assert.equal(commandResult.command.value.action, 'switch_view');
  assert.equal(commandResult.command.value.view, 'ai_changelog');

  const db = new Database(harness.dbPath, { readonly: true, fileMustExist: true });
  t.after(() => db.close());

  const commandPreference = db
    .prepare('SELECT value FROM device_state WHERE key = ?')
    .get('assistant_ui_command') as { value: string } | undefined;
  assert.ok(commandPreference, 'Expected assistant_ui_command device state to be written');
  const commandPayload = JSON.parse(commandPreference.value) as { action?: string; view?: string };
  assert.equal(commandPayload.action, 'switch_view');
  assert.equal(commandPayload.view, 'ai_changelog');
});
