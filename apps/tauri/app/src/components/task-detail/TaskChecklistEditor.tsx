import { useEffect, useMemo, useRef, useState } from 'react';
import type { TaskChecklistItem } from '@/lib/ipc/tasks/models';
import { addTaskChecklistItem, removeTaskChecklistItem, reorderTaskChecklistItems, setTaskChecklistItemCompleted, updateTaskChecklistItemText } from '@/lib/ipc/tasks/mutations/checklist';
import { useI18n } from '@/lib/i18n';
import { isImeComposing } from '@/lib/ime';
import { toast } from '@/lib/notifications/toast';
import {
  buildChecklistProgressLabel,
  reconcileChecklistItemDraft,
} from './TaskChecklistEditor.logic';

interface TaskChecklistEditorProps {
  taskId: string;
  items: TaskChecklistItem[] | null;
  refetchTask: () => Promise<unknown>;
}

export default function TaskChecklistEditor({
  taskId,
  items,
  refetchTask,
}: TaskChecklistEditorProps) {
  const { t, locale } = useI18n();
  const checklistItems = useMemo(() => items ?? [], [items]);
  const [newItemText, setNewItemText] = useState('');
  const progressLabel = useMemo(() => {
    const completed = checklistItems.filter((item) => item.completed_at).length;
    return buildChecklistProgressLabel(locale, completed, checklistItems.length);
  }, [checklistItems, locale]);

  const reload = async () => {
    await refetchTask();
  };

  const handleAdd = async () => {
    const trimmed = newItemText.trim();
    if (!trimmed) {
      return;
    }
    try {
      await addTaskChecklistItem(taskId, trimmed);
      setNewItemText('');
      await reload();
    } catch (error) {
      toast.errorWithDetail(error, t('task.checklistAddError'));
    }
  };

  const handleToggle = async (item: TaskChecklistItem, completed: boolean) => {
    try {
      await setTaskChecklistItemCompleted(taskId, item.id, completed);
      await reload();
    } catch (error) {
      toast.errorWithDetail(error, t('task.checklistUpdateError'));
    }
  };

  const handleTextCommit = async (item: TaskChecklistItem, nextText: string) => {
    const trimmed = nextText.trim();
    if (!trimmed || trimmed === item.text) {
      return;
    }
    try {
      await updateTaskChecklistItemText(taskId, item.id, trimmed);
      await reload();
    } catch (error) {
      toast.errorWithDetail(error, t('task.checklistRenameError'));
    }
  };

  const handleRemove = async (item: TaskChecklistItem) => {
    try {
      await removeTaskChecklistItem(taskId, item.id);
      await reload();
    } catch (error) {
      toast.errorWithDetail(error, t('task.checklistRemoveError'));
    }
  };

  const handleMove = async (item: TaskChecklistItem, delta: -1 | 1) => {
    const currentIndex = checklistItems.findIndex((entry) => entry.id === item.id);
    const targetIndex = currentIndex + delta;
    if (currentIndex < 0 || targetIndex < 0 || targetIndex >= checklistItems.length) {
      return;
    }
    const next = [...checklistItems];
    const [moved] = next.splice(currentIndex, 1);
    if (!moved) {
      return;
    }
    next.splice(targetIndex, 0, moved);
    try {
      await reorderTaskChecklistItems(
        taskId,
        next.map((entry) => entry.id),
      );
      await reload();
    } catch (error) {
      toast.errorWithDetail(error, t('task.checklistReorderError'));
    }
  };

  return (
    <section className="flex flex-col gap-2">
      <div className="flex items-center justify-between">
        <span className="text-text-muted/60 text-2xs font-medium uppercase tracking-wide">
          {t('task.checklist')}
        </span>
        {progressLabel ? (
          <span className="text-xs text-text-muted/70 tabular-nums">{progressLabel}</span>
        ) : null}
      </div>

      {checklistItems.length > 0 ? (
        <div className="flex flex-col gap-2">
          {checklistItems.map((item, index) => (
            <ChecklistRow
              key={item.id}
              item={item}
              isFirst={index === 0}
              isLast={index === checklistItems.length - 1}
              onCommit={handleTextCommit}
              onMove={handleMove}
              onRemove={handleRemove}
              onToggle={handleToggle}
            />
          ))}
        </div>
      ) : (
        <div className="text-sm text-text-muted/60 rounded-r-control border border-dashed border-card px-3 py-2">
          {t('task.checklistEmpty')}
        </div>
      )}

      <div className="flex items-center gap-2">
        <input
          value={newItemText}
          onChange={(event) => setNewItemText(event.target.value)}
          onKeyDown={(event) => {
            if (event.key === 'Enter' && !isImeComposing(event)) {
              event.preventDefault();
              void handleAdd();
            }
          }}
          placeholder={t('task.checklistPlaceholder')}
          aria-label={t('task.checklistPlaceholder')}
          className="flex-1 rounded-r-control border border-card bg-surface-2/50 px-3 py-2 text-sm outline-hidden focus-ring-soft"
        />
        <button
          type="button"
          onClick={() => {
            void handleAdd();
          }}
          className="rounded-r-control border border-card px-3 py-2 text-sm text-text-secondary hover:bg-surface-2/60"
        >
          {t('common.add')}
        </button>
      </div>
    </section>
  );
}

