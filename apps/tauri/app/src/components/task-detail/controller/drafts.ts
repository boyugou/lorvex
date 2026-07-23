import { useCallback, useEffect, useRef, useState, type KeyboardEvent as ReactKeyboardEvent, type RefObject } from 'react';

import { isImeComposingEvent } from '@/lib/ime';
import type { Task } from '@/lib/ipc/tasks/models';
import { updateTask } from '@/lib/ipc/tasks/mutations/quickCapture';
import { toast } from '@/lib/notifications/toast';
import type { TranslationKey } from '@/lib/i18n';
import { showUndoOnlyToast } from '@/lib/tasks/lifecycleUndoRedo';
import { reportTaskDetailActionError } from '../support';
import { reconcileTaskDraftField, shouldPersistTaskDetailDrafts } from './drafts.logic';

interface UseTaskDetailDraftsArgs {
  invalidateAll: (options?: { extraListIds?: string[] }) => void;
  mountedRef: RefObject<boolean>;
  task: Task | null;
  taskId: string;
  t: (key: TranslationKey) => string;
}

export function useTaskDetailDrafts({
  invalidateAll,
  mountedRef,
  task,
  taskId,
  t,
}: UseTaskDetailDraftsArgs): {
  bodyDraft: string;
  bodyDirty: boolean;
  handleBodyDraftChange: (next: string) => void;
  handleBodyDirtyChange: (next: boolean) => void;
  handleTitleBlur: () => void;
  handleTitleChange: (value: string) => void;
  handleTitleCompositionEnd: () => void;
  handleTitleCompositionStart: () => void;
  handleTitleKeyDown: (event: ReactKeyboardEvent<HTMLInputElement>) => void;
  persistBody: (draft?: string) => Promise<boolean>;
  persistDrafts: () => Promise<boolean>;
  savingBody: boolean;
  savingTitle: boolean;
  titleComposing: boolean;
  titleDraft: string;
  titleDirty: boolean;
} {
  const [titleDraft, setTitleDraft] = useState('');
  const [bodyDraft, setBodyDraft] = useState('');
  const [titleDirty, setTitleDirty] = useState(false);
  const [bodyDirty, setBodyDirty] = useState(false);
  const [savingTitle, setSavingTitle] = useState(false);
  const [savingBody, setSavingBody] = useState(false);
  const [titleComposing, setTitleComposing] = useState(false);

  // Keep a stable ref to persistDrafts so the taskId-change effect can flush
  // pending edits for the PREVIOUS task before switching.
  const persistDraftsRef = useRef<() => Promise<boolean>>(async () => true);

  // race 1: `titleDirty` / `bodyDirty` are React state and
  // therefore see values from the last committed render. Between a
  // keystroke handler calling `setTitleDirty(true)` and React's commit,
  // a peer-window `data-changed` event can trigger a query refetch, the
  // `task` prop identity changes, this effect fires, and `titleDirty`
  // reads as `false` — clobbering in-flight user edits.
  //
  // Fix: mirror the dirty flags in refs that are mutated synchronously
  // in the change handlers. Effects read the ref, not the state.
  //
  // A second race arises right after a successful persist: we call
  // `invalidateAll()` (schedules a refetch) *before* flipping
  // `titleDirty` back to false. The refetch may not have landed yet, so
  // an effect run between those two state updates would read the stale
  // pre-update `task.title` and overwrite the correct fresh draft. The
  // `skipSyncForValue` refs suppress exactly one sync-down pass whose
  // incoming `task` field still matches the pre-persist snapshot.
  const titleDirtyRef = useRef(false);
  const bodyDirtyRef = useRef(false);
  const titleDraftRef = useRef(titleDraft);
  titleDraftRef.current = titleDraft;
  const bodyDraftRef = useRef(bodyDraft);
  bodyDraftRef.current = bodyDraft;
  const skipTitleSyncForValueRef = useRef<string | null>(null);
  const skipBodySyncForValueRef = useRef<string | null>(null);

  useEffect(() => {
    titleDirtyRef.current = false;
    bodyDirtyRef.current = false;
    skipTitleSyncForValueRef.current = null;
    skipBodySyncForValueRef.current = null;
    setTitleDirty(false);
    setBodyDirty(false);
  }, [taskId]);

  useEffect(() => {
    if (!task) return;
    if (!titleDirtyRef.current) {
      const result = reconcileTaskDraftField({
        dirty: false,
        currentDraft: titleDraft,
        incomingValue: task.title,
        skipValue: skipTitleSyncForValueRef.current,
      });
      skipTitleSyncForValueRef.current = result.nextSkipValue;
      if (result.shouldUpdateDraft) {
        setTitleDraft(result.nextDraft);
      }
    }
    if (!bodyDirtyRef.current) {
      const result = reconcileTaskDraftField({
        dirty: false,
        currentDraft: bodyDraft,
        incomingValue: task.body ?? '',
        skipValue: skipBodySyncForValueRef.current,
      });
      skipBodySyncForValueRef.current = result.nextSkipValue;
      if (result.shouldUpdateDraft) {
        setBodyDraft(result.nextDraft);
      }
    }
  }, [bodyDraft, task, titleDraft]);

  const persistTitle = useCallback(async (): Promise<boolean> => {
    if (!task) return true;
    const trimmed = titleDraftRef.current.trim();
    if (!trimmed) {
      if (mountedRef.current) {
        titleDirtyRef.current = false;
        setTitleDraft(task.title);
        setTitleDirty(false);
      }
      return true;
    }
    if (trimmed !== task.title) {
      if (mountedRef.current) {
        setSavingTitle(true);
      }
      try {
        const result = await updateTask(task.id, { title: trimmed });
        // Suppress the one sync-down pass that will fire with the stale
        // pre-update `task.title` (before the refetch lands). Once the
        // refetch returns the new value, skip is cleared and sync
        // resumes.
        skipTitleSyncForValueRef.current = task.title;
        titleDirtyRef.current = false;
        // Skip cache invalidation during unmount to avoid stale flicker
        if (mountedRef.current) invalidateAll();
        if (mountedRef.current) {
          setTitleDirty(false);
          showUndoOnlyToast(t('task.updated'), result.undo_token, {
            invalidate: () => invalidateAll(),
            t,
            errorKeyPrefix: 'taskDetail.rename',
          });
        }
        return true;
      } catch (taskError) {
        reportTaskDetailActionError('save-title', taskError, task.id);
        toast.errorWithDetail(taskError, t('common.error'));
        return false;
      } finally {
        if (mountedRef.current) {
          setSavingTitle(false);
        }
      }
    }
    if (mountedRef.current) {
      titleDirtyRef.current = false;
      setTitleDirty(false);
    }
    return true;
  }, [invalidateAll, mountedRef, t, task]);

  const persistBody = useCallback(async (draft?: string): Promise<boolean> => {
    if (!task) return true;
    const latestDraft = draft ?? bodyDraftRef.current;
    const next = latestDraft.trim().length > 0 ? latestDraft : null;
    const current = task.body ?? null;
    if (next === current) {
      if (mountedRef.current) {
        bodyDirtyRef.current = false;
        setBodyDirty(false);
      }
      return true;
    }
    if (mountedRef.current) {
      setSavingBody(true);
    }
    try {
      // surface Undo on body edits so a mis-paste can
      // be recovered within the 5s hold window.
      const result = await updateTask(task.id, { body: next });
      // Suppress one sync-down pass with the stale pre-update body.
      skipBodySyncForValueRef.current = current;
      bodyDirtyRef.current = false;
      // Skip cache invalidation during unmount to avoid stale flicker
      if (mountedRef.current) invalidateAll();
      if (mountedRef.current) {
        setBodyDirty(false);
        showUndoOnlyToast(t('task.updated'), result.undo_token, {
          invalidate: () => invalidateAll(),
          t,
          errorKeyPrefix: 'taskDetail.body',
        });
      }
      return true;
    } catch (taskError) {
      reportTaskDetailActionError('save-notes', taskError, task.id);
      toast.errorWithDetail(taskError, t('common.error'));
      return false;
    } finally {
      if (mountedRef.current) {
        setSavingBody(false);
      }
    }
  }, [invalidateAll, mountedRef, t, task]);

  const persistDrafts = useCallback(async (): Promise<boolean> => {
    if (!shouldPersistTaskDetailDrafts({
      bodyDirty: bodyDirtyRef.current,
      titleDirty: titleDirtyRef.current,
    })) {
      return true;
    }
    if (titleDirtyRef.current) {
      const ok = await persistTitle();
      if (!ok) return false;
    }
    if (bodyDirtyRef.current) {
      const ok = await persistBody();
      if (!ok) return false;
    }
    return true;
  }, [persistBody, persistTitle]);

  // Flush pending drafts for the PREVIOUS task when taskId changes.
  // The cleanup runs before the ref-update effect below, so
  // persistDraftsRef.current still points to the version that closes over the
  // old task / old dirty drafts — exactly what we need.
  useEffect(() => {
    return () => {
      void persistDraftsRef.current();
    };
  }, [taskId]);

  // Update the stable ref in an effect (not during render) so that the
  // cleanup above always sees the PREVIOUS render's persistDrafts.
  useEffect(() => {
    persistDraftsRef.current = persistDrafts;
  });

  // Stable handler refs to avoid recreating on every render
  const handleBodyDraftChange = useCallback((next: string) => {
    bodyDraftRef.current = next;
    setBodyDraft(next);
  }, []);

  const handleBodyDirtyChange = useCallback((next: boolean) => {
    // Sync ref first so the sync-down effect observes the change even
    // if it fires between this call and React's state commit. See
    // race 1.
    bodyDirtyRef.current = next;
    setBodyDirty(next);
  }, []);

  const persistTitleRef = useRef(persistTitle);
  persistTitleRef.current = persistTitle;
  const handleTitleBlur = useCallback(() => {
    void persistTitleRef.current();
  }, []);

  const handleTitleChange = useCallback((value: string) => {
    // Sync ref first — see race 1.
    titleDirtyRef.current = true;
    titleDraftRef.current = value;
    setTitleDraft(value);
    setTitleDirty(true);
  }, []);

  const handleTitleCompositionEnd = useCallback(() => {
    setTitleComposing(false);
  }, []);

  const handleTitleCompositionStart = useCallback(() => {
    setTitleComposing(true);
  }, []);

  const titleComposingRef = useRef(titleComposing);
  titleComposingRef.current = titleComposing;
  const handleTitleKeyDown = useCallback((event: ReactKeyboardEvent<HTMLInputElement>) => {
    if (
      titleComposingRef.current
      || isImeComposingEvent(event.nativeEvent as KeyboardEvent & { keyCode?: number; which?: number })
    ) {
      return;
    }
    if (event.key === 'Enter') {
      event.preventDefault();
      event.currentTarget.blur();
    }
  }, []);

  return {
    bodyDraft,
    bodyDirty,
    handleBodyDraftChange,
    handleBodyDirtyChange,
    handleTitleBlur,
    handleTitleChange,
    handleTitleCompositionEnd,
    handleTitleCompositionStart,
    handleTitleKeyDown,
    persistBody,
    persistDrafts,
    savingBody,
    savingTitle,
    titleComposing,
    titleDraft,
    titleDirty,
  };
}

export type TaskDetailDraftState = ReturnType<typeof useTaskDetailDrafts>;
