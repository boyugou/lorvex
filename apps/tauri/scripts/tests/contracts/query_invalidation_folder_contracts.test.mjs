import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

const ROOT_FACADE = 'app/src/lib/query/invalidation/index.ts';
const QUERY_KEYS_BARREL = 'app/src/lib/query/queryKeys.ts';
const INVALIDATION_FILES = [
  'app/src/lib/query/invalidation/batch.ts',
  'app/src/lib/query/invalidation/entityMap.ts',
  'app/src/lib/query/invalidation/groups.ts',
  'app/src/lib/query/invalidation/helpers.ts',
  'app/src/lib/query/invalidation/registry.ts',
  'app/src/lib/query/invalidation/types.ts',
];
const EXTRACTED_DECLARATIONS = [
  'function\\s+invalidateKeyHeads\\b',
  'function\\s+invalidateByKeyHeadSet\\b',
  'function\\s+queryHeadList\\b',
  'const\\s+TODAY_SURFACE_QUERY_KEY_HEADS\\b',
  'const\\s+TASK_MUTATION_QUERY_KEY_HEADS\\b',
  'const\\s+EXTERNAL_MUTATION_QUERY_KEY_HEADS\\b',
  'const\\s+QUERY_INVALIDATION_REGISTRY\\b',
  'const\\s+QUERY_ENTITY_INVALIDATION_MAP\\b',
];
const PUBLIC_INVALIDATION_EXPORTS = [
  'QUERY_ENTITY_INVALIDATION_MAP',
  'QUERY_INVALIDATION_REGISTRY',
  'invalidateAllQueries',
  'invalidateCalendarMutationQueries',
  'invalidateCalendarSubscriptionQueries',
  'invalidateCalendarViewQueries',
  'invalidateChangelogQueries',
  'invalidateCurrentFocusQueries',
  'invalidateDailyReviewQueries',
  'invalidateDataImportQueries',
  'invalidateDeviceStateQueries',
  'invalidateExternalMutationQueries',
  'invalidateFocusScheduleQueries',
  'invalidateFocusTaskQueries',
  'invalidateHabitQueries',
  'invalidateHabitReminderQueries',
  'invalidateListContextTaskWriteQueries',
  'invalidateListQueries',
  'invalidateOverviewQueries',
  'invalidatePlanningFocusQueries',
  'invalidatePreferenceQueries',
  'invalidateQueriesForEntity',
  'invalidateTaskCollectionQueries',
  'invalidateTaskDependencyQueries',
  'invalidateTaskDetailWriteQueries',
  'invalidateTaskMutationQueries',
  'invalidateTaskQueries',
  'invalidateTaskReminderQueries',
  'invalidateTaskStatusChangeQueries',
  'invalidateTaskWorkspaceQueries',
  'invalidateTodayBootstrapQueries',
  'invalidateTodaySurfaceQueries',
  'queryKeyHeadsForInvalidationIntent',
];

function read(relativePath) {
  return fs.readFileSync(path.join(repoRoot, relativePath), 'utf8');
}

test('query invalidation is organized as a folder-backed subsystem', () => {
  const root = read(ROOT_FACADE);
  const queryKeysBarrel = read(QUERY_KEYS_BARREL);
  const queryInvalidationExportBlock = queryKeysBarrel.match(
    /export\s+\{([\s\S]*?)\}\s+from\s+'\.\/invalidation';/,
  )?.[1] ?? '';

  for (const relativePath of INVALIDATION_FILES) {
    assert.ok(
      fs.existsSync(path.join(repoRoot, relativePath)),
      `${relativePath} should exist as a focused query invalidation module`,
    );
  }

  assert.match(
    root,
    /export \{[\s\S]*\} from '\.\/helpers';/,
    'invalidation/index.ts should stay a thin facade over focused invalidation modules',
  );

  for (const declarationPattern of EXTRACTED_DECLARATIONS) {
    assert.doesNotMatch(
      root,
      new RegExp(declarationPattern),
      `${declarationPattern} should not be implemented in the queryInvalidation root facade`,
    );
  }

  const rootLineCount = root.split(/\r?\n/).length;
  assert.ok(
    rootLineCount <= 80,
    `invalidation/index.ts should stay a thin facade, found ${rootLineCount} lines`,
  );

  for (const exportName of PUBLIC_INVALIDATION_EXPORTS) {
    assert.match(
      queryInvalidationExportBlock,
      new RegExp(`\\b${exportName}\\b`),
      `queryKeys.ts should keep exporting ${exportName} from the query invalidation facade`,
    );
  }
});
