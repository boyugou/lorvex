
import type { TranslationKey } from '@/locales';
import type { ShortcutToken } from '@/lib/shortcuts';
import type { View } from '@/lib/types';

export type SystemActionId =
  | 'system.exportData'
  | 'system.importData'
  | 'system.syncNow'
  | 'system.resetSyncRetries'
  | 'system.permanentDeleteTask'
  | 'system.openShortcuts'
  | 'system.toggleLanguage'
  | 'system.cycleTheme'
  | 'system.createHabit'
  | 'system.completeHabit'
  | 'system.openDailyReview'
  | 'system.moveTaskHint'
  | 'system.purgeCancelled'
  | 'system.deleteAllData';

/**
 * `nav` — descriptor activates by navigating to a view (no confirm).
 * `run` — fire-and-forget side-effect; no confirm.
 * `confirm` — open the shared confirm() modal first; only run on YES.
 */
type SystemActionKind = 'nav' | 'run' | 'confirm';

export interface SystemActionDescriptor {
  id: SystemActionId;
  /** Title rendered in the palette row. */
  labelKey: TranslationKey;
  /** Optional secondary description rendered under the title — currently
   *  used only by the descriptor tests; the palette UI does not yet
   *  render two-line entries. Keeping the key here preserves the
   *  contract for a future visual upgrade. */
  descKey?: TranslationKey;
  shortcut?: ShortcutToken[];
  kind: SystemActionKind;
  /** For `kind: 'nav'`. */
  navTo?: View;
  /** For `kind: 'run'` / `'confirm'`. Resolves once the side-effect
   *  finishes. The descriptor never throws — handlers must catch and
   *  surface their own toasts; the palette runner only awaits. */
  run?: () => Promise<void> | void;
  /** Confirm dialog metadata (only when `kind === 'confirm'`). */
  confirm?: {
    titleKey: TranslationKey;
    messageKey: TranslationKey;
    confirmLabelKey?: TranslationKey;
    variant?: 'danger' | 'default';
  };
}

export interface SelectedTaskContext {
  id: string;
  title: string;
}

export interface SystemActionDeps {
  /** Run when the user activates "Export data". Owns the save dialog. */
  exportData: () => Promise<void> | void;
  /** Open import dialog + apply snapshot. */
  importData: () => Promise<void> | void;
  /** Trigger a "Sync now" cycle for the active backend. */
  syncNow: () => Promise<void> | void;
  /** Reset the sync outbox retry counters. */
  resetSyncRetries: () => Promise<void> | void;
  /** Permanently delete the currently selected task (no-op when null). */
  permanentDeleteTask: (task: SelectedTaskContext) => Promise<void> | void;
  /** Open the keyboard-shortcuts panel. */
  openShortcuts: () => Promise<void> | void;
  /** Cycle UI language between user-managed locales. */
  toggleLanguage: () => Promise<void> | void;
  /** Cycle theme: light → dark → system → light. */
  cycleTheme: () => Promise<void> | void;
  /** Open the habit-creation surface (currently nav to Habits view). */
  openCreateHabit: () => Promise<void> | void;
  /** Open the habit-completion picker (currently nav to Habits view —
   *  the per-habit complete buttons live there). */
  openCompleteHabit: () => Promise<void> | void;
  /** Show the user a hint that Tab → list-picker is the move-task
   *  flow. The palette already has the in-place picker; this entry
   *  exists purely so users discover the affordance from the empty
   *  state. */
  showMoveTaskHint: () => Promise<void> | void;
  /** Clear all cancelled tasks. */
  purgeCancelled: () => Promise<void> | void;
  /** Reset every local mutation. Routes through Settings → Danger
   *  Zone because the multi-step typed-confirmation lives there;
   *  invoking it directly from the palette would bypass the typed
   *  token guard (`DELETE`) the destructive flow requires. */
  openDeleteAllData: () => Promise<void> | void;
  /** Currently selected task — required for permanent-delete. */
  selectedTask: SelectedTaskContext | null;
}

/**
 * Build the canonical system-action descriptor list.
 *
 * Order is intentional and matches the palette's empty-state
 * grouping: most-frequent first (Sync, Export, Import), then
 * task-context actions, then preference toggles, then destructive
 * actions, with `Delete all data` last so an inattentive Enter on a
 * fresh palette never hits it.
 */
