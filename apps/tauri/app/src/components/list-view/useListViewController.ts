import { useEffect, useMemo, useRef, useState } from 'react';
import { useMounted } from '@/lib/useMounted';
import { keepPreviousData, useQuery, useQueryClient } from '@tanstack/react-query';

import { confirm } from '@/lib/dialogs/confirm';
import { reportClientError } from '@/lib/errors/errorLogging';
import { useSnapshotUndoToast } from '@/lib/hooks/useSnapshotUndoToast';
import { useI18n } from '@/lib/i18n';
import { deleteList, getListWithTasks, updateList } from '@/lib/ipc/tasks/lists';
import { quickCapture } from '@/lib/ipc/tasks/mutations/quickCapture';
import { parseTags } from '@/lib/format';
import { sortTasks } from '@/lib/tasks/taskSorting';
import { useTaskFilters } from '@/lib/tasks/useTaskFilters';
import { useTaskSortState } from '@/lib/tasks/useTaskSortState';
import type { PriorityFilterValue } from '@/lib/tasks/priorityFilter';
import { QUERY_KEYS, invalidateListContextTaskWriteQueries, invalidateTaskCollectionQueries, invalidateTodaySurfaceQueries } from '@/lib/query/queryKeys';
import { withBusyRetry } from '@/lib/recovery/sqliteRetry';
import { toast } from '@/lib/notifications/toast';
import type { QueryClient } from '@tanstack/react-query';

import { evictDeletedListFromCache } from './deleteCache';
import { isListNotFoundError } from './listError';
import { sortOpenTasks } from './support';
import { TASK_STATUS } from '@lorvex/shared/types';

