import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { readTypeScriptSources, repoRoot } from './shared.mjs';

test('PopoverWindow is organized as a folder-backed subsystem with controller and content modules', () => {
  const rootSource = fs.readFileSync(path.join(repoRoot, 'app/src/components/PopoverWindow.tsx'), 'utf8');
  const controllerSource = readTypeScriptSources(
    'app/src/components/popover-window/usePopoverWindowController.ts',
    'app/src/components/popover-window/controller',
  );
  const contentSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/popover-window/PopoverWindowContent.tsx'),
    'utf8',
  );

  assert.match(
    rootSource,
    /import PopoverWindowContent from '\.\/popover-window\/PopoverWindowContent';/,
    'PopoverWindow root should render the dedicated popover-window content module',
  );
  assert.match(
    rootSource,
    /import \{ usePopoverWindowController \} from '\.\/popover-window\/usePopoverWindowController';/,
    'PopoverWindow root should delegate overlay runtime behavior to a dedicated controller module',
  );
  assert.match(
    rootSource,
    /const controller = usePopoverWindowController\(\);/,
    'PopoverWindow root should remain a thin composition layer over the controller state',
  );
  assert.match(controllerSource, /export function usePopoverWindowController\(/);
  assert.match(controllerSource, /export function usePopoverSummary\(/);
  assert.match(controllerSource, /export function usePopoverWindowLifecycle\(/);
  assert.match(controllerSource, /export function usePopoverWindowActions\(/);
  assert.match(contentSource, /export default function PopoverWindowContent/);
});
