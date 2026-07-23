import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import {
  resolveDatePickerDesktopPosition,
} from '../../../app/src/components/ui/DatePicker.runtime';

test('date picker desktop position prefers below-anchor placement when there is room', () => {
  assert.deepEqual(
    resolveDatePickerDesktopPosition({
      isMobile: false,
      anchorRect: { top: 80, left: 40, bottom: 120 },
      viewportWidth: 800,
      viewportHeight: 700,
    }),
    { top: 124, left: 40 },
  );
});

test('date picker desktop position flips above when below space is insufficient', () => {
  assert.deepEqual(
    resolveDatePickerDesktopPosition({
      isMobile: false,
      anchorRect: { top: 430, left: 760, bottom: 470 },
      viewportWidth: 820,
      viewportHeight: 520,
    }),
    { top: 86, left: 528 },
  );
});

test('date picker desktop position clamps into short and narrow viewports', () => {
  assert.deepEqual(
    resolveDatePickerDesktopPosition({
      isMobile: false,
      anchorRect: { top: 80, left: -80, bottom: 120 },
      viewportWidth: 220,
      viewportHeight: 260,
    }),
    { top: 12, left: 12 },
  );
});

test('date picker position is inert for mobile and offscreen without an anchor', () => {
  assert.deepEqual(
    resolveDatePickerDesktopPosition({
      isMobile: true,
      anchorRect: { top: 80, left: 40, bottom: 120 },
      viewportWidth: 800,
      viewportHeight: 700,
    }),
    { top: 0, left: 0 },
  );
  assert.deepEqual(
    resolveDatePickerDesktopPosition({
      isMobile: false,
      anchorRect: null,
      viewportWidth: 800,
      viewportHeight: 700,
    }),
    { top: -9999, left: -9999 },
  );
});

test('date picker component delegates positioning and Escape stacking to shared seams', () => {
  const controllerSource = fs.readFileSync(
    path.join(process.cwd(), 'app/src/components/ui/DatePicker.controller.ts'),
    'utf8',
  );
  const mobileShellSource = fs.readFileSync(
    path.join(process.cwd(), 'app/src/components/ui/DatePickerMobileSheet.tsx'),
    'utf8',
  );
  const gridSource = fs.readFileSync(
    path.join(process.cwd(), 'app/src/components/ui/DatePickerGrid.tsx'),
    'utf8',
  );

  assert.match(
    controllerSource,
    /import \{ pushModalEscapeHandler \} from '\.\/overlay';/,
  );
  assert.match(
    mobileShellSource,
    /import \{ ModalShell \} from '\.\/overlay';/,
  );
  assert.match(
    controllerSource,
    /import\s+\{[\s\S]*\bresolveDatePickerDesktopPosition\b[\s\S]*\}\s+from '\.\/DatePicker\.runtime';/s,
  );
  assert.match(controllerSource, /return resolveDatePickerDesktopPosition\(\{/);
  assert.match(controllerSource, /anchorRect: anchor\?\.getBoundingClientRect\(\) \?\? null,/);
  assert.match(controllerSource, /return pushModalEscapeHandler\(onClose\);/);
  assert.match(controllerSource, /if \(e\.key === 'Escape'\) \{/);
  assert.match(controllerSource, /const weeks = useMemo\(\(\) => \{/);
  assert.match(gridSource, /\{weeks\.map\(\(week, weekIndex\) => \(/);
  assert.doesNotMatch(gridSource, /role="row">\s*\{grid\.map/s);
  assert.doesNotMatch(controllerSource, /const spaceBelow = window\.innerHeight/);
  assert.doesNotMatch(controllerSource, /document\.addEventListener\('keydown', onDocEscape, true\)/);
  assert.doesNotMatch(controllerSource, /installDatePickerDocumentEscapeRuntime/);
});
