import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { readTypeScriptSources, repoRoot } from './shared.mjs';

test('CommandPalette is organized as a folder-backed subsystem with controller runtime modules, model, and task-result modules', () => {
  const rootSource = fs.readFileSync(path.join(repoRoot, 'app/src/components/CommandPalette.tsx'), 'utf8');
  const controllerSource = readTypeScriptSources(
    'app/src/components/command-palette/useCommandPaletteController.ts',
    'app/src/components/command-palette/controller',
  );
  const modelSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/command-palette/model.ts'),
    'utf8',
  );
  const taskResultSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/command-palette/TaskResult.tsx'),
    'utf8',
  );

  assert.match(
    rootSource,
    /import TaskResult from '\.\/command-palette\/TaskResult';/,
    'CommandPalette root should render task rows through the dedicated TaskResult module',
  );
  assert.match(
    rootSource,
    /useCommandPaletteController\(props\)/,
    'CommandPalette root should delegate search and mutation orchestration to the dedicated controller',
  );
  assert.match(
    modelSource,
    /export function getPaletteOptionId\(key: string\): string \{/,
    'CommandPalette should keep option-id semantics in a dedicated model module',
  );
  assert.match(
    controllerSource,
    /export function useCommandPaletteController\(\{/,
    'CommandPalette should keep keyboard orchestration in a dedicated controller composition root',
  );
  assert.match(
    controllerSource,
    /export function usePaletteMutationActions\(/,
    'CommandPalette mutations should live in a dedicated runtime module',
  );
  assert.match(
    controllerSource,
    /export function usePaletteState\(/,
    'CommandPalette state and query loading should live in a dedicated runtime module',
  );
  assert.match(
    controllerSource,
    /export function usePaletteSelection\(/,
    'CommandPalette selection preservation should live in a dedicated runtime module',
  );
  assert.match(
    controllerSource,
    /export function usePaletteKeyboard\(/,
    'CommandPalette keyboard orchestration should live in a dedicated runtime module',
  );
  assert.match(
    controllerSource,
    /export function useCommandPaletteResults\(/,
    'CommandPalette result assembly should live in a dedicated runtime module',
  );
  assert.match(
    taskResultSource,
    /export default function TaskResult/,
    'CommandPalette task-row rendering should live in a dedicated module',
  );
});