export function useListViewController({
  listId,
  initialRename = false,
  onListDeleted,
}: { listId: string; initialRename?: boolean | undefined; onListDeleted?: (() => void) | undefined }) {
  const { t } = useI18n();
  const qc = useQueryClient();
  const showSnapshotUndoToast = useSnapshotUndoToast();
  const [search, setSearch] = useState('');
  const [draft, setDraft] = useState('');
  const [adding, setAdding] = useState(false);
  const [deleting, setDeleting] = useState(false);
  const [deletionFinalized, setDeletionFinalized] = useState(false);
  const [renaming, setRenaming] = useState(initialRename);
  const [renameSaving, setRenameSaving] = useState(false);
  const { sortKey, setSortKey, sortDirection, toggleSortDirection } = useTaskSortState();
  const [filterPriority, setFilterPriority] = useState<PriorityFilterValue>(null);
  const inputRef = useRef<HTMLInputElement>(null);
  const listViewMountedRef = useMounted();

  const { data, isLoading, error, refetch } = useQuery({
    queryKey: QUERY_KEYS.list(listId),
    queryFn: ({ signal }) => getListWithTasks(listId, signal),
    enabled: !deleting,
    refetchInterval: deleting ? false : 60_000,
    placeholderData: keepPreviousData,
  });

  useEffect(() => {
    if (!error || !onListDeleted) return;
    if (isListNotFoundError(error)) {
      onListDeleted();
    }
  }, [error, onListDeleted]);

  useEffect(() => {
    setDeletionFinalized(false);
  }, [listId]);

  const openTasksForTags = useMemo(
    () => data ? data.tasks.filter((task) => task.status === TASK_STATUS.open) : [],
    [data],
  );
  const { selectedTags, toggleTag, clearTagFilter, allTags } = useTaskFilters(openTasksForTags);

  const searchLower = search.toLowerCase();
  const matchesFilter = (task: { title: string; status: string; priority?: number | null; tags?: string[] | null }) => {
    if (task.status !== TASK_STATUS.open) return false;
    if (searchLower && !task.title.toLowerCase().includes(searchLower)) return false;
    if (filterPriority !== null && task.priority !== filterPriority) return false;
    if (selectedTags.size > 0) {
      const taskTags = parseTags(task.tags ?? null);
      if (!taskTags.some((tag) => selectedTags.has(tag))) return false;
    }
    return true;
  };

  const isFilterActive = !!(searchLower || filterPriority !== null || selectedTags.size > 0);
  const totalOpenCount = data ? data.tasks.filter(task => task.status === TASK_STATUS.open).length : 0;
  const openTasks = data
    ? sortKey === 'default'
      ? sortOpenTasks(data.tasks.filter(matchesFilter))
      : sortTasks(data.tasks.filter(matchesFilter), sortKey, sortDirection)
    : [];
  const completedTasks = data ? data.tasks.filter(task => task.status === TASK_STATUS.completed) : [];

  const handleAdd = async () => {
    const title = draft.trim();
    if (!title || adding) return;

    setAdding(true);
    try {
      await quickCapture({ title, listId });
      invalidateListContextTaskWriteQueries(qc, { listId });
      if (listViewMountedRef.current) {
        setDraft('');
      }
      // inline list add-task was silent; match the
      // audibility of every other write path by acknowledging the save.
      toast.success(t('task.createSuccess'));
    } catch (error) {
      reportClientError('list.addTask', 'Failed to quick capture task into list', error, listId);
      toast.errorWithDetail(error, t('common.error'));
    } finally {
      if (listViewMountedRef.current) {
        setAdding(false);
        inputRef.current?.focus();
      }
    }
  };

  const handleDeleteList = async () => {
    if (!data || deleting) return;

    const ok = await confirm({
      title: t('list.delete'),
      message: t('list.deleteConfirm'),
      variant: 'danger',
    });
    if (!ok) return;

    setDeleting(true);
    try {
      await qc.cancelQueries({ queryKey: QUERY_KEYS.list(listId) });
      const result = await withBusyRetry(() => deleteList(data.list.id));
      if (listViewMountedRef.current) {
        setDeletionFinalized(true);
      }
      evictDeletedListFromCache(qc, result.deleted_list_id);
      invalidateTodaySurfaceQueries(qc);
      invalidateTaskCollectionQueries(qc);
      // surface the snapshot-undo toast so a same-second
      // misclick can be reverted. The "navigate away" step is
      // deferred to `onAfterUndoExpired` — running it eagerly would
      // strand the user on Today even after a successful Undo
      // restored the list to the sidebar. Mirrors the contract used
      // by the sidebar context-menu delete in `useListContextMenu`.
      showSnapshotUndoToast({
        kind: 'list',
        token: result.undo_token,
        successKey: 'list.deleteSuccess',
        restoredKey: 'list.restored',
        invalidate: (client: QueryClient) => {
          void client.invalidateQueries({ queryKey: QUERY_KEYS.lists() });
          invalidateTodaySurfaceQueries(client);
          invalidateTaskCollectionQueries(client);
        },
        onAfterUndoExpired: () => {
          if (listViewMountedRef.current) {
            onListDeleted?.();
          }
        },
      });
    } catch (error) {
      reportClientError('list.delete', 'Failed to delete list', error, listId);
      if (isListNotFoundError(error)) {
        if (listViewMountedRef.current) {
          setDeletionFinalized(true);
        }
        evictDeletedListFromCache(qc, data.list.id);
        invalidateTodaySurfaceQueries(qc);
        toast.success(t('list.deleteSuccess'));
        if (listViewMountedRef.current) {
          onListDeleted?.();
        }
        return;
      }
      // `errorWithDetail` filters backend-internal
      // strings (PoisonError, JNI, absolute paths, etc.) before
      // concatenating with a localized prefix, so a Chinese user no
      // longer sees English Rust internals in the toast.
      toast.errorWithDetail(error, t('list.deleteFailed'));
    } finally {
      if (listViewMountedRef.current) {
        setDeleting(false);
      }
    }
  };

  const handleRename = async (newName: string) => {
    const trimmed = newName.trim();
    if (!trimmed || !data || renameSaving) {
      setRenaming(false);
      return;
    }
    if (trimmed === data.list.name) {
      setRenaming(false);
      return;
    }
    setRenameSaving(true);
    try {
      await updateList({ id: listId, name: trimmed });
      invalidateListContextTaskWriteQueries(qc, { listId });
    } catch (error) {
      reportClientError('list.rename', 'Failed to rename list', error, listId);
      toast.errorWithDetail(error, t('common.error'));
    } finally {
      if (listViewMountedRef.current) {
        setRenameSaving(false);
        setRenaming(false);
      }
    }
  };

  return {
    adding,
    allTags,
    clearTagFilter,
    completedTasks,
    isFilterActive,
    data,
    deleting,
    deletionFinalized,
    draft,
    error,
    filterPriority,
    handleAdd,
    handleDeleteList,
    handleRename,
    inputRef,
    isLoading,
    openTasks,
    refetch,
    renameSaving,
    renaming,
    search,
    selectedTags,
    setDraft,
    setFilterPriority,
    setRenaming,
    setSearch,
    setSortKey,
    sortDirection,
    sortKey,
    toggleSortDirection,
    toggleTag,
    totalOpenCount,
  };
}
