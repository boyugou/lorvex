import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

test('task picker overlays delegate task update mutations to a shared action hook', () => {
  const durationOverlaySource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/ui/DurationPickerOverlay.tsx'),
    'utf8',
  );
  const recurrenceOverlaySource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/ui/RecurrencePickerOverlay.tsx'),
    'utf8',
  );
  const dueDateOverlaySource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/ui/DueDatePickerOverlay.tsx'),
    'utf8',
  );
  const listPickerOverlaySource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/ui/ListPickerOverlay.tsx'),
    'utf8',
  );
  const sharedMutationSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/ui/useTaskPickerMutation.ts'),
    'utf8',
  );

  for (const source of [
    durationOverlaySource,
    recurrenceOverlaySource,
    dueDateOverlaySource,
    listPickerOverlaySource,
  ]) {
    assert.match(
      source,
      /import \{ useTaskPickerMutation \} from '\.\/useTaskPickerMutation';/,
      'task picker overlays should import the shared mutation hook',
    );
    assert.doesNotMatch(
      source,
      /useQueryClient|updateTask\(|invalidateTaskMutationQueries|reportClientError|toast\./,
      'task picker overlays should stay focused on picker UI instead of owning transport and mutation wiring',
    );
  }

  assert.match(sharedMutationSource, /export function useTaskPickerMutation\(/);
  assert.match(sharedMutationSource, /updateTask\(/);
  assert.match(sharedMutationSource, /invalidateTaskMutationQueries\(/);
  assert.match(sharedMutationSource, /reportClientError\(/);
});
