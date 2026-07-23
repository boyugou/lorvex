import assert from 'node:assert/strict';
import test from 'node:test';
import Database from 'better-sqlite3';

import {
  asToolResultPayload,
  createHarness,
  parseJsonContent,
} from '../../shared';

test('control_app_ui exposes pending command replacement metadata and supports replacement guard', async (t) => {
  const harness = await createHarness('ui-pending');
  t.after(async () => {
    await harness.cleanup();
  });

  const firstCommand = parseJsonContent<{
    command_id: string;
    command: { key: string; value: { command_id: string } };
    replaced_pending_command: null;
  }>(asToolResultPayload(await harness.client.callTool({
    name: 'control_app_ui',
    arguments: {
      action: 'switch_view',
      view: 'today',
    },
  })));
  assert.equal(firstCommand.command.key, 'assistant_ui_command');
  assert.equal(firstCommand.command.value.command_id, firstCommand.command_id);
  assert.equal(firstCommand.replaced_pending_command, null);

  const replacedCommand = parseJsonContent<{
    command_id: string;
    command: { key: string; value: { command_id: string } };
    replaced_pending_command: { command_id: string; action: string };
  }>(asToolResultPayload(await harness.client.callTool({
    name: 'control_app_ui',
    arguments: {
      action: 'switch_view',
      view: 'ai_changelog',
    },
  })));
  assert.equal(replacedCommand.command.key, 'assistant_ui_command');
  assert.equal(replacedCommand.command.value.command_id, replacedCommand.command_id);
  assert.notEqual(replacedCommand.command_id, firstCommand.command_id);
  assert.ok(replacedCommand.replaced_pending_command, 'Expected replaced pending command metadata');
  assert.equal(replacedCommand.replaced_pending_command.command_id, firstCommand.command_id);
  assert.equal(replacedCommand.replaced_pending_command.action, 'switch_view');

  const guardHarness = await createHarness('ui-pending-guard');
  t.after(async () => {
    await guardHarness.cleanup();
  });

  const guardFirst = parseJsonContent<{ command_id: string }>(asToolResultPayload(await guardHarness.client.callTool({
    name: 'control_app_ui',
    arguments: {
      action: 'switch_view',
      view: 'today',
    },
  })));

  const guardBlocked = asToolResultPayload(await guardHarness.client.callTool({
    name: 'control_app_ui',
    arguments: {
      action: 'switch_view',
      view: 'today',
      allow_replace_pending: false,
    },
  }));
  assert.equal(guardBlocked.isError, true, 'Expected pending guard to reject replacement');

  // Validation failures are wrapped as a structured MCP error envelope, but
  // the SDK may truncate the long embedded `message` string for transport.
  const outerErrorPayload = parseJsonContent<{
    kind?: string;
  }>(guardBlocked);
  assert.equal(outerErrorPayload.kind, 'validation');

  const guardDb = new Database(guardHarness.dbPath, { readonly: true, fileMustExist: true });
  t.after(() => guardDb.close());
  const persistedGuardCommand = guardDb
    .prepare('SELECT value FROM device_state WHERE key = ?')
    .get('assistant_ui_command') as { value: string } | undefined;
  assert.ok(persistedGuardCommand, 'Expected original pending command to still be present');
  const persistedPayload = JSON.parse(persistedGuardCommand.value) as { command_id?: string; view?: string };
  assert.equal(persistedPayload.command_id, guardFirst.command_id);
  assert.equal(persistedPayload.view, 'today');
});
