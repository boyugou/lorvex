import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

test('ListView keeps the root surface as a composition boundary over list-view modules', () => {
  const rootSource = fs.readFileSync(path.join(repoRoot, 'app/src/components/ListView.tsx'), 'utf8');
  const controllerSource = fs.readFileSync(path.join(repoRoot, 'app/src/components/list-view/useListViewController.ts'), 'utf8');
  const contentSource = fs.readFileSync(path.join(repoRoot, 'app/src/components/list-view/ListViewContent.tsx'), 'utf8');
  const supportSource = fs.readFileSync(path.join(repoRoot, 'app/src/components/list-view/support.ts'), 'utf8');

  assert.match(rootSource, /useRuntimeProfile\(/);
  assert.match(rootSource, /useListViewController\(/);
  assert.match(rootSource, /<ListViewContent/);
  assert.match(rootSource, /\bclarity-first-surface\b/);
  assert.doesNotMatch(
    rootSource,
    /const listViewMountedRef = useRef\(true\);|await quickCapture\(|await deleteList\(/,
    'ListView root should stay focused on platform-aware composition instead of mutation runtime details',
  );

  assert.match(controllerSource, /export function useListViewController\(/);
  assert.match(controllerSource, /const listViewMountedRef = useMounted\(\);/);
  assert.match(controllerSource, /reportClientError\(/);
  assert.match(controllerSource, /withBusyRetry/);

  assert.match(contentSource, /export function ListViewContent\(/);
  // ListViewLoadError + LoadingState are re-exported from ListViewStates.
  assert.match(contentSource, /export \{ ListViewLoadError, LoadingState \} from '\.\/ListViewStates';/);
  assert.doesNotMatch(
    contentSource,
    /useQuery|useQueryClient|reportClientError|withBusyRetry|deleteList|quickCapture/,
    'ListView content should stay focused on rendering and input plumbing',
  );

  // Sub-component files exist and export correctly.
  const headerSource = fs.readFileSync(path.join(repoRoot, 'app/src/components/list-view/ListViewHeader.tsx'), 'utf8');
  assert.match(headerSource, /export function ListViewHeader\(/, 'ListViewHeader should be a named export in its own file');
  assert.match(headerSource, /formatListPlan/, 'ListViewHeader should use the formatListPlan utility');

  const openTaskListSource = fs.readFileSync(path.join(repoRoot, 'app/src/components/list-view/OpenTaskList.tsx'), 'utf8');
  assert.match(
    openTaskListSource,
    /<InteractiveTaskCard\b/,
    'OpenTaskList should delegate row rendering to InteractiveTaskCard instead of inlining its own reorder button',
  );
  assert.doesNotMatch(
    openTaskListSource,
    /REORDER_BTN_CLASS/,
    'OpenTaskList should no longer carry a local REORDER_BTN_CLASS after delegating the reorder affordance to InteractiveTaskCard',
  );

  const formatSource = fs.readFileSync(path.join(repoRoot, 'app/src/components/list-view/formatListPlan.ts'), 'utf8');
  assert.match(formatSource, /export function formatListPlan\(/, 'formatListPlan should be an exported pure utility');

  assert.match(supportSource, /export interface ListViewProps/);
  assert.match(supportSource, /export function sortOpenTasks\(/);
});
