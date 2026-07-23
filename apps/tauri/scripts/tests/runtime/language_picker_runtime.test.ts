import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import {
  createBrowserLanguagePickerDismissRuntimeDeps,
  getNextLanguagePickerFocusIndex,
  getNextLanguagePickerSearchFocusIndex,
  installLanguagePickerDismissRuntime,
  resolveLanguagePickerDropdownPosition,
  scheduleLanguagePickerSearchFocusRuntime,
  shouldDismissLanguagePickerFromPointerTarget,
  shouldDismissLanguagePickerFromScrollTarget,
} from '../../../app/src/components/settings/LanguagePicker.runtime';

test('language picker dropdown position opens below by default and flips above when below space is tight', () => {
  assert.deepEqual(
    resolveLanguagePickerDropdownPosition(
      { top: 100, left: 40, bottom: 132 },
      { viewportWidth: 800, viewportHeight: 700 },
    ),
    { top: 138, left: 40 },
  );
  assert.deepEqual(
    resolveLanguagePickerDropdownPosition(
      { top: 360, left: 60, bottom: 392 },
      { viewportWidth: 800, viewportHeight: 520 },
    ),
    { top: 74, left: 60 },
  );
});

test('language picker dismiss predicates preserve events from inside the trigger or dropdown', () => {
  const insideTarget = new EventTarget();
  const outsideTarget = new EventTarget();
  const isInsideTarget = (target: EventTarget | null) => target === insideTarget;

  assert.equal(shouldDismissLanguagePickerFromPointerTarget(insideTarget, isInsideTarget), false);
  assert.equal(shouldDismissLanguagePickerFromPointerTarget(outsideTarget, isInsideTarget), true);
  assert.equal(shouldDismissLanguagePickerFromScrollTarget(insideTarget, isInsideTarget), false);
  assert.equal(shouldDismissLanguagePickerFromScrollTarget(outsideTarget, isInsideTarget), true);
});

test('language picker dismiss runtime closes on outside pointer or scroll and unregisters listeners', () => {
  const calls: string[] = [];
  let mouseDownListener: ((event: MouseEvent) => void) | undefined;
  let scrollListener: ((event: Event) => void) | undefined;
  const insideTarget = new EventTarget();
  const outsideTarget = new EventTarget();

  const cleanup = installLanguagePickerDismissRuntime({
    addDocumentMouseDownListener: (listener) => {
      mouseDownListener = listener;
      return () => {
        mouseDownListener = undefined;
        calls.push('cleanup-mousedown');
      };
    },
    addDocumentScrollListener: (listener) => {
      scrollListener = listener;
      return () => {
        scrollListener = undefined;
        calls.push('cleanup-scroll');
      };
    },
    isInsideTarget: (target) => target === insideTarget,
    onDismiss: () => calls.push('dismiss'),
  });

  mouseDownListener?.({ target: insideTarget } as MouseEvent);
  scrollListener?.({ target: insideTarget } as Event);
  mouseDownListener?.({ target: outsideTarget } as MouseEvent);
  scrollListener?.({ target: outsideTarget } as Event);
  cleanup();

  assert.deepEqual(calls, [
    'dismiss',
    'dismiss',
    'cleanup-mousedown',
    'cleanup-scroll',
  ]);
  assert.equal(mouseDownListener, undefined);
  assert.equal(scrollListener, undefined);
});

test('language picker dismiss runtime is inert without document hosts', () => {
  const cleanup = installLanguagePickerDismissRuntime({
    addDocumentMouseDownListener: null,
    addDocumentScrollListener: null,
    isInsideTarget: () => false,
    onDismiss: () => {
      throw new Error('dismiss should not run without installed listeners');
    },
  });

  cleanup();
});

