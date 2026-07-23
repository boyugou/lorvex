import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

test('AppSelect is organized as a folder-backed subsystem with model navigation and style modules', () => {
  const rootSource = fs.readFileSync(path.join(repoRoot, 'app/src/components/ui/AppSelect.tsx'), 'utf8');
  const componentSource = fs.readFileSync(path.join(repoRoot, 'app/src/components/ui/app-select/AppSelect.tsx'), 'utf8');
  const contentSource = fs.readFileSync(path.join(repoRoot, 'app/src/components/ui/app-select/AppSelectContent.tsx'), 'utf8');
  const controllerSource = fs.readFileSync(path.join(repoRoot, 'app/src/components/ui/app-select/useAppSelectController.ts'), 'utf8');
  const modelSource = fs.readFileSync(path.join(repoRoot, 'app/src/components/ui/app-select/model.ts'), 'utf8');
  const navigationSource = fs.readFileSync(path.join(repoRoot, 'app/src/components/ui/app-select/navigation.ts'), 'utf8');
  const stylesSource = fs.readFileSync(path.join(repoRoot, 'app/src/components/ui/app-select/styles.ts'), 'utf8');

  assert.match(rootSource, /export \{ AppSelect \} from '\.\/app-select\/AppSelect';/);
  assert.doesNotMatch(rootSource, /AppSelectProps|AppSelectVariant/);

  assert.match(componentSource, /from '\.\/AppSelectContent';/);
  assert.match(componentSource, /from '\.\/useAppSelectController';/);
  assert.doesNotMatch(
    componentSource,
    /useEffect\(|useState\(|function parseOptions\(|function findNextEnabledOption\(|BASE_TRIGGER_CLASSES/,
    'AppSelect root should stay as a composition layer over the controller and content modules',
  );

  assert.match(contentSource, /BASE_TRIGGER_CLASSES/);
  assert.match(contentSource, /LISTBOX_CLASSES/);
  assert.doesNotMatch(
    contentSource,
    /useEffect\(|useState\(|parseOptions\(|findNextEnabledOption\(/,
    'AppSelect content module should stay focused on rendering and style composition',
  );

  assert.match(controllerSource, /export function useAppSelectController\(/);
  assert.match(controllerSource, /parseOptions\(/);
  assert.match(controllerSource, /findNextEnabledOption\(/);
  assert.match(controllerSource, /useEffect\(/);
  assert.doesNotMatch(
    controllerSource,
    /LISTBOX_CLASSES|<button|<div/,
    'AppSelect controller should own state and keyboard behavior instead of JSX rendering',
  );

  assert.match(modelSource, /type AppSelectVariant = keyof typeof VARIANT_TRIGGER_CLASSES;/);
  assert.match(modelSource, /export function normalizeSelectValue\(/);
  assert.match(modelSource, /export function parseOptions\(/);

  assert.match(navigationSource, /export function findNextEnabledOption\(/);
  assert.doesNotMatch(
    navigationSource,
    /useEffect|useState|Children|isValidElement/,
    'AppSelect navigation helper should stay focused on keyboard traversal logic',
  );

  assert.match(stylesSource, /export const VARIANT_TRIGGER_CLASSES = \{/);
  assert.match(stylesSource, /export function joinClasses\(/);
  assert.match(stylesSource, /export function extractLayoutClasses\(/);
});
