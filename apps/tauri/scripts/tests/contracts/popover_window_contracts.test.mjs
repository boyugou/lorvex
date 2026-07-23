import assert from 'node:assert/strict';
import test from 'node:test';

import { readTypeScriptSources } from './shared.mjs';

test('popover quick capture and open-app fallback hide the popover after a successful main-window handoff', () => {
  const source = readTypeScriptSources(
    'app/src/components/popover-window/usePopoverWindowController.ts',
    'app/src/components/popover-window/controller',
  );

  assert.match(
    source,
    /const handleQuickCapture = useCallback\(async \(\) => \{\s*try \{\s*await openMainQuickCapture\(\);\s*await requestHidePopover\(\);\s*\} catch \(error\) \{/s,
    'Popover quick capture should hide the popover after the main window opens the quick capture surface',
  );
  assert.match(
    source,
    /const handleOpenMain = useCallback\(\(\) => \{[\s\S]*?handleOpenTask\([\s\S]*?void handleQuickCapture\(\);\s*\}, \[handleOpenTask, handleQuickCapture, nextUpTasks\]\);/s,
    'Open App fallback should reuse the same quick-capture handoff path when there is no next-up task',
  );
  assert.doesNotMatch(
    source,
    /const handleQuickCapture = \(\) => \{\s*openMainQuickCapture\(\)\.catch\(/s,
    'Popover quick capture should not fire-and-forget the app handoff without closing the popover',
  );
});

test('popover summary loading and task completion guard late async writes after teardown', () => {
  const source = readTypeScriptSources(
    'app/src/components/popover-window/usePopoverWindowController.ts',
    'app/src/components/popover-window/controller',
  );

  assert.match(
    source,
    /const popoverMountedRef = (?:useRef\(false\)|useMounted\(\));/,
    'PopoverWindow should track whether the overlay is still mounted before committing async state',
  );
  assert.match(
    source,
    /loadSummaryRequestIdRef\.current \+= 1/,
    'PopoverWindow should invalidate in-flight summary loads when the overlay unmounts',
  );
  assert.match(
    source,
    /const \[overviewResult, currentFocusResult, eventsResult[\s\S]*?\] = await Promise\.allSettled\(\[[\s\S]*?\]\);\s*if \(!popoverMountedRef\.current \|\| requestId !== loadSummaryRequestIdRef\.current\) return;/s,
    'PopoverWindow should abort summary updates when the overlay is already unmounted or superseded',
  );
  assert.match(
    source,
    /finally \{\s*if \(popoverMountedRef\.current\) \{\s*setCompletingTaskIds\(\(current\) => current\.filter\(\(id\) => id !== taskId\)\);\s*}\s*}/s,
    'PopoverWindow should avoid clearing completing state after the overlay already unmounted',
  );
});
