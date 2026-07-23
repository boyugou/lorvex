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

function readAppViewTypes(source) {
  const viewTypes = Array.from(source.matchAll(/\|\s*\{\s*type:\s*'([^']+)'/g), (item) => item[1]);
  assert.ok(viewTypes.length > 0, 'Expected View union members in app view types source');
  return viewTypes;
}

function readAssistantViewSwitch(source) {
  const functionMatch = source.match(/export function assistantCommandViewToAppView\([\s\S]*?\): View \| null \{([\s\S]*?)\n\}/);
  assert.ok(functionMatch, 'Expected assistantCommandViewToAppView function in app assistant UI command source');

  const switchMatch = functionMatch[1].match(
    /switch \(view\) \{([\s\S]*?)\n\s*\}\n\s*return assertNever\(view,\s*'assistant UI view'\);/,
  );
  assert.ok(switchMatch, 'Expected assistantCommandViewToAppView switch in app assistant UI command source');

  const directPairs = Array.from(
    switchMatch[1].matchAll(/case '([^']+)': return \{ type: '([^']+)' \};/g),
    (item) => ({ input: item[1], output: item[2] }),
  );
  const hasListCase = /case 'list':\s*return listId \? \{ type: 'list', listId \} : null;/.test(switchMatch[1]);

  return {
    functionBody: functionMatch[1],
    directPairs,
    hasListCase,
  };
}

test('assistant UI shared views stay aligned with the app View union', () => {
  const sharedTypes = fs.readFileSync(path.join(repoRoot, 'shared/src/types.ts'), 'utf8');
  const appViewTypes = fs.readFileSync(path.join(repoRoot, 'app/src/lib/types.ts'), 'utf8');

  const sharedViews = readQuotedValuesFromSharedArray(sharedTypes, 'ASSISTANT_UI_VIEWS').sort();
  const appViews = readAppViewTypes(appViewTypes).sort();

  assert.deepEqual(
    appViews,
    sharedViews,
    'app View union should expose the same route types as shared ASSISTANT_UI_VIEWS',
  );
});

test('assistant UI view routing handles every shared view and keeps list as the only listId-dependent route', () => {
  const sharedTypes = fs.readFileSync(path.join(repoRoot, 'shared/src/types.ts'), 'utf8');
  const assistantUiCommandSource = fs.readFileSync(path.join(repoRoot, 'app/src/lib/assistantUiCommand.ts'), 'utf8');

  const sharedViews = readQuotedValuesFromSharedArray(sharedTypes, 'ASSISTANT_UI_VIEWS');
  const { functionBody, directPairs, hasListCase } = readAssistantViewSwitch(assistantUiCommandSource);
  const directInputs = directPairs.map((pair) => pair.input).sort();
  const sharedNonListViews = sharedViews.filter((view) => view !== 'list').sort();

  assert.deepEqual(
    directInputs,
    sharedNonListViews,
    'assistantCommandViewToAppView should explicitly handle every shared non-list view',
  );

  for (const pair of directPairs) {
    assert.equal(
      pair.output,
      pair.input,
      `assistantCommandViewToAppView should map ${pair.input} directly to the same app view type`,
    );
  }

  assert.equal(
    hasListCase,
    true,
    'assistantCommandViewToAppView should keep list as the only listId-dependent route',
  );
  assert.doesNotMatch(
    functionBody,
    /default:/,
    'assistantCommandViewToAppView should not quietly swallow future shared views with a default branch',
  );
  assert.match(
    functionBody,
    /return assertNever\(view,\s*'assistant UI view'\);/,
    'assistantCommandViewToAppView should keep an explicit exhaustiveness guard for future shared views',
  );
});
