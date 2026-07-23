import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

test('schedule timeline keeps mutation wiring in a dedicated runtime hook', () => {
  const contentSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/schedule-timeline/ScheduleTimelineContent.tsx'),
    'utf8',
  );
  const actionsSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/schedule-timeline/useScheduleTimelineActions.ts'),
    'utf8',
  );

  assert.match(
    contentSource,
    /export default function ScheduleTimelineContent/,
    'schedule timeline should live in the folder-backed content module',
  );
  assert.match(
    contentSource,
    /import \{ useScheduleTimelineActions \} from '\.\/useScheduleTimelineActions';/,
    'Schedule timeline content should delegate mutations to a dedicated runtime hook',
  );
  assert.doesNotMatch(
    contentSource,
    /useMutation\(\{/,
    'Schedule timeline content should not keep inline mutation ownership',
  );
  assert.match(
    actionsSource,
    /export function useScheduleTimelineActions\(/,
    'Schedule timeline mutations should live in a dedicated runtime hook',
  );
  assert.match(
    actionsSource,
    /useMutation\(\{/,
    'Schedule timeline runtime hook should own mutation wiring',
  );
});

test('schedule timeline complete control has a stable compact hit target', () => {
  const taskBlockSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/schedule-timeline/TaskBlock.tsx'),
    'utf8',
  );

  assert.match(
    taskBlockSource,
    /className="w-6 h-6 shrink-0 flex items-center justify-center focus-ring-soft rounded-full/,
    'Schedule timeline complete button should own a stable 24px hit target.',
  );
  assert.match(
    taskBlockSource,
    /className="w-6 shrink-0 flex items-center justify-center self-stretch"/,
    'Schedule timeline complete lane should reserve the 24px button width so hover/focus cannot shift layout.',
  );
  assert.match(
    taskBlockSource,
    /className=\{`flex w-\[16px\] h-\[16px\] rounded-full/,
    'Schedule timeline complete glyph should remain the compact 16px visual circle inside the larger target.',
  );
});
