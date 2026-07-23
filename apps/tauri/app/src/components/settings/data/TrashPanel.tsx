import { useCallback, useEffect, useMemo, useState } from 'react';

import type { Task } from '@lorvex/shared/types';

import { confirm } from '@/lib/dialogs/confirm';
import { formatRelativeTime } from '@/lib/dates/dateLocale';
import { useConfiguredTimezone } from '@/lib/dayContext';
import { reportClientError } from '@/lib/errors/errorLogging';
import { useI18n } from '@/lib/i18n';
import { toast } from '@/lib/notifications/toast';
import { emptyTrash, getArchivedTasks, permanentDeleteTask, restoreTaskFromTrash } from '@/lib/ipc/tasks/mutations/lifecycle';
import { SettingsSection } from '../SettingsPrimitives';
import { TonalButton } from '@/components/ui/TonalButton';

/**
 * user-facing Trash / undelete.
 *
 * Lists every task with `archived_at IS NOT NULL`, with three actions:
 *   - Restore (`restoreTaskFromTrash`)
 *   - Delete forever (`permanentDeleteTask`, now archive-first-enforced)
 *   - Empty trash (`emptyTrash`, hard-deletes entries older than 30 days)
 *
 * The 30-day auto-purge also runs on every app launch from the backend
 * startup-maintenance pass, so this panel reflects what the assistant
 * has already pruned without the user having to click anything.
 */
export function TrashPanel() {
  const { t, format, formatNumber } = useI18n();
  const { timezone } = useConfiguredTimezone();
  const [rows, setRows] = useState<Task[]>([]);
  // Inferred from the literal — dropped redundant `<number>` per
  // frontend-cleanup pass.
  const [totalMatching, setTotalMatching] = useState(0);
  const [loading, setLoading] = useState(false);
  const [busyId, setBusyId] = useState<string | null>(null);
  const [emptyingAll, setEmptyingAll] = useState(false);
  const [notice, setNotice] = useState<string | null>(null);

  const refresh = useCallback(async () => {
    setLoading(true);
    try {
      // the Trash IPC is now paginated. The default
      // limit is the canonical IPC cap (1k); this panel renders the
      // first page and surfaces `total_matching` to the user so they
      // know when older entries are paged out.
      const result = await getArchivedTasks();
      setRows(result.tasks);
      setTotalMatching(result.total_matching);
    } catch (error) {
      // Surface to Diagnostics + toast so a load failure is visible
      // instead of being indistinguishable from an empty trash.
      reportClientError('settings.trash.refresh', 'Failed to load archived tasks', error);
      toast.errorWithDetail(error, t('common.error'));
    } finally {
      setLoading(false);
    }
  }, [t]);

  useEffect(() => {
    void refresh();
  }, [refresh]);

  const handleRestore = useCallback(
    async (id: string) => {
      setBusyId(id);
      try {
        await restoreTaskFromTrash(id);
        setRows((prev) => prev.filter((r) => r.id !== id));
      } catch (error) {
        // Surface the failure explicitly: the optimistic filter only
        // runs after the await resolves successfully, so on rejection
        // the row stays in `rows` and the user needs a toast to know
        // restore did not succeed.
        reportClientError(
          'settings.trash.restore',
          'Failed to restore task from trash',
          error,
          `task_id=${id}`,
        );
        toast.errorWithDetail(error, t('common.error'));
      } finally {
        setBusyId(null);
      }
    },
    [t],
  );

  const handleDeleteForever = useCallback(
    async (id: string) => {
      const ok = await confirm({
        title: t('settings.trashDeleteForever'),
        message: t('settings.trashDeleteForeverConfirm'),
        variant: 'danger',
        confirmLabel: t('settings.trashDeleteForever'),
      });
      if (!ok) return;
      setBusyId(id);
      try {
        await permanentDeleteTask(id);
        setRows((prev) => prev.filter((r) => r.id !== id));
      } catch (error) {
        // Surface `delete forever` failures explicitly so the user
        // doesn't mistakenly believe the row was permanently deleted
        // when the IPC actually failed.
        reportClientError(
          'settings.trash.deleteForever',
          'Failed to permanently delete task',
          error,
          `task_id=${id}`,
        );
        toast.errorWithDetail(error, t('common.error'));
      } finally {
        setBusyId(null);
      }
    },
    [t],
  );

  const handleEmptyTrash = useCallback(async () => {
    const ok = await confirm({
      title: t('settings.trashEmptyAll'),
      message: t('settings.trashEmptyAllConfirm'),
      variant: 'danger',
      confirmLabel: t('settings.trashEmptyAll'),
    });
    if (!ok) return;
    setEmptyingAll(true);
    try {
      const result = await emptyTrash();
      setNotice(format('settings.trashEmptyResult', { count: result.deleted, remaining: result.remaining }));
      await refresh();
    } catch (error) {
      // surface "empty trash" failures so the user
      // knows the bulk delete didn't run.
      reportClientError('settings.trash.emptyAll', 'Failed to empty trash', error);
      toast.errorWithDetail(error, t('common.error'));
    } finally {
      setEmptyingAll(false);
    }
  }, [refresh, t, format]);

  const hasRows = rows.length > 0;

  return (
    <SettingsSection
      title={t('settings.trashSection')}
      description={t('settings.trashSectionDesc')}
      variant="subsection"
    >
      <div className="space-y-3">
        <div className="flex items-center justify-between gap-3">
          <p className="text-xs text-text-muted">
            {loading
              ? '…'
              : hasRows
                ? totalMatching > rows.length
                  ? `${formatNumber(rows.length)} / ${formatNumber(totalMatching)}`
                  : formatNumber(rows.length)
                : t('settings.trashEmpty')}
          </p>
          {hasRows ? (
            <TonalButton
              tone="danger"
              size="lg"
              loading={emptyingAll}
              onClick={() => { void handleEmptyTrash(); }}
            >
              {emptyingAll ? t('common.saving') : t('settings.trashEmptyAll')}
            </TonalButton>
          ) : null}
        </div>

        {notice ? (
          <p className="text-xs text-text-secondary rounded-r-control border border-card bg-surface-2/40 px-3 py-2">
            {notice}
          </p>
        ) : null}

        {hasRows ? (
          <ul className="divide-y divide-surface-3/60 rounded-r-control border border-card bg-surface-1/40 overflow-hidden">
            {rows.map((task) => (
              <TrashRow
                key={task.id}
                task={task}
                busy={busyId === task.id}
                timezone={timezone}
                onRestore={() => { void handleRestore(task.id); }}
                onDelete={() => { void handleDeleteForever(task.id); }}
              />
            ))}
          </ul>
        ) : null}
      </div>
    </SettingsSection>
  );
}

