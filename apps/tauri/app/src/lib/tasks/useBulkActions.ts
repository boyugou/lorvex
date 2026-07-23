import { type Dispatch, type SetStateAction, useCallback, useMemo, useState } from 'react';
import { useQueryClient } from '@tanstack/react-query';

import type { Task } from '@/lib/ipc/tasks/models';
import { batchCancelTasks, batchCompleteTasks, batchDeferTasks, batchMoveTasks } from '@/lib/ipc/tasks/mutations/batch';
import { addToCurrentFocus } from '@/lib/ipc/tasks/mutations/focus';
import { undoTaskLifecycleBatch } from '@/lib/ipc/tasks/mutations/lifecycle';
import { isTaskActive } from '../format';
import { DEFER_REASON_NOT_TODAY, TASK_STATUS } from '@lorvex/shared/types';
import { confirm } from '../dialogs/confirm';
import { reportClientError } from '../errors/errorLogging';
import { formatTranslation } from '@/locales';
import { useI18n } from '../i18n';
import { useMounted } from '../useMounted';
import { invalidateTaskWorkspaceQueries } from '../query/queryKeys';
import { toast } from '../notifications/toast';
import { consumeUndoToken, makeRecentUndoToken, recordUndoToken, type RecentUndoAction } from '../undoTokenStore';
import {
  formatBulkCancelledMessage,
  formatBulkCompletedMessage,
  formatBulkDeferredMessage,
  formatBulkFocusedMessage,
  formatBulkMovedMessage,
} from '../dates/i18nCountPhrases';
import type { BulkAction } from './useTaskSelection';

/**
 * minimum eligible-task count that triggers an explicit
 * confirm dialog for destructive bulk actions (defer, cancel). Below
 * this threshold the action runs immediately, matching 
 * single/small-batch ergonomics; at-or-above it the user must
 * acknowledge the count before any write hits the backend.
 */
const BULK_CONFIRM_THRESHOLD = 20;

interface UseBulkActionsParams {
  tasks: Task[];
  selectedIds: Set<string>;
  setSelectedIds: (ids: Set<string>) => void;
  deferDateYmd: string;
  /** Fallback list ID for bulk move when no override is passed to handleBulkMove. */
  targetListId?: string | null;
  /**
   * Optional externally-managed bulk action state. When provided, the hook
   * uses these instead of creating its own useState. Useful when the caller
   * needs to share bulkAction with a sibling hook (e.g. selection guard).
   */
  externalBulkAction?: BulkAction;
  externalSetBulkAction?: Dispatch<SetStateAction<BulkAction>>;
}

