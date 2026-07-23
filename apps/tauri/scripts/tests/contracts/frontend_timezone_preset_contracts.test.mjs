import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { readTypeScriptSources, repoRoot } from './shared.mjs';

test('task date presets derive from a shared configured-timezone day-context helper', () => {
  const dayContextSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/lib/dayContext.ts'),
    'utf8',
  );
  const dayContextMathSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/lib/dayContextMath.ts'),
    'utf8',
  );
  const taskMetadataSource = readTypeScriptSources(
    'app/src/components/task-detail/metadata-editor',
  );
  const snoozeSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/task-detail/metadata-editor/TaskUnifiedMetaCard.tsx'),
    'utf8',
  );

  assert.match(
    dayContextSource,
    /export function useConfiguredTimezone\(/,
    'frontend should expose a shared configured-timezone hook for day-context consumers',
  );
  assert.match(
    dayContextSource,
    /export function getRelativeDateYmd\(/,
    'frontend should expose a shared timezone-aware relative-date helper',
  );
  assert.match(
    dayContextMathSource,
    /export function getNextWeekendYmd\(/,
    'frontend should expose a shared pure timezone-aware weekend helper',
  );
  assert.match(
    dayContextMathSource,
    /export function getNextMondayYmd\(/,
    'frontend should expose a shared pure timezone-aware next-Monday helper',
  );

  assert.equal(
    fs.existsSync(path.join(repoRoot, 'app/src/components/task-detail/TaskMetadataEditor.tsx')),
    false,
    'TaskMetadataEditor should not keep a thin metadata-editor facade',
  );
  assert.match(
    taskMetadataSource,
    /export function TaskSecondaryMetaFields\(/,
    'TaskSecondaryMetaFields should own the extracted metadata-editor subtree',
  );

  assert.match(
    snoozeSource,
    /from ['"](?:@\/lib\/dayContext|(?:\.\.\/){2,3}lib\/dayContext)['"]/,
    'TaskUnifiedMetaCard should import configured-timezone day-context state for defer/snooze presets',
  );
  assert.match(
    snoozeSource,
    /from ['"]@\/lib\/dayContextMath['"]/,
    'TaskUnifiedMetaCard should import pure date helpers from dayContextMath directly',
  );
  assert.match(
    snoozeSource,
    /const \{ timezone \} = useConfiguredTimezone\(\);/,
    'TaskUnifiedMetaCard defer chips should resolve preset dates from the configured timezone',
  );
  assert.match(
    snoozeSource,
    /getRelativeDateYmd\(timezone, chip\.days\)|getRelativeDateYmd\(timezone,\s*1\)|getNextWeekendYmd\(timezone\)|getNextMondayYmd\(timezone\)/,
    'TaskUnifiedMetaCard defer/snooze presets should use shared timezone-aware date helpers',
  );
  assert.doesNotMatch(
    snoozeSource,
    /function toLocalISODate\(|function nextWeekend\(|function nextMonday\(/,
    'TaskUnifiedMetaCard should not keep inline browser-local date helper implementations',
  );
});
