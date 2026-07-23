import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

test('WeekGrid completed-task popover renders through the shared fixed popover layer', () => {
  const completedTasksPopoverSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/calendar/CompletedTasksPopover.tsx'),
    'utf8',
  );

  assert.match(
    completedTasksPopoverSource,
    /createPortal\(/,
    'completed-task popover should portal out of week-grid overflow clipping',
  );
  assert.match(
    completedTasksPopoverSource,
    /getPopoverLayerClasses\('popover'\)/,
    'completed-task popover should use the canonical popover layer classes',
  );
  assert.match(
    completedTasksPopoverSource,
    /computeCompletedTasksPopoverPosition\(/,
    'completed-task popover should use the shared viewport clamp helper',
  );
  assert.doesNotMatch(
    completedTasksPopoverSource,
    /absolute z-10/,
    'completed-task popover should not use inline absolute z-index layering',
  );
  assert.match(
    completedTasksPopoverSource,
    /line-through[\s\S]{0,220}focus-ring-soft/,
    'completed-task popover rows should keep canonical keyboard focus styling',
  );
});