export function buildSystemActionDescriptors(
  deps: SystemActionDeps,
): SystemActionDescriptor[] {
  const list: SystemActionDescriptor[] = [];

  list.push({
    id: 'system.syncNow',
    labelKey: 'palette.syncNow',
    descKey: 'palette.syncNowDesc',
    shortcut: ['Mod', 'Shift', 'S'],
    kind: 'run',
    run: deps.syncNow,
  });

  list.push({
    id: 'system.exportData',
    labelKey: 'palette.exportData',
    descKey: 'palette.exportDataDesc',
    shortcut: ['Mod', 'Shift', 'E'],
    kind: 'run',
    run: deps.exportData,
  });

  list.push({
    id: 'system.importData',
    labelKey: 'palette.importData',
    descKey: 'palette.importDataDesc',
    shortcut: ['Mod', 'Shift', 'I'],
    kind: 'confirm',
    confirm: {
      titleKey: 'palette.importData',
      messageKey: 'palette.importDataConfirm',
      confirmLabelKey: 'palette.importData',
      variant: 'default',
    },
    run: deps.importData,
  });

  list.push({
    id: 'system.openDailyReview',
    labelKey: 'palette.openDailyReview',
    kind: 'nav',
    navTo: { type: 'daily_review' },
  });

  list.push({
    id: 'system.createHabit',
    labelKey: 'palette.createHabit',
    kind: 'run',
    run: deps.openCreateHabit,
  });

  list.push({
    id: 'system.completeHabit',
    labelKey: 'palette.completeHabit',
    kind: 'run',
    run: deps.openCompleteHabit,
  });

  list.push({
    id: 'system.moveTaskHint',
    labelKey: 'palette.moveTaskHint',
    descKey: 'palette.moveTaskHintDesc',
    kind: 'run',
    run: deps.showMoveTaskHint,
  });

  list.push({
    id: 'system.toggleLanguage',
    labelKey: 'palette.toggleLanguage',
    descKey: 'palette.toggleLanguageDesc',
    kind: 'run',
    run: deps.toggleLanguage,
  });

  list.push({
    id: 'system.cycleTheme',
    labelKey: 'palette.cycleTheme',
    descKey: 'palette.cycleThemeDesc',
    kind: 'run',
    run: deps.cycleTheme,
  });

  list.push({
    id: 'system.openShortcuts',
    labelKey: 'palette.openShortcuts',
    shortcut: ['?'],
    kind: 'run',
    run: deps.openShortcuts,
  });

  // Permanent task delete is conditionally surfaced — only when a
  // task is currently selected in the search results. We attach it
  // here (descriptor list is the source of truth) and the React
  // wrapper filters by `selectedTask`.
  if (deps.selectedTask) {
    const task = deps.selectedTask;
    list.push({
      id: 'system.permanentDeleteTask',
      labelKey: 'palette.permanentDeleteTask',
      kind: 'confirm',
      confirm: {
        titleKey: 'palette.permanentDeleteTask',
        messageKey: 'palette.permanentDeleteTaskConfirm',
        confirmLabelKey: 'palette.permanentDeleteTask',
        variant: 'danger',
      },
      run: () => deps.permanentDeleteTask(task),
    });
  }

  list.push({
    id: 'system.purgeCancelled',
    labelKey: 'palette.purgeCancelled',
    kind: 'confirm',
    confirm: {
      titleKey: 'palette.purgeCancelled',
      messageKey: 'palette.purgeCancelledConfirm',
      confirmLabelKey: 'palette.purgeCancelled',
      variant: 'danger',
    },
    run: deps.purgeCancelled,
  });

  list.push({
    id: 'system.resetSyncRetries',
    labelKey: 'palette.resetSync',
    kind: 'confirm',
    confirm: {
      titleKey: 'palette.resetSync',
      messageKey: 'palette.resetSyncConfirm',
      confirmLabelKey: 'palette.resetSync',
      variant: 'danger',
    },
    run: deps.resetSyncRetries,
  });

  // ALWAYS LAST: hardest-to-reach destructive action.
  list.push({
    id: 'system.deleteAllData',
    labelKey: 'palette.deleteAllData',
    descKey: 'palette.deleteAllDataDesc',
    kind: 'run',
    run: deps.openDeleteAllData,
  });

  return list;
}

/**
 * Filter descriptors by the user's typed query. Empty query returns
 * all entries; otherwise we substring-match the localized label so
 * the palette's empty-state list and search-mode list stay
 * consistent.
 *
 * The filter is a pure function: callers pass already-translated
 * label strings to avoid coupling this module to the i18n runtime.
 */
export function filterSystemActionDescriptors(
  descriptors: SystemActionDescriptor[],
  query: string,
  translateLabel: (key: TranslationKey) => string,
): SystemActionDescriptor[] {
  const trimmed = query.trim().toLowerCase();
  if (trimmed.length === 0) return descriptors;
  return descriptors.filter((descriptor) => {
    const label = translateLabel(descriptor.labelKey).toLowerCase();
    if (label.includes(trimmed)) return true;
    if (descriptor.descKey) {
      const desc = translateLabel(descriptor.descKey).toLowerCase();
      if (desc.includes(trimmed)) return true;
    }
    return false;
  });
}

/**
 * Convenience: every descriptor's i18n key. Tests use this to assert
 * each key is present in `en.ts` and to spot drift between the
 * descriptor list and the locale catalog.
 */
export function collectSystemActionTranslationKeys(
  descriptors: SystemActionDescriptor[],
): TranslationKey[] {
  const keys = new Set<TranslationKey>();
  for (const descriptor of descriptors) {
    keys.add(descriptor.labelKey);
    if (descriptor.descKey) keys.add(descriptor.descKey);
    if (descriptor.confirm) {
      keys.add(descriptor.confirm.titleKey);
      keys.add(descriptor.confirm.messageKey);
      if (descriptor.confirm.confirmLabelKey) {
        keys.add(descriptor.confirm.confirmLabelKey);
      }
    }
  }
  return Array.from(keys);
}
