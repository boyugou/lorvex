import assert from 'node:assert/strict';
import test from 'node:test';
import Database from 'better-sqlite3';

import {
  asToolResultPayload,
  createHarness,
  getFirstTextContent,
  parseJsonContent,
} from '../../shared';

test('control_app_ui validates and persists set_language commands', async (t) => {
  const harness = await createHarness('ui-language');
  t.after(async () => {
    await harness.cleanup();
  });

  const missingLanguage = asToolResultPayload(await harness.client.callTool({
    name: 'control_app_ui',
    arguments: {
      action: 'set_language',
    },
  }));
  assert.equal(missingLanguage.isError, true, 'Expected set_language to require language');
  assert.match(getFirstTextContent(missingLanguage), /language is required/i);

  // The closed `AssistantUiLanguage` Rust enum on `ControlAppUiArgs.language`
  // rejects unknown variants at the serde-deserialize layer (issue #3318
  // H3); the rmcp router surfaces the rejection with a serde-shaped
  // diagnostic that names the unknown variant. Pre-fix the runtime
  // validator returned `"language must be one of …"`; that branch is
  // now unreachable for unknown wire values.
  await assert.rejects(
    harness.client.callTool({
      name: 'control_app_ui',
      arguments: {
        action: 'set_language',
        language: 'pirate',
      },
    }),
    (err: any) => err.code === -32602 || /pirate|unknown variant|invalid|language/i.test(String(err.message)),
    'Expected set_language to reject invalid languages at the protocol boundary',
  );

  const validLanguage = asToolResultPayload(await harness.client.callTool({
    name: 'control_app_ui',
    arguments: {
      action: 'set_language',
      language: 'zh',
    },
  }));
  assert.notStrictEqual(validLanguage.isError, true, 'Expected set_language to accept shared locales');

  const languageResult = parseJsonContent<{
    action: string;
    command_id: string;
    command: { key: string; value: { action: string; language?: string } };
  }>(validLanguage);
  assert.equal(languageResult.action, 'set_language');
  assert.equal(languageResult.command.key, 'assistant_ui_command');
  assert.equal(languageResult.command.value.action, 'set_language');
  assert.equal(languageResult.command.value.language, 'zh');

  const db = new Database(harness.dbPath, { readonly: true, fileMustExist: true });
  t.after(() => db.close());

  const commandPreference = db
    .prepare('SELECT value FROM device_state WHERE key = ?')
    .get('assistant_ui_command') as { value: string } | undefined;
  assert.ok(commandPreference, 'Expected assistant_ui_command device state to be written');
  const commandPayload = JSON.parse(commandPreference.value) as { action?: string; language?: string };
  assert.equal(commandPayload.action, 'set_language');
  assert.equal(commandPayload.language, 'zh');
});