test('language picker browser dismiss deps delegate document and Node wiring to shared runtime', () => {
  const calls: string[] = [];
  let mouseDownListener: ((event: MouseEvent) => void) | undefined;
  let scrollListener: ((event: Event) => void) | undefined;
  const isCapture = (options?: boolean | AddEventListenerOptions | EventListenerOptions) =>
    options === true || (typeof options === 'object' && options.capture === true);
  const insideNode = {} as Node;
  const outsideNode = {} as Node;
  const documentTarget = {
    addEventListener: (type: string, listener: EventListener, options?: boolean | AddEventListenerOptions) => {
      if (type === 'mousedown') mouseDownListener = listener as (event: MouseEvent) => void;
      if (type === 'scroll' && isCapture(options)) scrollListener = listener as (event: Event) => void;
    },
    removeEventListener: (type: string, listener: EventListener, options?: boolean | EventListenerOptions) => {
      if (type === 'mousedown' && mouseDownListener === listener) mouseDownListener = undefined;
      if (type === 'scroll' && isCapture(options) && scrollListener === listener) scrollListener = undefined;
    },
  };
  const trigger = { contains: (node: Node) => node === insideNode } as HTMLElement;
  const panel = { contains: () => false } as unknown as HTMLElement;

  const cleanup = installLanguagePickerDismissRuntime(
    createBrowserLanguagePickerDismissRuntimeDeps({
      documentTarget,
      getTrigger: () => trigger,
      getPanel: () => panel,
      nodeConstructor: Object as unknown as typeof Node,
      onDismiss: () => calls.push('dismiss'),
    }),
  );

  mouseDownListener?.({ target: insideNode } as MouseEvent);
  mouseDownListener?.({ target: outsideNode } as MouseEvent);
  scrollListener?.({ target: outsideNode } as Event);
  cleanup();

  assert.deepEqual(calls, ['dismiss', 'dismiss']);
  assert.equal(mouseDownListener, undefined);
  assert.equal(scrollListener, undefined);
});

test('language picker roving focus clamps arrow, home, and end navigation', () => {
  assert.equal(getNextLanguagePickerFocusIndex('ArrowDown', -1, 4), 0);
  assert.equal(getNextLanguagePickerFocusIndex('ArrowDown', 2, 4), 3);
  assert.equal(getNextLanguagePickerFocusIndex('ArrowDown', 3, 4), 3);
  assert.equal(getNextLanguagePickerFocusIndex('ArrowUp', 0, 4), 0);
  assert.equal(getNextLanguagePickerFocusIndex('ArrowUp', 3, 4), 2);
  assert.equal(getNextLanguagePickerFocusIndex('Home', 2, 4), 0);
  assert.equal(getNextLanguagePickerFocusIndex('End', 0, 4), 3);
  assert.equal(getNextLanguagePickerFocusIndex('ArrowDown', -1, 0), -1);
  assert.equal(getNextLanguagePickerFocusIndex('Enter', 2, 4), 2);
});

test('language picker search field only yields focus to arrow navigation', () => {
  assert.equal(getNextLanguagePickerSearchFocusIndex('ArrowDown', 4), 0);
  assert.equal(getNextLanguagePickerSearchFocusIndex('ArrowUp', 4), 3);
  assert.equal(getNextLanguagePickerSearchFocusIndex('Home', 4), -1);
  assert.equal(getNextLanguagePickerSearchFocusIndex('End', 4), -1);
  assert.equal(getNextLanguagePickerSearchFocusIndex('Enter', 4), -1);
  assert.equal(getNextLanguagePickerSearchFocusIndex(' ', 4), -1);
  assert.equal(getNextLanguagePickerSearchFocusIndex('ArrowDown', 0), -1);
});

test('language picker deferred focus runtime clears pending focus on cleanup', () => {
  const calls: string[] = [];
  let pending: (() => void) | undefined;

  const cleanup = scheduleLanguagePickerSearchFocusRuntime({
    setTimeout: (callback) => {
      pending = callback;
      calls.push('schedule');
      return 'timer';
    },
    clearTimeout: (handle) => {
      assert.equal(handle, 'timer');
      pending = undefined;
      calls.push('clear');
    },
    focusSearchInput: () => calls.push('focus'),
  });

  cleanup();
  pending?.();

  assert.deepEqual(calls, ['schedule', 'clear']);
});