function ChecklistRow({
  item,
  isFirst,
  isLast,
  onCommit,
  onMove,
  onRemove,
  onToggle,
}: {
  item: TaskChecklistItem;
  isFirst: boolean;
  isLast: boolean;
  onCommit: (item: TaskChecklistItem, nextText: string) => Promise<void>;
  onMove: (item: TaskChecklistItem, delta: -1 | 1) => Promise<void>;
  onRemove: (item: TaskChecklistItem) => Promise<void>;
  onToggle: (item: TaskChecklistItem, completed: boolean) => Promise<void>;
}) {
  const { t } = useI18n();
  const [draft, setDraft] = useState(item.text);
  const toggleLabel = `${t('task.checklist')}: ${item.text}`;
  const moveUpLabel = `${t('task.checklistMoveUp')}: ${item.text}`;
  const moveDownLabel = `${t('task.checklistMoveDown')}: ${item.text}`;
  const removeLabel = `${t('common.remove')}: ${item.text}`;
  // mirrors the draft-sync guard in controller/drafts.ts
  //. Without it, a peer or MCP edit to the same
  // checklist item lands a refetch while the user is typing and the
  // effect silently overwrites the in-flight keystrokes.
  const draftDirtyRef = useRef(false);
  const skipSyncForValueRef = useRef<string | null>(null);

  useEffect(() => {
    const reconciled = reconcileChecklistItemDraft({
      dirty: draftDirtyRef.current,
      currentDraft: draft,
      incomingValue: item.text,
      skipValue: skipSyncForValueRef.current,
    });
    skipSyncForValueRef.current = reconciled.nextSkipValue;
    if (reconciled.shouldUpdateDraft) {
      setDraft(reconciled.nextDraft);
    }
    // `draft` is intentionally read from closure rather than declared as a
    // dependency: re-running the reconciler on every keystroke would defeat
    // the dirty-guard above and silently overwrite in-flight edits when the
    // incoming `item.text` matches the freshly-typed value. Mirrors the
    // controller pattern in `controller/drafts.ts`.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [item.text]);

  return (
    <div className="flex items-center gap-2 rounded-r-control border border-card bg-surface-2/30 px-2.5 py-2">
      <input
        type="checkbox"
        checked={Boolean(item.completed_at)}
        onChange={(event) => {
          void onToggle(item, event.target.checked);
        }}
        aria-label={toggleLabel}
        className="h-4 min-h-6 w-4 min-w-6 rounded-r-control border-card"
      />
      <input
        value={draft}
        aria-label={t('task.checklistItemLabel')}
        onChange={(event) => {
          draftDirtyRef.current = true;
          setDraft(event.target.value);
        }}
        onBlur={() => {
          // Mark the committed value as the "expected next item.text"
          // so the post-mutation refetch doesn't trigger a re-render
          // that overwrites the draft.
          skipSyncForValueRef.current = draft;
          draftDirtyRef.current = false;
          void onCommit(item, draft);
        }}
        onKeyDown={(event) => {
          if (event.key === 'Enter' && !isImeComposing(event)) {
            event.preventDefault();
            skipSyncForValueRef.current = draft;
            draftDirtyRef.current = false;
            void onCommit(item, draft);
          }
        }}
        className={`flex-1 bg-transparent text-sm outline-hidden rounded-r-control focus-ring-soft ${
          item.completed_at ? 'line-through text-text-muted' : 'text-text-primary'
        }`}
      />
      <div className="flex items-center gap-1">
        <button
          type="button"
          onClick={() => {
            void onMove(item, -1);
          }}
          disabled={isFirst}
          aria-label={moveUpLabel}
          className="inline-flex min-h-6 min-w-6 items-center justify-center rounded-r-control px-1.5 py-0.5 text-xs text-text-muted enabled:hover:bg-surface-3/50 disabled:opacity-30 focus-ring-soft"
        >
          ↑
        </button>
        <button
          type="button"
          onClick={() => {
            void onMove(item, 1);
          }}
          disabled={isLast}
          aria-label={moveDownLabel}
          className="inline-flex min-h-6 min-w-6 items-center justify-center rounded-r-control px-1.5 py-0.5 text-xs text-text-muted enabled:hover:bg-surface-3/50 disabled:opacity-30 focus-ring-soft"
        >
          ↓
        </button>
        <button
          type="button"
          onClick={() => {
            void onRemove(item);
          }}
          aria-label={removeLabel}
          className="inline-flex min-h-6 min-w-6 items-center justify-center rounded-r-control px-1.5 py-0.5 text-xs text-danger hover:bg-[var(--danger-tint-sm)] focus-ring-soft"
        >
          {t('common.remove')}
        </button>
      </div>
    </div>
  );
}
