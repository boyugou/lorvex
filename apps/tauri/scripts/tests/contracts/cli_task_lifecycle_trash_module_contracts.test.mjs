import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { hasRustUseReexport, repoRoot } from './shared.mjs';

const ROOT = 'lorvex-cli/src/commands/mutate/tasks/lifecycle_effects/mod.rs';
const TRASH_ROOT = 'lorvex-cli/src/commands/mutate/tasks/lifecycle_effects/trash/mod.rs';
const TRASH_ARCHIVE = 'lorvex-cli/src/commands/mutate/tasks/lifecycle_effects/trash/archive.rs';
const TRASH_RESTORE = 'lorvex-cli/src/commands/mutate/tasks/lifecycle_effects/trash/restore.rs';
const TRASH_PERMANENT_DELETE = 'lorvex-cli/src/commands/mutate/tasks/lifecycle_effects/trash/permanent_delete.rs';
const TRASH_FOCUS_DATES = 'lorvex-cli/src/commands/mutate/tasks/lifecycle_effects/trash/focus_dates.rs';

function read(relativePath) {
  return fs.readFileSync(path.join(repoRoot, relativePath), 'utf8');
}

test('CLI task lifecycle delegates Trash operations to a dedicated module', () => {
  const rootSource = read(ROOT);
  const trashRootSource = read(TRASH_ROOT);

  assert.match(rootSource, /^mod trash;$/m, 'task_lifecycle root should register the trash module');
  assert.ok(
    hasRustUseReexport(rootSource, {
      modulePath: 'trash',
      symbols: [
        'archive_task_in_tx',
        'permanent_delete_task_in_tx',
        'restore_task_from_trash_in_tx',
        'PermanentDeleteTaskResult',
      ],
      visibility: 'pub(crate)',
    }),
    'task_lifecycle root should re-export production Trash operations from the trash module',
  );
  assert.ok(
    hasRustUseReexport(rootSource, {
      modulePath: 'trash',
      symbols: [
        'archive_task_with_conn',
        'permanent_delete_task_with_conn',
        'restore_task_from_trash_with_conn',
      ],
      visibility: 'pub(crate)',
    }),
    'task_lifecycle root should keep test-only Trash wrappers reachable from the trash module',
  );
  assert.ok(
    rootSource.split('\n').length <= 760,
    'task_lifecycle root should shrink after extracting Trash operations',
  );
  assert.doesNotMatch(
    rootSource,
    /\npub\(crate\) fn (?:archive_task|restore_task_from_trash|permanent_delete_task)_(?:with_conn|in_tx)\b/,
    'task_lifecycle root should not keep Trash operation implementations inline',
  );

  // trash/mod.rs should be a thin facade that re-exports production + test-only helpers
  // from per-concern siblings.
  for (const subModule of ['archive', 'restore', 'permanent_delete', 'focus_dates']) {
    assert.match(
      trashRootSource,
      new RegExp(`\\nmod ${subModule};`),
      `trash/mod.rs should register the ${subModule} sibling`,
    );
  }

  // Each function must live in the sibling that owns it.
  const ownership = {
    archive_task_in_tx: TRASH_ARCHIVE,
    restore_task_from_trash_in_tx: TRASH_RESTORE,
    permanent_delete_task_in_tx: TRASH_PERMANENT_DELETE,
    collect_focus_parent_dates_for_task: TRASH_FOCUS_DATES,
    enqueue_archive_focus_parent_upserts: TRASH_ARCHIVE,
  };
  for (const [functionName, ownerFile] of Object.entries(ownership)) {
    const ownerSource = read(ownerFile);
    assert.match(
      ownerSource,
      new RegExp(`\\n(?:pub\\((?:crate|super|in [^)]+)\\) )?fn ${functionName}\\b`),
      `${ownerFile} should own ${functionName}`,
    );
  }
});