interface TrashRowProps {
  task: Task;
  busy: boolean;
  timezone: string;
  onRestore: () => void;
  onDelete: () => void;
}

function TrashRow({ task, busy, timezone, onRestore, onDelete }: TrashRowProps) {
  const { t, format, locale } = useI18n();
  const relative = useMemo(
    () => task.archived_at
      ? formatRelativeTime(task.archived_at, locale, t, format, timezone)
      : '',
    [task.archived_at, locale, t, format, timezone],
  );

  return (
    <li className="flex items-start justify-between gap-3 px-3 py-2.5">
      <div className="min-w-0 space-y-0.5">
        <p className="text-sm text-text-primary truncate font-medium">{task.title}</p>
        <p className="text-2xs text-text-muted">
          {format('settings.trashArchivedAt', { relative })}
        </p>
      </div>
      <div className="flex items-center gap-1.5 shrink-0">
        <button
          type="button"
          disabled={busy}
          onClick={onRestore}
          className="text-xs px-2.5 py-1 rounded-r-control border border-card text-text-secondary hover:bg-surface-2/60 transition-colors disabled:opacity-50 focus-ring-soft"
        >
          {t('settings.trashRestore')}
        </button>
        <TonalButton
          tone="danger"
          loading={busy}
          onClick={onDelete}
        >
          {t('settings.trashDeleteForever')}
        </TonalButton>
      </div>
    </li>
  );
}
