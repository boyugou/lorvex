import { useCallback, useEffect, useRef } from 'react';
import { useQueryClient } from '@tanstack/react-query';

import { useConfiguredDayContext } from '@/lib/dayContext';
import { useI18n } from '@/lib/i18n';
import { useMounted } from '@/lib/useMounted';
import {
  type TaskDetailControllerState,
  type TaskDetailProps,
} from '../support';
import { useTaskDetailDrafts } from './drafts';
import { useTaskDetailMutations } from './mutations';
import { invalidateTaskDetailWriteQueries } from '@/lib/query/queryKeys';
import { useTaskDetailQueries } from './queries';
import { useTaskDetailControllerState } from './state';

export function useTaskDetailController({
  taskId,
  onClose,
  onSelectTask,
  isMobile = false,
  flushDraftsRef,
}: TaskDetailProps): TaskDetailControllerState {
  const qc = useQueryClient();
  const { t, format, locale } = useI18n();
  const dayContext = useConfiguredDayContext();
  const persistDraftsRef = useRef<() => Promise<boolean>>(async () => true);
  const mountedRef = useMounted();

  const {
    attribution,
    blocksIds,
    dependsOnIds,
    depTaskMap,
    error,
    isLoading,
    refetchTask,
    task,
  } = useTaskDetailQueries(taskId);

  const invalidateAll = useCallback((options?: { extraListIds?: string[] }) => {
    if (!task) return;
    invalidateTaskDetailWriteQueries(qc, task, options);
  }, [qc, task]);

  const drafts = useTaskDetailDrafts({
    invalidateAll,
    mountedRef,
    task,
    taskId,
    t,
  });
  persistDraftsRef.current = drafts.persistDrafts;

  const mutations = useTaskDetailMutations({
    invalidateAll,
    mountedRef,
    onClose,
    persistDraftsRef,
    task,
    t,
    format,
  });

  const handleClose = useCallback(async () => {
    const ok = await persistDraftsRef.current();
    if (!ok) return;
    onClose();
  }, [onClose]);

  // Expose persistDrafts to the parent so any close path the parent owns
  // (SlidePanel scrim/Esc, X button outside the controller, ErrorBoundary
  // fallback) can flush drafts before tearing the panel down. Without this,
  // those paths called setSelectedTaskId(null) directly and silently dropped
  // unsaved title/body/meta edits — even when the underlying save failed
  // (UX bug U5).
  useEffect(() => {
    if (!flushDraftsRef) return;
    flushDraftsRef.current = () => persistDraftsRef.current();
    return () => {
      flushDraftsRef.current = null;
    };
  }, [flushDraftsRef]);

  // Safety-net flush: if the controller unmounts without the parent
  // invoking the registered `flushDraftsRef` (e.g. a parent route swap
  // tears the panel out without an explicit close), call persistDrafts
  // directly so the most recent debounced title/body/meta edit lands.
  // Idempotent with the explicit close path — persistDrafts skips when
  // the draft state matches the saved task.
  useEffect(() => {
    return () => {
      void persistDraftsRef.current();
    };
  }, []);

  const handleDefer = useCallback(async (untilDate: string | null) => {
    await mutations.handleDefer(untilDate);
  }, [mutations]);
  return useTaskDetailControllerState({
    attribution,
    blocksIds,
    dayContext,
    dependsOnIds,
    depTaskMap,
    drafts,
    error,
    handleClose,
    handleDefer,
    isLoading,
    isMobile,
    locale,
    mutations,
    onSelectTask,
    refetchTask,
    t,
    task,
    taskId,
  });
}
