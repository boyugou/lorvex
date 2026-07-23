import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

function readQuotedValuesFromSharedArray(source, constName) {
  const pattern = new RegExp(`export const ${constName} = \\[([\\s\\S]*?)\\] as const;`);
  const match = source.match(pattern);
  assert.ok(match, `Expected ${constName} array in shared source`);
  return Array.from(match[1].matchAll(/'([^']+)'/g), (item) => item[1]);
}

function readExecuteAssistantUiCommandSwitch(source) {
  const callbackMatch = source.match(/const executeAssistantUiCommand = useCallback\(async \(command: AssistantUiCommand\) => \{([\s\S]*?)\n\s*\}, \[/);
  assert.ok(callbackMatch, 'Expected executeAssistantUiCommand callback in useAssistantUiRuntime.ts');
  assert.match(callbackMatch[1], /switch \(command\.action\) \{/, 'Expected executeAssistantUiCommand switch in useAssistantUiRuntime.ts');

  return {
    callbackBody: callbackMatch[1],
    switchBody: callbackMatch[1],
  };
}

test('assistant UI action handler covers every shared assistant UI action', () => {
  const sharedTypes = fs.readFileSync(path.join(repoRoot, 'shared/src/types.ts'), 'utf8');
  const runtimeSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/app-shell/main-window/runtime/useAssistantUiRuntime.ts'),
    'utf8',
  );

  const sharedActions = readQuotedValuesFromSharedArray(sharedTypes, 'ASSISTANT_UI_ACTIONS').sort();
  const { switchBody: actionSwitch } = readExecuteAssistantUiCommandSwitch(runtimeSource);
  const handledActions = Array.from(
    actionSwitch.matchAll(/case '([^']+)': \{/g),
    (item) => item[1],
  ).sort();

  assert.deepEqual(
    handledActions,
    sharedActions,
    'executeAssistantUiCommand should explicitly handle every shared assistant UI action',
  );
});

test('assistant UI action handler keeps action-specific payload guards explicit', () => {
  const runtimeSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/app-shell/main-window/runtime/useAssistantUiRuntime.ts'),
    'utf8',
  );
  const { callbackBody, switchBody: actionSwitch } = readExecuteAssistantUiCommandSwitch(runtimeSource);

  const requiredGuardPatterns = [
    /case 'focus_task': \{\s*if \(typeof command\.task_id !== 'string'\) return;/,
    /case 'open_task': \{\s*if \(typeof command\.task_id !== 'string'\) return;/,
    /case 'switch_view': \{\s*const next = assistantCommandViewToAppView\(command\.view, command\.list_id\);\s*if \(!next\) return;/,
    /case 'set_theme': \{\s*if \(!command\.theme\) return;/,
    /case 'set_appearance_profile': \{\s*if \(!command\.appearance_profile\) return;/,
    /case 'set_language': \{\s*if \(!command\.language\) return;/,
  ];

  for (const pattern of requiredGuardPatterns) {
    assert.match(
      actionSwitch,
      pattern,
      `executeAssistantUiCommand should keep required payload guard ${pattern} explicit`,
    );
  }

  assert.match(
    actionSwitch,
    /default:\s*return assertNever\(command\.action,\s*'assistant UI action'\);/,
    'executeAssistantUiCommand should keep an explicit default-branch exhaustiveness guard for future assistant UI actions',
  );
});
