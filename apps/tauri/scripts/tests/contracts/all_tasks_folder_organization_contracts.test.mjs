import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { readTypeScriptSources, repoRoot } from './shared.mjs';

test('AllTasksView is organized as a folder-backed subsystem with controller and task-group modules', () => {
  const rootSource = fs.readFileSync(path.join(repoRoot, 'app/src/components/AllTasksView.tsx'), 'utf8');
  const controllerRootSource = fs.readFileSync(path.join(repoRoot, 'app/src/components/all-tasks/useAllTasksController.ts'), 'utf8');
  const controllerSource = readTypeScriptSources('app/src/components/all-tasks/useAllTasksController.ts', 'app/src/components/all-tasks/controller');
  const virtualSectionHeaderSource = fs.readFileSync(path.join(repoRoot, 'app/src/components/all-tasks/VirtualSectionHeader.tsx'), 'utf8');
  const typesSource = fs.readFileSync(path.join(repoRoot, 'app/src/components/all-tasks/types.ts'), 'utf8');

  assert.match(
    rootSource,
    /useAllTasksController\(/,
    'AllTasksView root should compose the dedicated all-tasks controller',
  );
  assert.match(
    rootSource,
    /VirtualSectionHeader|InteractiveTaskCard/,
    'AllTasksView root should delegate rendering to virtualised section/task components',
  );
  assert.match(
    controllerRootSource,
    /export function useAllTasksController\(/,
    'all-tasks controller module should own view state and mutation workflows',
  );
  assert.match(
    controllerSource,
    /const \[targetListId, setTargetListId\] = useState<string \| null>\(null\);/,
    'all-tasks controller should keep null as the canonical missing target-list sentinel',
  );
  assert.match(
    controllerSource,
    /const setSelectionModeEnabled = \(enabled: boolean\) => \{\s*base\.setSelectionModeEnabled\(enabled\);\s*if \(!enabled\) setTargetListId\(null\);\s*};/s,
    'all-tasks selection wrapper should clear its target-list state while delegating generic selection reset to the shared hook',
  );
  assert.match(
    controllerRootSource,
    /useAllTasksSelection\(visibleTaskIds,\s*bulkAction\)/,
    'all-tasks controller root should compose selection state from the dedicated controller subtree',
  );
  assert.ok(
    fs.existsSync(path.join(repoRoot, 'app/src/components/all-tasks/controller/selection.ts')),
    'all-tasks controller subtree should own selection-state management',
  );
  assert.match(
    controllerRootSource,
    /import \{ useDebounced \} from ['"](?:@\/lib\/useDebounced|\.\.\/\.\.\/lib\/useDebounced)['"];/,
    'all-tasks controller should import the canonical debounced helper from the shared lib',
  );
  assert.match(
    rootSource,
    /type VirtualRow = VirtualSectionHeaderRow \| VirtualTaskRow \| VirtualSectionGapRow;/,
    'AllTasksView should keep explicit virtual row payload types for section-aware rendering',
  );
  assert.match(
    rootSource,
    /useVirtualizedTaskRows\(/,
    'AllTasksView should delegate row virtualization to the shared section-aware virtualizer',
  );
  assert.match(
    virtualSectionHeaderSource,
    /export const VirtualSectionHeader = memo/,
    'VirtualSectionHeader module should own memoized grouped-section header rendering',
  );
  assert.match(
    typesSource,
    /SortKey/,
    'types module should own or re-export shared all-tasks sorting vocabulary',
  );
});