export function useBulkActions({
  tasks,
  selectedIds,
  setSelectedIds,
  deferDateYmd,
  targetListId,
  externalBulkAction,
  externalSetBulkAction,
}: UseBulkActionsParams) {
  const { locale, t } = useI18n();
  const qc = useQueryClient();
  const [internalBulkAction, internalSetBulkAction] = useState<BulkAction>(null);
  const bulkAction = externalBulkAction !== undefined ? externalBulkAction : internalBulkAction;
  const setBulkAction = externalSetBulkAction ?? internalSetBulkAction;
  const mountedRef = useMounted();

  const selectedTasks = useMemo(() => tasks.filter((tk) => selectedIds.has(tk.id)), [tasks, selectedIds]);
  const selectedCount = selectedIds.size;

  // persist every token the backend issues so a reload,
  // navigation, or Focus Mode dismissal within the 5s undo-hold window
  // does not strand the tokens inside the toast closure. The palette
  // renders a "Recent actions → Undo" group from this store.
  const recordBatchUndoTokens = useCallback(
    (tokens: string[], label: string, action: RecentUndoAction) => {
      const issuedAt = Date.now();
      for (const token of tokens) {
        recordUndoToken(makeRecentUndoToken(token, label, action, issuedAt));
      }
    },
    [],
  );


  const handleBulkComplete = useCallback(async () => {
    if (selectedCount === 0) { toast.info(t('allTasks.bulkNothingSelected')); return; }
    const taskIds = selectedTasks
      .filter((tk) => tk.status !== TASK_STATUS.completed && tk.status !== TASK_STATUS.cancelled)
      .map((tk) => tk.id);
    if (taskIds.length === 0) { toast.info(t('allTasks.bulkNoEligibleComplete')); return; }

    setBulkAction('complete');
    try {
      const result = await batchCompleteTasks(taskIds);
      invalidateTaskWorkspaceQueries(qc);
      if (mountedRef.current) {
        setBulkAction(null);
        setSelectedIds(new Set(result.skipped));
      }

      if (result.completed_count === 0) return;

      const bulkLabel = formatBulkCompletedMessage(locale, result.completed_count, t);
      recordBatchUndoTokens(result.undo_tokens, bulkLabel, 'complete_batch');
      // a coalesced bulk-undo toast represents N actions
      // behind a single token. Scale its visible duration with the
      // magnitude of the operation and mark it `priority` so it can't
      // be evicted by routine chatter while the user is still reading
      // it. Cap at 10s so the toast eventually times out.
      toast.success(
        bulkLabel,
        {
          label: t('common.undo'),
          onClick: async () => {
            try {
              await undoTaskLifecycleBatch(result.undo_tokens);
              for (const tk of result.undo_tokens) consumeUndoToken(tk);
              invalidateTaskWorkspaceQueries(qc);
              if (mountedRef.current) {
                setSelectedIds(new Set());
              }
              toast.info(t('task.undone'));
            } catch (error) {
              reportClientError('bulk.undoComplete', 'Failed to undo complete batch', error, undefined, 'warn');
              invalidateTaskWorkspaceQueries(qc);
              // Route via `errorWithDetail` so the user sees the
              // backend's actionable string ("database is
              // temporarily busy, retry") rather than a bare
              // "Error" word.
              toast.errorWithDetail(error, t('common.error'));
            }
          },
        },
        undefined,
        {
          durationMs: Math.min(4500 + 100 * result.completed_count, 10000),
          priority: true,
        },
      );
    } catch (error) {
      reportClientError('bulk.complete', 'Bulk complete failed', error, undefined, 'warn');
      if (mountedRef.current) {
        setBulkAction(null);
      }
      toast.errorWithDetail(error, t('common.error'));
    }
  }, [locale, qc, mountedRef, selectedCount, selectedTasks, setBulkAction, setSelectedIds, t, recordBatchUndoTokens]);

  const handleBulkDefer = useCallback(async () => {
    if (selectedCount === 0) { toast.info(t('allTasks.bulkNothingSelected')); return; }
    const taskIds = selectedTasks
      .filter((tk) => isTaskActive(tk.status))
      .map((tk) => tk.id);
    if (taskIds.length === 0) { toast.info(t('allTasks.bulkNoEligibleDefer')); return; }
    // destructive bulk action guard. At a 20-task threshold a
    // mistaken bulk-defer corrupts a meaningful chunk of the user's
    // schedule (every selected open task gets a planned-date push and
    // a defer_count bump that is observable in deferral-pressure
    // surfaces forever). Force an explicit confirm so a stray Enter or
    // an off-by-one selection does not commit silently. Bulk-complete
    // is non-destructive (every step has a per-task undo token) so it
    // skips this guard.
    if (taskIds.length >= BULK_CONFIRM_THRESHOLD) {
      const ok = await confirm({
        title: formatTranslation(locale, 'allTasks.bulkConfirmDeferTitle', { count: taskIds.length }),
        message: formatTranslation(locale, 'allTasks.bulkConfirmDeferMessage', { count: taskIds.length }),
        confirmLabel: t('allTasks.bulkConfirmDeferCta'),
        variant: 'danger',
      });
      if (!ok) return;
    }

    // use the existing `batch_defer_tasks` Rust command so
    // 50 selected tasks resolve in one transaction + one sync_outbox
    // batch instead of 50 serial Tauri round-trips.
    //
    // there is an intentional asymmetry here.
    // `batch_complete_tasks` returns `undo_tokens` so we can offer a
    // coalesced "Undo all N completions" affordance, but the defer
    // pathway does not yet emit undo tokens on the Rust side. Wiring
    // defer-undo is a backend change. (this issue)
    // and follow-up; we deliberately do NOT expand the backend
    // surface here to keep this PR focused on the UI-eviction / toast
    // duration fix.
    setBulkAction('defer');
    try {
      const result = await batchDeferTasks(taskIds, deferDateYmd, DEFER_REASON_NOT_TODAY);
      invalidateTaskWorkspaceQueries(qc);
      if (mountedRef.current) {
        setBulkAction(null);
        setSelectedIds(new Set(result.skipped));
      }
      if (result.deferred_count === 0) return;
      toast.success(formatBulkDeferredMessage(locale, result.deferred_count, t));
    } catch (error) {
      reportClientError('bulk.defer', 'Bulk defer failed', error, undefined, 'warn');
      if (mountedRef.current) setBulkAction(null);
      toast.errorWithDetail(error, t('common.error'));
    }
  }, [locale, qc, mountedRef, selectedCount, selectedTasks, setBulkAction, setSelectedIds, deferDateYmd, t]);

  const handleBulkCancel = useCallback(async () => {
    if (selectedCount === 0) { toast.info(t('allTasks.bulkNothingSelected')); return; }
    const eligible = selectedTasks.filter((tk) => tk.status !== TASK_STATUS.cancelled);
    const taskIds = eligible.map((tk) => tk.id);
    if (taskIds.length === 0) { toast.info(t('allTasks.bulkNoEligibleCancel')); return; }
    // guard destructive bulk-cancel above the 20-task threshold.
    // The backend issues per-task undo tokens, but undoing 20+ items
    // one toast at a time is impractical; the explicit confirm covers
    // the common "stray selection" failure mode before the writes hit.
    if (taskIds.length >= BULK_CONFIRM_THRESHOLD) {
      const ok = await confirm({
        title: formatTranslation(locale, 'allTasks.bulkConfirmCancelTitle', { count: taskIds.length }),
        message: formatTranslation(locale, 'allTasks.bulkConfirmCancelMessage', { count: taskIds.length }),
        confirmLabel: t('allTasks.bulkConfirmCancelCta'),
        variant: 'danger',
      });
      if (!ok) return;
    }

    setBulkAction('cancel');
    try {
      const result = await batchCancelTasks(taskIds);
      invalidateTaskWorkspaceQueries(qc);
      if (mountedRef.current) {
        setBulkAction(null);
        setSelectedIds(new Set(result.skipped));
      }

      if (result.cancelled_count === 0) return;

      // `batch_cancel_tasks` now emits one undo token per
      // cancelled task, so we can offer the same coalesced "Undo all N
      // cancellations" affordance as bulk complete. Mirrors the
      // `handleBulkComplete` pattern — if the backend returned no
      // tokens (empty selection / all skipped), fall back to a plain
      // success toast.
      if (result.undo_tokens.length === 0) {
        toast.success(formatBulkCancelledMessage(locale, result.cancelled_count, t));
        return;
      }
      const bulkLabel = formatBulkCancelledMessage(locale, result.cancelled_count, t);
      recordBatchUndoTokens(result.undo_tokens, bulkLabel, 'cancel_batch');
      toast.success(
        bulkLabel,
        {
          label: t('common.undo'),
          onClick: async () => {
            try {
              await undoTaskLifecycleBatch(result.undo_tokens);
              for (const tk of result.undo_tokens) consumeUndoToken(tk);
              invalidateTaskWorkspaceQueries(qc);
              if (mountedRef.current) {
                setSelectedIds(new Set());
              }
              toast.info(t('task.undone'));
            } catch (error) {
              reportClientError('bulk.undoCancel', 'Failed to undo cancel batch', error, undefined, 'warn');
              invalidateTaskWorkspaceQueries(qc);
              toast.errorWithDetail(error, t('common.error'));
            }
          },
        },
        undefined,
        {
          durationMs: Math.min(4500 + 100 * result.cancelled_count, 10000),
          priority: true,
        },
      );
    } catch (error) {
      reportClientError('bulk.cancel', 'Bulk cancel failed', error, undefined, 'warn');
      if (mountedRef.current) {
        setBulkAction(null);
      }
      toast.errorWithDetail(error, t('common.error'));
    }
  }, [locale, qc, mountedRef, selectedCount, selectedTasks, setBulkAction, setSelectedIds, t, recordBatchUndoTokens]);

  const handleBulkMove = useCallback(async (overrideListId?: string | null) => {
    if (selectedCount === 0) { toast.info(t('allTasks.bulkNothingSelected')); return; }
    const effectiveListId = overrideListId !== undefined ? overrideListId : (targetListId ?? null);
    if (!effectiveListId) { toast.info(t('allTasks.bulkNeedList')); return; }
    const eligible = selectedTasks.filter((tk) => tk.status !== TASK_STATUS.cancelled && tk.list_id !== effectiveListId);
    const taskIds = eligible.map((tk) => tk.id);
    if (taskIds.length === 0) { toast.info(t('allTasks.bulkNoEligibleMove')); return; }
    // bulk-move guard. Mirror the bulk-cancel / bulk-defer
    // confirm at the same 20-task threshold. Move is technically
    // reversible (the user can move them back), but a stray Enter on
    // the wrong destination list silently scatters work across
    // unrelated lists, and the per-list filter views make the loss
    // hard to spot. Force an explicit confirm so the count + intent
    // are acknowledged.
    if (taskIds.length >= BULK_CONFIRM_THRESHOLD) {
      const ok = await confirm({
        title: formatTranslation(locale, 'allTasks.bulkConfirmMoveTitle', { count: taskIds.length }),
        message: formatTranslation(locale, 'allTasks.bulkConfirmMoveMessage', { count: taskIds.length }),
        confirmLabel: t('allTasks.bulkConfirmMoveCta'),
        variant: 'default',
      });
      if (!ok) return;
    }

    // use the new `batch_move_tasks` Rust command so
    // large selections resolve atomically.
    setBulkAction('move');
    try {
      const result = await batchMoveTasks(taskIds, effectiveListId);
      invalidateTaskWorkspaceQueries(qc);
      if (mountedRef.current) {
        setBulkAction(null);
        setSelectedIds(new Set(result.skipped));
      }
      if (result.moved_count === 0) return;
      toast.success(formatBulkMovedMessage(locale, result.moved_count, t));
    } catch (error) {
      reportClientError('bulk.move', 'Bulk move failed', error, undefined, 'warn');
      if (mountedRef.current) setBulkAction(null);
      toast.errorWithDetail(error, t('common.error'));
    }
  }, [locale, qc, mountedRef, selectedCount, selectedTasks, setBulkAction, setSelectedIds, targetListId, t]);

  const handleBulkFocus = useCallback(async () => {
    if (selectedCount === 0) { toast.info(t('allTasks.bulkNothingSelected')); return; }
    const taskIds = selectedTasks
      .filter((tk) => isTaskActive(tk.status))
      .map((tk) => tk.id);
    if (taskIds.length === 0) { toast.info(t('allTasks.bulkNoEligibleFocus')); return; }

    setBulkAction('focus');
    try {
      await addToCurrentFocus(taskIds);
      invalidateTaskWorkspaceQueries(qc);
      if (mountedRef.current) {
        setBulkAction(null);
        setSelectedIds(new Set());
      }
      toast.success(formatBulkFocusedMessage(locale, taskIds.length, t));
    } catch (error) {
      reportClientError('bulk.focus', 'Bulk add to focus failed', error, undefined, 'warn');
      if (mountedRef.current) {
        setBulkAction(null);
      }
      toast.errorWithDetail(error, t('common.error'));
    }
  }, [locale, qc, mountedRef, selectedCount, selectedTasks, setBulkAction, setSelectedIds, t]);

  return {
    bulkAction,
    handleBulkCancel,
    handleBulkComplete,
    handleBulkFocus,
    handleBulkMove,
    handleBulkDefer,
    selectedCount,
  };
}
