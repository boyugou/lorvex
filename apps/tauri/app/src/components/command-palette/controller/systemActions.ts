/**
 * React-side wrapper for the palette's system-action
 * descriptor registry. Translates the pure descriptors emitted by
 * `systemActions.logic.ts` into `PaletteActionItem` / `PaletteNavItem`
 * results, wiring confirm dialogs through the shared `confirm()`
 * modal and reporting handler errors via `reportClientError`.
 *
 * The hook is intentionally side-effect-free at instantiation: it
 * only allocates handler closures. The descriptor list is built on
 * every render from the latest `selectedTask` + IPC handle bundle so
 * the "Permanent delete" entry stays in sync with the user's
 * highlighted task.
 */

import { createElement, useCallback, useMemo, type ReactNode } from 'react';
import { emit } from '@/lib/platform/events';
import { useQueryClient } from '@tanstack/react-query';

import { confirm } from '@/lib/dialogs/confirm';
import { reportClientError } from '@/lib/errors/errorLogging';
import { useI18n } from '@/lib/i18n';
import { useTheme } from '@/lib/theme';
import { exportDataSnapshot, importDataSnapshot, purgeCancelledTasks } from '@/lib/ipc/settings';
import { resetOutboxRetryCountsForTransportSwitch } from '@/lib/ipc/sync';
import type { Task } from '@/lib/ipc/tasks/models';
import { permanentDeleteTask } from '@/lib/ipc/tasks/mutations/lifecycle';
import {
  invalidateChangelogQueries,
  invalidateTaskWorkspaceQueries,
} from '@/lib/query/queryKeys';
import { formatShortcut } from '@/lib/shortcuts';
import { toast } from '@/lib/notifications/toast';
import { localeRegistry, type TranslationKey } from '@/locales';
import {
  ArchiveIcon,
  ArrowRightIcon,
  BoltIcon,
  FlameIcon,
  GearIcon,
  MoveIcon,
  NotebookIcon,
  RecurrenceIcon,
  SparkleIcon,
  TrashIcon,
  WarningIcon,
} from '@/components/ui/icons';
import type { PaletteActionItem, PaletteNavItem } from '../types';
import {
  buildSystemActionDescriptors,
  filterSystemActionDescriptors,
  type SelectedTaskContext,
  type SystemActionId,
} from './systemActions.logic';

/**
 * Visual icon per system action. Centralized so a single change
 * propagates to every render path. Falls back to `GearIcon` for any
 * id we forget to map — the entry still renders correctly.
 */
function iconForSystemAction(id: SystemActionId): ReactNode {
  switch (id) {
    case 'system.exportData':
      return createElement(ArchiveIcon);
    case 'system.importData':
      return createElement(ArrowRightIcon);
    case 'system.syncNow':
      return createElement(RecurrenceIcon);
    case 'system.resetSyncRetries':
      return createElement(WarningIcon);
    case 'system.permanentDeleteTask':
      return createElement(TrashIcon);
    case 'system.openShortcuts':
      return createElement(GearIcon);
    case 'system.toggleLanguage':
      return createElement(SparkleIcon);
    case 'system.cycleTheme':
      return createElement(SparkleIcon);
    case 'system.createHabit':
      return createElement(FlameIcon);
    case 'system.completeHabit':
      return createElement(FlameIcon);
    case 'system.openDailyReview':
      return createElement(NotebookIcon);
    case 'system.moveTaskHint':
      return createElement(MoveIcon);
    case 'system.purgeCancelled':
      return createElement(TrashIcon);
    case 'system.deleteAllData':
      return createElement(BoltIcon);
    default:
      return createElement(GearIcon);
  }
}

interface UseSystemActionsArgs {
  query: string;
  onClose: () => void;
  onNavigate: (target: { type: 'settings'; sectionId?: string } | { type: 'daily_review' } | { type: 'habits' }) => void;
  selectedTask: Task | null;
}

interface SystemActionResult {
  /** Palette items derived from descriptors after query-filtering. */
  items: Array<PaletteActionItem | PaletteNavItem>;
  /** Stable id list (for tests / a11y / debugging). */
  ids: SystemActionId[];
}

/**
 * Hook entry point.
 *
 * Consumed by `useCommandPaletteResults`. Filters by the current
 * query so the system actions surface in both the empty state and
 * the live-typing search.
 */
