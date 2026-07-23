import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

test('task-detail mutations are organized as a folder-backed subsystem with lifecycle, metadata, and type modules', () => {
  const rootSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/task-detail/controller/mutations.ts'),
    'utf8',
  );
  const lifecycleSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/task-detail/controller/mutations/lifecycle.ts'),
    'utf8',
  );
  const metadataSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/task-detail/controller/mutations/metadata.ts'),
    'utf8',
  );
  const typesSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/task-detail/controller/mutations/types.ts'),
    'utf8',
  );

  assert.match(rootSource, /import \{ useTaskDetailLifecycleMutations \} from '\.\/mutations\/lifecycle';/);
  assert.match(rootSource, /import \{ useTaskDetailMetadataMutations \} from '\.\/mutations\/metadata';/);
  assert.match(rootSource, /export function useTaskDetailMutations\(/);
  assert.match(rootSource, /export type \{ TaskDetailMutationState \} from '\.\/mutations\/types';/);
  assert.doesNotMatch(
    rootSource,
    /const handleComplete = useCallback|const handleDefer = useCallback|const saveMetaPatch = useCallback/,
    'task-detail mutation root should stay a composition boundary after folder extraction',
  );

  assert.match(lifecycleSource, /export function useTaskDetailLifecycleMutations\(/);
  assert.match(lifecycleSource, /handleComplete/);
  assert.match(lifecycleSource, /handleDefer/);
  assert.match(lifecycleSource, /handlePermanentDelete/);
  assert.match(metadataSource, /export function useTaskDetailMetadataMutations\(/);
  assert.match(metadataSource, /saveMetaPatch/);
  assert.match(typesSource, /export interface UseTaskDetailMutationDeps/);
  assert.match(typesSource, /export interface TaskDetailMutationState/);
});