test('language picker component delegates browser positioning, dismissal, and deferred focus to runtime seams', () => {
  const source = fs.readFileSync(
    path.join(process.cwd(), 'app/src/components/settings/LanguagePicker.tsx'),
    'utf8',
  );
  const runtimeSource = fs.readFileSync(
    path.join(process.cwd(), 'app/src/components/settings/LanguagePicker.runtime.ts'),
    'utf8',
  );

  assert.match(
    source,
    /import \{[\s\S]*createBrowserLanguagePickerDeferredFocusTimerHost,[\s\S]*getNextLanguagePickerFocusIndex,[\s\S]*installLanguagePickerDismissRuntime,[\s\S]*resolveLanguagePickerDropdownPosition,[\s\S]*scheduleLanguagePickerSearchFocusRuntime,[\s\S]*\} from '\.\/LanguagePicker\.runtime';/s,
  );
  assert.match(
    source,
    /const languagePickerDeferredFocusTimerHost = createBrowserLanguagePickerDeferredFocusTimerHost\(\);/,
  );
  assert.match(
    source,
    /setDropdownPos\(resolveLanguagePickerDropdownPosition\(rect, \{[\s\S]*viewportWidth: window\.innerWidth,[\s\S]*viewportHeight: window\.innerHeight,[\s\S]*\}\)\);/s,
  );
  assert.match(
    source,
    /const cleanupFocus = scheduleLanguagePickerSearchFocusRuntime\(\{[\s\S]*focusSearchInput:[\s\S]*\.\.\.languagePickerDeferredFocusTimerHost,[\s\S]*\}\);/s,
  );
  assert.match(
    source,
    /const cleanupDismiss = installLanguagePickerDismissRuntime\(\s*createBrowserLanguagePickerDismissRuntimeDeps\(\{[\s\S]*getTrigger: \(\) => buttonRef\.current,[\s\S]*getPanel: \(\) => dropdownRef\.current,[\s\S]*onDismiss:/s,
  );
  assert.doesNotMatch(source, /globalThis\.setTimeout/);
  assert.doesNotMatch(source, /globalThis\.clearTimeout/);
  assert.doesNotMatch(source, /const handleMouseDown = \(e: MouseEvent\) => \{/);
  assert.doesNotMatch(source, /const handleScroll = \(e: Event\) => \{/);
  assert.match(
    runtimeSource,
    /import \{[\s\S]*createBrowserAnchoredPopupDismissRuntimeDeps,[\s\S]*installAnchoredPopupDismissRuntime,[\s\S]*resolveAnchoredPopupPosition,[\s\S]*shouldDismissAnchoredPopupFromTarget,[\s\S]*\} from '\.\.\/ui\/portalDropdown\.runtime';/s,
  );
});

test('language picker component exposes listbox semantics and roving keyboard focus', () => {
  const source = fs.readFileSync(
    path.join(process.cwd(), 'app/src/components/settings/LanguagePicker.tsx'),
    'utf8',
  );

  assert.match(source, /const listboxId = useId\(\);/);
  assert.match(source, /const optionIdPrefix = useId\(\);/);
  assert.match(source, /aria-haspopup="listbox"/);
  assert.match(source, /aria-expanded=\{open\}/);
  assert.match(source, /aria-controls=\{open \? listboxId : undefined\}/);
  assert.match(source, /role="listbox"/);
  assert.match(source, /aria-activedescendant=\{activeDescendantId\}/);
  assert.match(source, /role="combobox"/);
  assert.match(source, /aria-autocomplete="list"/);
  assert.match(source, /aria-expanded=\{open && languageOptions\.length > 0\}/);
  assert.match(source, /aria-controls=\{listboxId\}/);
  assert.match(source, /aria-activedescendant=\{searchActiveDescendantId\}/);
  assert.match(source, /role="option"/);
  assert.match(source, /aria-selected=/);
  assert.match(source, /tabIndex=\{focusedIndex === i \? 0 : -1\}/);
  assert.match(source, /getNextLanguagePickerFocusIndex\(e\.key, focusedIndex, languageOptions\.length\)/);
  assert.match(source, /getNextLanguagePickerSearchFocusIndex\(e\.key, languageOptions\.length\)/);
  assert.match(source, /const \[searchFocused, setSearchFocused\] = useState\(false\);/);
  assert.match(source, /const searchActiveDescendantId = searchFocused \? activeDescendantId : undefined;/);
  assert.match(source, /onFocus=\{\(\) => \{[\s\S]*setSearchFocused\(true\);[\s\S]*setFocusedIndex\(-1\);[\s\S]*\}\}/);
  assert.match(source, /onBlur=\{\(\) => setSearchFocused\(false\)\}/);
  assert.match(source, /if \(e\.key !== 'ArrowDown' && e\.key !== 'ArrowUp'\) \{[\s\S]*e\.stopPropagation\(\);[\s\S]*return;[\s\S]*\}/);
  assert.match(source, /if \(e\.key === 'Enter' \|\| e\.key === ' '\) \{[\s\S]*e\.stopPropagation\(\);[\s\S]*return;[\s\S]*\}/);
});