export function useSystemActions(args: UseSystemActionsArgs): SystemActionResult {
  const { query, onClose, onNavigate, selectedTask } = args;
  const { t, format, setLocale, locale } = useI18n();
  const { mode, setMode } = useTheme();
  const queryClient = useQueryClient();

  const reportPaletteError = useCallback(
    (action: string, error: unknown) => {
      reportClientError(
        `commandPalette.system.${action}`,
        `Palette system action failed: ${action}`,
        error,
        query,
        'warn',
      );
    },
    [query],
  );

  // Single helper that pipes a side-effecting handler through the
  // common close + invalidate path so descriptor entries stay tiny.
  const wrapHandler = useCallback(
    (label: string, fn: () => Promise<void> | void) => {
      return async () => {
        try {
          await fn();
          onClose();
        } catch (error) {
          reportPaletteError(label, error);
          toast.errorWithDetail(error, t('common.error'));
        }
      };
    },
    [onClose, reportPaletteError, t],
  );

  const exportData = useCallback(async () => {
    // Lazy-load the Tauri save dialog plugin so the import cost is
    // paid once, only when the user actually triggers an export.
    const { save } = await import('@tauri-apps/plugin-dialog');
    const now = new Date();
    const stamp = now.toISOString().replace(/[-:]/g, '').replace(/\.\d+Z$/, 'Z');
    const defaultName = `lorvex-export-v1-${stamp}.zip`;
    const chosenPath = await save({
      title: t('settings.exportSaveDialogTitle'),
      defaultPath: defaultName,
      filters: [{ name: 'ZIP Archive', extensions: ['zip'] }],
    });
    if (!chosenPath) return;
    const result = await exportDataSnapshot(chosenPath);
    toast.success(format('settings.exportSavedToPath', { path: result.export_path }));
  }, [format, t]);

  const importData = useCallback(async () => {
    const { open } = await import('@tauri-apps/plugin-dialog');
    const chosen = await open({
      title: t('palette.importData'),
      multiple: false,
      directory: false,
      filters: [{ name: 'ZIP Archive', extensions: ['zip'] }],
    });
    if (!chosen || typeof chosen !== 'string') return;
    const result = await importDataSnapshot(chosen);
    toast.success(format('palette.importDataResult', { count: result.entities_created }));
    invalidateTaskWorkspaceQueries(queryClient);
    invalidateChangelogQueries(queryClient);
  }, [format, queryClient, t]);

  const syncNow = useCallback(async () => {
    // Sync's preflight (offline check, save-state debounce, backend
    // selection) is heavy state that lives in the Settings panel —
    // re-implementing it here would duplicate the Run-now button's
    // entire validation tree. The palette's role is to give the user
    // a one-keystroke path to that pane; an earlier revision also
    // emitted a `menu://sync-now` event in the hope that the panel
    // would auto-fire Run-now, but no listener was ever wired and
    // the channel was not registered in `event_channels.rs`. Drop
    // the dead emit so the palette has a single, predictable effect
    // (focus the Sync card) and the user clicks Run-now from there.
    onNavigate({ type: 'settings', sectionId: 'settings-section-sync' });
  }, [onNavigate]);

  const resetSyncRetries = useCallback(async () => {
    const reset = await resetOutboxRetryCountsForTransportSwitch();
    toast.success(format('palette.resetSyncResult', { count: reset }));
  }, [format]);

  const permanentDeleteTaskHandler = useCallback(
    async (task: SelectedTaskContext) => {
      await permanentDeleteTask(task.id);
      toast.success(format('palette.permanentDeleteTaskDone', { title: task.title }));
      invalidateTaskWorkspaceQueries(queryClient);
    },
    [format, queryClient],
  );

  const openShortcuts = useCallback(async () => {
    try {
      await emit('menu://open-shortcuts');
    } catch (error) {
      reportPaletteError('openShortcuts.emit', error);
    }
  }, [reportPaletteError]);

  const toggleLanguage = useCallback(async () => {
    const codes = localeRegistry.map((entry) => entry.code);
    const currentIndex = codes.indexOf(locale);
    const next = codes[(currentIndex + 1) % codes.length] ?? 'en';
    setLocale(next);
    toast.info(format('settings.languageChanged', { locale: next }));
  }, [format, locale, setLocale]);

  const cycleTheme = useCallback(async () => {
    const next = mode === 'light' ? 'dark' : mode === 'dark' ? 'system' : 'light';
    setMode(next);
    const themeLabel = next === 'light'
      ? t('settings.themeLight')
      : next === 'dark'
        ? t('settings.themeDark')
        : t('settings.themeSystem');
    toast.info(format('palette.cycleThemeChanged', { theme: themeLabel }));
  }, [format, mode, setMode, t]);

  const openCreateHabit = useCallback(async () => {
    // Habit creation is a multi-field form on the Habits view. Nav
    // there so the user can fill it in. A future iteration could add
    // a quick-capture-style habit dialog directly from the palette.
    onNavigate({ type: 'habits' });
  }, [onNavigate]);

  const openCompleteHabit = useCallback(async () => {
    // Habit completion lives in the Habits view (one tap per
    // habit). Until the palette grows a per-habit picker, navigating
    // there is the cheapest path to action.
    onNavigate({ type: 'habits' });
  }, [onNavigate]);

  const showMoveTaskHint = useCallback(async () => {
    toast.info(t('palette.moveTaskHintDesc'));
  }, [t]);

  const purgeCancelled = useCallback(async () => {
    const result = await purgeCancelledTasks();
    toast.success(format('palette.purgeCancelledResult', { count: result.purged_count }));
    invalidateTaskWorkspaceQueries(queryClient);
  }, [format, queryClient]);

  const openDeleteAllData = useCallback(async () => {
    // Destructive: route to Settings → Danger Zone where the typed
    // "DELETE" confirmation lives. Bypassing the typed token from
    // the palette would defeat that guard.
    onNavigate({ type: 'settings', sectionId: 'settings-section-data' });
  }, [onNavigate]);

  const selectedTaskContext: SelectedTaskContext | null = useMemo(
    () => (selectedTask ? { id: selectedTask.id, title: selectedTask.title } : null),
    [selectedTask],
  );

  const descriptors = useMemo(
    () =>
      buildSystemActionDescriptors({
        exportData,
        importData,
        syncNow,
        resetSyncRetries,
        permanentDeleteTask: permanentDeleteTaskHandler,
        openShortcuts,
        toggleLanguage,
        cycleTheme,
        openCreateHabit,
        openCompleteHabit,
        showMoveTaskHint,
        purgeCancelled,
        openDeleteAllData,
        selectedTask: selectedTaskContext,
      }),
    [
      exportData,
      importData,
      syncNow,
      resetSyncRetries,
      permanentDeleteTaskHandler,
      openShortcuts,
      toggleLanguage,
      cycleTheme,
      openCreateHabit,
      openCompleteHabit,
      showMoveTaskHint,
      purgeCancelled,
      openDeleteAllData,
      selectedTaskContext,
    ],
  );

  const filtered = useMemo(
    () =>
      filterSystemActionDescriptors(descriptors, query, (key: TranslationKey) => t(key)),
    [descriptors, query, t],
  );

  const items = useMemo<Array<PaletteActionItem | PaletteNavItem>>(() => {
    return filtered.map((descriptor) => {
      const baseLabel = t(descriptor.labelKey);
      const label =
        descriptor.id === 'system.permanentDeleteTask' && selectedTask
          ? `${baseLabel}: ${selectedTask.title}`
          : baseLabel;
      const icon = iconForSystemAction(descriptor.id);
      const shortcut = descriptor.shortcut ? formatShortcut(descriptor.shortcut) : undefined;

      if (descriptor.kind === 'nav' && descriptor.navTo) {
        return {
          kind: 'nav',
          label,
          icon,
          shortcut,
          view: descriptor.navTo,
        } satisfies PaletteNavItem;
      }

      const action = wrapHandler(descriptor.id, async () => {
        if (descriptor.kind === 'confirm' && descriptor.confirm) {
          // `exactOptionalPropertyTypes` prevents passing
          // `confirmLabel: undefined` — build the options object
          // conditionally so the absent case omits the key entirely.
          const options: Parameters<typeof confirm>[0] = {
            title: t(descriptor.confirm.titleKey),
            message: t(descriptor.confirm.messageKey),
            variant: descriptor.confirm.variant ?? 'danger',
          };
          if (descriptor.confirm.confirmLabelKey) {
            options.confirmLabel = t(descriptor.confirm.confirmLabelKey);
          }
          const confirmed = await confirm(options);
          if (!confirmed) return;
        }
        if (descriptor.run) await descriptor.run();
      });

      return {
        kind: 'action',
        label,
        icon,
        shortcut,
        action: () => {
          void action();
        },
      } satisfies PaletteActionItem;
    });
  }, [filtered, selectedTask, t, wrapHandler]);

  const ids = useMemo(() => filtered.map((descriptor) => descriptor.id), [filtered]);

  return { items, ids };
}
