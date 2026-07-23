import { useCallback, useMemo } from 'react';

import { parseTags } from '@/lib/format';
import type { TaskDetailControllerState } from '@/components/task-detail/support';
import { TagsField } from '@/components/task-detail/metadata-editor/primitives';

export function TaskDetailInlineTags({
  task,
  controller,
}: {
  task: NonNullable<TaskDetailControllerState['task']>;
  controller: TaskDetailControllerState;
}) {
  // Memoise the parsed `tags` array off the raw serialised string
  // (and pair it with a stable `onSave`) so TagsField's per-tag
  // colour memo sees a stable input reference. Otherwise a fresh
  // `parseTags(task.tags)` per render produces a new array on every
  // keystroke into the add-tag input and re-runs the colour hash
  // for every chip.
  const tags = useMemo(() => parseTags(task.tags), [task.tags]);
  const onSave = useCallback(
    async (newTags: string[]) => {
      await controller.saveMetaPatch({ tags: newTags.length > 0 ? newTags : null });
    },
    [controller],
  );
  return <TagsField tags={tags} t={controller.t} onSave={onSave} />;
}
