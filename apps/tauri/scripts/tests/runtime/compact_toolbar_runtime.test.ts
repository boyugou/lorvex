import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import {
  createBrowserCompactToolbarFocusTimerHost,
  deferCompactToolbarFocus,
  type CompactToolbarFocusTimerHost,
} from '../../../app/src/components/quick-capture/CompactToolbar.runtime';

test('compact toolbar defers focus through the injected timer host', () => {
  const callbacks: Array<() => void> = [];
  const delays: number[] = [];
  const host: CompactToolbarFocusTimerHost = {
    setTimeout: (callback, delayMs) => {
      callbacks.push(callback);
      delays.push(delayMs);
      return 'compact-toolbar-focus-timer';
    },
  };

  let focusCount = 0;
  deferCompactToolbarFocus(host, () => {
    focusCount += 1;
  });

  assert.deepEqual(delays, [0]);
  assert.equal(focusCount, 0);

  callbacks[0]?.();
  assert.equal(focusCount, 1);
});

test('compact toolbar delegates browser focus timer wiring to the runtime seam', () => {
  const source = fs.readFileSync(
    path.join(process.cwd(), 'app/src/components/quick-capture/toolbar/TagsToggle.tsx'),
    'utf8',
  );
  const runtimeSource = fs.readFileSync(
    path.join(process.cwd(), 'app/src/components/quick-capture/CompactToolbar.runtime.ts'),
    'utf8',
  );

  assert.match(
    source,
    /import \{[\s\S]*createBrowserCompactToolbarFocusTimerHost,[\s\S]*deferCompactToolbarFocus,[\s\S]*\} from '\.\.\/CompactToolbar\.runtime';/s,
  );
  assert.match(source, /const compactToolbarFocusTimerHost = createBrowserCompactToolbarFocusTimerHost\(\);/);
  assert.match(source, /const tagSuggestionsListboxId = useId\(\);/);
  assert.match(source, /aria-controls=\{showDropdown \? tagSuggestionsListboxId : undefined\}/);
  assert.match(source, /aria-activedescendant=\{activeSuggestionId\}/);
  assert.match(source, /id=\{tagSuggestionsListboxId\}/);
  assert.match(source, /id=\{`\$\{tagSuggestionsListboxId\}-option-\$\{idx\}`\}/);
  assert.match(
    source,
    /deferCompactToolbarFocus\([\s\S]*compactToolbarFocusTimerHost,[\s\S]*\(\) => inputRef\.current\?\.focus\(\),[\s\S]*\);/s,
  );
  assert.doesNotMatch(source, /(?<!\.)\bsetTimeout\(/);

  assert.match(runtimeSource, /export function createBrowserCompactToolbarFocusTimerHost\(\): CompactToolbarFocusTimerHost/);
  assert.match(runtimeSource, /setTimeout: \(callback, delayMs\) => globalThis\.setTimeout\(callback, delayMs\),/);
});

test('compact toolbar runtime owns the browser focus timer host wiring', () => {
  const host = createBrowserCompactToolbarFocusTimerHost();
  assert.equal(typeof host.setTimeout, 'function');
});

test('quick capture toolbar popovers route Escape through the modal stack', () => {
  for (const fileName of ['PriorityDropdown.tsx', 'DurationDropdown.tsx']) {
    const source = fs.readFileSync(
      path.join(process.cwd(), `app/src/components/quick-capture/toolbar/${fileName}`),
      'utf8',
    );

    assert.match(
      source,
      /import \{ pushModalEscapeHandler \} from '@\/components\/ui\/overlay';/,
      `${fileName} should share ModalShell's Escape stack instead of installing an independent listener`,
    );
    assert.match(
      source,
      /useLayoutEffect\(\(\) => \{\s*if \(!open\) return;\s*return pushModalEscapeHandler\(\(\) => (?:closeMenu|closePanel)\(true\)\);\s*\}, \[(?:closeMenu|closePanel), open\]\);/s,
      `${fileName} should register only while the popover is open and close just the popover on Escape`,
    );
    assert.doesNotMatch(
      source,
      /document\.addEventListener\(['"]keydown['"]/,
      `${fileName} should not bypass the shared modal Escape stack`,
    );
  }
});

test('quick capture toolbar popovers render portaled accessible popups', () => {
  const prioritySource = fs.readFileSync(
    path.join(process.cwd(), 'app/src/components/quick-capture/toolbar/PriorityDropdown.tsx'),
    'utf8',
  );
  const durationSource = fs.readFileSync(
    path.join(process.cwd(), 'app/src/components/quick-capture/toolbar/DurationDropdown.tsx'),
    'utf8',
  );

  for (const [fileName, source] of [
    ['PriorityDropdown.tsx', prioritySource],
    ['DurationDropdown.tsx', durationSource],
  ] as const) {
    assert.match(source, /import \{ createPortal \} from 'react-dom';/, `${fileName} should portal above Modal overflow`);
    assert.match(source, /resolveAnchoredPopupPosition/, `${fileName} should position the portaled popup from the trigger rect`);
    assert.match(source, /createPortal\(/, `${fileName} should render its popup through a portal`);
    assert.match(source, /document\.body/, `${fileName} should portal into document.body`);
    assert.match(
      source,
      /style=\{\{ position: 'fixed', top: panelPos\.top, left: panelPos\.left/,
      `${fileName} popup should be fixed-positioned from the resolved viewport coordinates`,
    );
    assert.doesNotMatch(
      source,
      /aria-haspopup="listbox"/,
      `${fileName} should not announce a listbox while rendering non-listbox popup content`,
    );
    assert.doesNotMatch(
      source,
      /className="absolute top-full/,
      `${fileName} should not render the popup as an absolute child that can be clipped by Modal overflow`,
    );
  }

  assert.match(prioritySource, /aria-haspopup="menu"/);
  assert.match(prioritySource, /role="menu"/);
  assert.match(prioritySource, /role="menuitemradio"/);
  assert.match(prioritySource, /aria-checked=\{priority === opt\.value\}/);
  assert.match(prioritySource, /role="menuitem"/);

  assert.match(durationSource, /aria-haspopup="dialog"/);
  assert.match(durationSource, /role="dialog"/);
  assert.match(durationSource, /aria-label=\{t\('capture\.durationPlaceholder'\)\}/);
});

test('quick capture priority dropdown wires roving keyboard focus and menuitemradio selection', () => {
  const source = fs.readFileSync(
    path.join(process.cwd(), 'app/src/components/quick-capture/toolbar/PriorityDropdown.tsx'),
    'utf8',
  );

  assert.match(source, /const optionRefs = useRef<\(HTMLButtonElement \| null\)\[\]>\(\[\]\);/);
  assert.match(source, /const \[focusedIdx, setFocusedIdx\] = useState\(0\);/);
  assert.match(source, /function handleMenuKeyDown\(event: React\.KeyboardEvent<HTMLDivElement>\)/);
  assert.match(source, /if \(event\.key === 'ArrowDown' \|\| event\.key === 'ArrowUp'\)/);
  assert.match(source, /if \(event\.key === 'Enter' \|\| event\.key === ' '\)/);
  assert.match(source, /onKeyDown=\{handleMenuKeyDown\}/);
  assert.match(source, /ref=\{\(node\) => \{ optionRefs\.current\[idx\] = node; \}\}/);
  assert.match(source, /tabIndex=\{focusedIdx === idx \? 0 : -1\}/);
  assert.match(source, /aria-checked=\{priority === opt\.value\}/);
});

test('quick capture toolbar popovers close on Tab without trapping browser focus', () => {
  const prioritySource = fs.readFileSync(
    path.join(process.cwd(), 'app/src/components/quick-capture/toolbar/PriorityDropdown.tsx'),
    'utf8',
  );
  const durationSource = fs.readFileSync(
    path.join(process.cwd(), 'app/src/components/quick-capture/toolbar/DurationDropdown.tsx'),
    'utf8',
  );

  assert.match(
    prioritySource,
    /if \(event\.key === 'Tab'\) \{\s*closeMenu\(false\);\s*return;\s*\}/,
    'PriorityDropdown should close on Tab while preserving normal tab order',
  );
  assert.match(
    durationSource,
    /if \(event\.key === 'Tab'\) \{\s*closePanel\(false\);\s*return;\s*\}\s*if \(event\.target instanceof HTMLInputElement\) return;/,
    'DurationDropdown should close on Tab before the input-target early return',
  );
});

test('quick capture duration dropdown establishes stable keyboard focus order', () => {
  const source = fs.readFileSync(
    path.join(process.cwd(), 'app/src/components/quick-capture/toolbar/DurationDropdown.tsx'),
    'utf8',
  );

  assert.match(source, /const durationControlRefs = useRef<\(HTMLElement \| null\)\[\]>\(\[\]\);/);
  assert.match(source, /const \[focusedControlIdx, setFocusedControlIdx\] = useState\(0\);/);
  assert.match(source, /function resolveInitialDurationFocusIndex\(\): number/);
  assert.match(source, /function handlePanelKeyDown\(event: React\.KeyboardEvent<HTMLDivElement>\)/);
  assert.match(source, /if \(event\.target instanceof HTMLInputElement\) return;/);
  assert.match(source, /onKeyDown=\{handlePanelKeyDown\}/);
  assert.match(source, /durationControlRefs\.current\[idx\] = node;/);
  assert.match(source, /durationControlRefs\.current\[DURATION_CHIP_VALUES\.length\] = node;/);
  assert.match(source, /durationControlRefs\.current\[DURATION_CHIP_VALUES\.length \+ 1\] = node;/);
});
