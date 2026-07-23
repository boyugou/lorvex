import { createElement } from 'react';
import { useEffect, useMemo, useState } from 'react';
import type { ListWithCount, Task } from '@/lib/ipc/tasks/models';
import { undoTaskLifecycleBatch } from '@/lib/ipc/tasks/mutations/lifecycle';
import { quickCapture, updateTask } from '@/lib/ipc/tasks/mutations/quickCapture';
import { formatShortcut } from '@/lib/shortcuts';
import {
  consumeUndoToken,
  listRecentUndoTokens,
  type RecentUndoToken,
} from '@/lib/undoTokenStore';
import type { TranslationKey } from '@/locales';
import {
  ArchiveIcon,
  ClipboardIcon,
  GearIcon,
  MoveIcon,
  PlusIcon,
  TrashIcon,
  UndoIcon,
  WarningIcon,
} from '@/components/ui/icons';
import type { View } from '@/lib/types';
import { resultIdentity } from '../model';
import type {
  KeyedResult,
  PaletteActionItem,
  PaletteNavItem,
  PaletteSection,
  ResultItem,
} from '../types';
import type { PaletteMutationRunner } from './mutations';
import { scoreMatch } from './fuzzyScore';
import {
  createBrowserRecentUndoTokenIntervalHost,
  installRecentUndoTokenSnapshotRuntime,
} from './recentUndoTokens.runtime';
import { useSystemActions } from './systemActions';
import {
  listRecentPaletteActivations,
  listTaskOpens,
  topFrequentTasks,
  type RecentPaletteActivation,
  type TaskOpenEntry,
} from './paletteUsage';

const recentUndoTokenIntervalHost = createBrowserRecentUndoTokenIntervalHost();

export function createNoResultCreateTaskItem({
  onClose,
  onQuickCapture,
  query,
  t,
}: {
  onClose: () => void;
  onQuickCapture: (data?: { title?: string }) => void;
  query: string;
  t: (key: TranslationKey) => string;
}): PaletteActionItem {
  const title = query.trim();
  return {
    kind: 'action',
    label: `${t('palette.createTask')}: ${title}`,
    icon: createElement(PlusIcon),
    action: () => {
      onClose();
      onQuickCapture({ title });
    },
  };
}

interface UseCommandPaletteResultsArgs {
  shelveListFromPalette: (listId: string, listName: string) => void;
  confirmArchiveListId: string | null;
  createListFromPalette: (name: string) => void;
  deleteListFromPalette: (listId: string) => void;
  lists: ListWithCount[];
  moveTask: Task | null;
  navItems: Array<Omit<PaletteNavItem, 'kind'>>;
  onClose: () => void;
  onNavigate: (view: View) => void;
  onQuickCapture: (data?: { title?: string }) => void;
  /**
   * Task-open callback for the empty-query "Frequent tasks" lane.
   * The stored log only knows ids + titles, so re-opening goes
   * through the standard select-task path — the parent surface
   * decides whether to mount the detail panel or route elsewhere.
   */
  onSelectTask: (taskId: string) => void;
  query: string;
  runPaletteMutation: PaletteMutationRunner;
  searchResults: Task[];
  selectedTask: Task | null;
  t: (key: TranslationKey) => string;
  format: ReturnType<typeof import('@/lib/i18n').useI18n>['format'];
}

/**
 * snapshot + refresh the persistent undo-token list on a
 * 500ms tick. `enabled` is false whenever the user is typing a query
 * or is in move-task mode — we skip the interval entirely in those
 * states so the rest of the results `useMemo` doesn't churn every
 * 500ms while the user is searching.
 */
function useRecentUndoTokens(enabled: boolean): RecentUndoToken[] {
  const [tokens, setTokens] = useState<RecentUndoToken[]>(() => (enabled ? listRecentUndoTokens() : []));

  useEffect(() => {
    if (!enabled) {
      setTokens([]);
      return;
    }
    // Always re-snapshot on every tick: the palette needs the
    // countdown in each row to advance even when the token identity
    // set is stable. The list is capped at MAX_ENTRIES so this costs
    // at most a few dozen object allocations per second.
    return installRecentUndoTokenSnapshotRuntime({
      intervalHost: recentUndoTokenIntervalHost,
      intervalMs: 500,
      publishTokens: setTokens,
      snapshotTokens: listRecentUndoTokens,
    });
  }, [enabled]);

  return tokens;
}

export function useCommandPaletteResults({
  shelveListFromPalette,
  confirmArchiveListId,
  createListFromPalette,
  deleteListFromPalette,
  lists,
  moveTask,
  navItems,
  onClose,
  onNavigate,
  onQuickCapture,
  onSelectTask,
  query,
  runPaletteMutation,
  searchResults,
  selectedTask,
  t,
  format,
}: UseCommandPaletteResultsArgs): {
  keyedResults: KeyedResult[];
  results: ResultItem[];
} {
  const recentUndoEnabled = !moveTask && query.trim().length === 0;
  const recentUndoTokens = useRecentUndoTokens(recentUndoEnabled);

  // Snapshot the persistent palette-usage log once per empty-query
  // render. The data is stored in localStorage; reading inside the
  // memo's body is OK because we don't depend on it changing during
  // the open palette session — activations record on close, so by the
  // time the palette reopens the next snapshot reflects them.
  const recentActivations = useMemo<RecentPaletteActivation[]>(
    () => (recentUndoEnabled ? listRecentPaletteActivations() : []),
    [recentUndoEnabled],
  );
  const frequentTasks = useMemo<TaskOpenEntry[]>(
    () => (recentUndoEnabled ? topFrequentTasks(listTaskOpens(), 3) : []),
    [recentUndoEnabled],
  );

  // system-action registry. Filtered against the current
  // query so the entries surface in both the empty state and live
  // search.
  const systemActions = useSystemActions({
    query,
    onClose,
    onNavigate,
    selectedTask,
  });
  // Per-result section override populated alongside `items.push(...)`
  // for entries that belong in the editorial "Recently used" /
  // "Frequent tasks" lanes (Spotlight-style). Untagged items fall
  // back to their structural `kind` in the renderer.
  const sectionOverrides = useMemo(() => new WeakMap<ResultItem, PaletteSection>(), []);
  const results = useMemo<ResultItem[]>(() => {
    const items: ResultItem[] = [];
    const trimmedQuery = query.trim();
    const pushSectioned = (item: ResultItem, section: PaletteSection) => {
      items.push(item);
      sectionOverrides.set(item, section);
    };

    if (moveTask) {
      const scoredLists = lists
        .map((list) => ({ list, score: scoreMatch(trimmedQuery, list.name) }))
        .filter((entry): entry is { list: typeof entry.list; score: number } =>
          entry.score !== null,
        )
        .sort((a, b) => b.score - a.score);
      for (const { list } of scoredLists) {
        items.push({
          kind: 'action',
          label: `${list.icon ?? ''} ${list.name}`.trim(),
          icon: createElement(MoveIcon),
          action: () => runPaletteMutation(
            () => updateTask(moveTask.id, { list_id: list.id }),
            'move-task',
            { affectedListIds: [moveTask.list_id, list.id] },
          ),
        });
      }
      return items;
    }

    if (trimmedQuery.startsWith('@')) {
      const scopeRaw = trimmedQuery.slice(1).trim();
      const captureSeparatorIdx = scopeRaw.indexOf('::');
      const listQueryRaw = (captureSeparatorIdx === -1 ? scopeRaw : scopeRaw.slice(0, captureSeparatorIdx)).trim();
      const scopedCaptureTitle = captureSeparatorIdx === -1 ? '' : scopeRaw.slice(captureSeparatorIdx + 2).trim();
      const scopedListQuery = listQueryRaw.toLowerCase();
      const matchedLists = lists.filter((list) => list.name.toLowerCase().includes(scopedListQuery));
      const primaryList = matchedLists[0];
      const uniqueScopedList = matchedLists.length === 1 ? matchedLists[0] : null;

      if (primaryList && scopedCaptureTitle.length >= 2) {
        items.push({
          kind: 'action',
          label: `${t('palette.addToList')} "${scopedCaptureTitle}" \u2192 ${primaryList.name}`,
          icon: createElement(PlusIcon),
          shortcut: formatShortcut(['Enter']),
          action: () => runPaletteMutation(
            () => quickCapture({ title: scopedCaptureTitle, listId: primaryList.id }),
            'quick-capture-scoped-list',
          ),
        });
      }

      if (uniqueScopedList) {
        const archiveArmed = confirmArchiveListId === uniqueScopedList.id;
        items.push({
          kind: 'action',
          label: archiveArmed
            ? `${t('palette.shelveListToSomedayConfirm')}: ${uniqueScopedList.name}`
            : `${t('palette.shelveListToSomeday')}: ${uniqueScopedList.name}`,
          icon: archiveArmed ? createElement(WarningIcon) : createElement(ArchiveIcon),
          shortcut: formatShortcut(['Mod', 'Enter']),
          action: () => shelveListFromPalette(uniqueScopedList.id, uniqueScopedList.name),
        });
        // delete opens the shared confirm() modal; no
        // inline armed state is needed anymore.
        items.push({
          kind: 'action',
          label: `${t('palette.deleteList')}: ${uniqueScopedList.name}`,
          icon: createElement(TrashIcon),
          shortcut: formatShortcut(['Shift', 'Enter']),
          action: () => deleteListFromPalette(uniqueScopedList.id),
        });
      }

      for (const list of matchedLists) {
        items.push({ kind: 'nav', label: list.name, icon: list.icon ?? createElement(ClipboardIcon), view: { type: 'list', listId: list.id } });
      }

      if (matchedLists.length === 0 && listQueryRaw.length >= 2 && captureSeparatorIdx === -1) {
        items.push({
          kind: 'action',
          label: `${t('palette.createList')}: ${listQueryRaw}`,
          icon: createElement(ClipboardIcon),
          action: () => createListFromPalette(listQueryRaw),
        });
      }

      return items;
    }

    if (query.trim().length < 1) {
      // when no query is typed, surface any persistent
      // undo tokens at the top. The token list already has expired
      // entries pruned by `listRecentUndoTokens`, so items that appear
      // here are guaranteed to be redeemable by the backend.
      //
      // Tokens are grouped: a bulk operation emits N backend tokens
      // under the same visible label, and should present as one
      // palette entry whose Enter redeems the whole group.
      const groupedByLabel = new Map<string, RecentUndoToken[]>();
      for (const entry of recentUndoTokens) {
        const group = groupedByLabel.get(entry.label);
        if (group) group.push(entry);
        else groupedByLabel.set(entry.label, [entry]);
      }
      const now = Date.now();
      for (const [label, group] of groupedByLabel) {
        // Use the earliest expiresAt in the group so the countdown
        // reflects the first token that would become unredeemable.
        const soonest = group.reduce((min, e) => (e.expiresAt < min ? e.expiresAt : min), Infinity);
        const secondsLeft = Math.max(0, Math.ceil((soonest - now) / 1000));
        const remaining = format('palette.recentUndo.remaining', { seconds: String(secondsLeft) });
        const displayLabel = `${format('palette.recentUndo.label', { label })} \u00B7 ${remaining}`;
        const tokens = group.map((e) => e.token);
        items.push({
          kind: 'action',
          label: displayLabel,
          icon: createElement(UndoIcon),
          action: () => runPaletteMutation(async () => {
            await undoTaskLifecycleBatch(tokens);
            for (const tk of tokens) consumeUndoToken(tk);
          }, 'recent-undo'),
        });
      }
      // Recent activations: surface the top 5 nav/action entries the
      // user has activated, in MRU order. Matched by stored `key`
      // against the live nav + systemAction registries so a renamed
      // or removed entry drops out of recents the next render. Tasks
      // are tracked separately under "Frequent tasks" because their
      // value here is frequency rather than recency.
      const navByKey = new Map(
        navItems.map((nav) => [`nav:${nav.label}`, nav] as const),
      );
      const systemActionByKey = new Map(
        systemActions.items.map((sa) => [`action:${sa.label}`, sa] as const),
      );
      const recentInjected = new Set<string>();
      let recentCount = 0;
      for (const activation of recentActivations) {
        if (recentCount >= 5) break;
        if (activation.kind === 'nav') {
          const nav = navByKey.get(activation.key as `nav:${string}`);
          if (nav) {
            pushSectioned(
              { kind: 'nav', label: nav.label, icon: nav.icon, shortcut: nav.shortcut, view: nav.view },
              'recent',
            );
            recentInjected.add(activation.key);
            recentCount += 1;
          }
        } else if (activation.kind === 'action') {
          const sa = systemActionByKey.get(activation.key as `action:${string}`);
          if (sa) {
            pushSectioned(sa, 'recent');
            recentInjected.add(activation.key);
            recentCount += 1;
          }
        }
      }

      // Frequent tasks: synthesize lightweight Task-shaped entries
      // from the stored open log. We render them as `action` items
      // (label = stored title) because the original Task object is
      // not in scope here — `onSelectTask` is the only thing the
      // activation needs anyway. Capped at 3 per the spec.
      for (const entry of frequentTasks) {
        pushSectioned({
          kind: 'action',
          label: entry.title,
          icon: createElement(ClipboardIcon),
          action: () => {
            onClose();
            onSelectTask(entry.taskId);
          },
        }, 'frequent');
      }

      for (const nav of navItems) {
        // Skip entries we just surfaced in the recents lane to avoid
        // duplicates — keeps the empty list tidy without a separator.
        if (recentInjected.has(`nav:${nav.label}`)) continue;
        items.push({ kind: 'nav', label: nav.label, icon: nav.icon, shortcut: nav.shortcut, view: nav.view });
      }
      for (const list of lists) {
        items.push({ kind: 'nav', label: list.name, icon: list.icon ?? createElement(ClipboardIcon), view: { type: 'list', listId: list.id } });
      }
      items.push({
        kind: 'action',
        label: t('capture.addTask'),
        icon: createElement(PlusIcon),
        shortcut: formatShortcut(['Mod', 'N']),
        action: () => {
          onClose();
          onQuickCapture();
        },
      });
      items.push({
        kind: 'nav',
        label: t('nav.settings'),
        icon: createElement(GearIcon),
        shortcut: formatShortcut(['Mod', ',']),
        view: { type: 'settings' },
      });

      // system-action registry — destructive, data, sync, and
      // preference toggles. Rendered after navigation + Settings so
      // the most-used entries (today/upcoming/lists/quick-capture)
      // remain at the top of the empty state. The registry filters
      // itself: when a query is typed it only emits matching entries.
      for (const item of systemActions.items) {
        items.push(item);
      }
    } else {
      // tiered match scoring. Prefix > word-start >
      // substring > fuzzy-subsequence. Pre-score lists + nav entries
      // and sort within each category so a list named "Zebras" no
      // longer outranks a nav "Zebra cage cleanup" when the user types
      // "zebra cage", and single-character typos still surface results
      // via the fuzzy tier.
      const scoredLists = lists
        .map((list) => ({ list, score: scoreMatch(trimmedQuery, list.name) }))
        .filter((entry): entry is { list: typeof entry.list; score: number } =>
          entry.score !== null,
        )
        .sort((a, b) => b.score - a.score);
      const matchedLists = scoredLists.map((entry) => entry.list);
      const scoredNavs = navItems
        .map((nav) => ({ nav, score: scoreMatch(trimmedQuery, nav.label) }))
        .filter((entry): entry is { nav: typeof entry.nav; score: number } =>
          entry.score !== null,
        )
        .sort((a, b) => b.score - a.score);
      for (const { nav } of scoredNavs) {
        items.push({ kind: 'nav', label: nav.label, icon: nav.icon, shortcut: nav.shortcut, view: nav.view });
      }
      if (scoreMatch(trimmedQuery, t('nav.settings')) !== null) {
        items.push({
          kind: 'nav',
          label: t('nav.settings'),
          icon: createElement(GearIcon),
          shortcut: formatShortcut(['Mod', ',']),
          view: { type: 'settings' },
        });
      }
      for (const list of matchedLists) {
        items.push({ kind: 'nav', label: list.name, icon: list.icon ?? createElement(ClipboardIcon), view: { type: 'list', listId: list.id } });
      }
      for (const list of matchedLists.slice(0, 5)) {
        items.push({
          kind: 'action',
          label: `${t('palette.addToList')} "${trimmedQuery}" \u2192 ${list.name}`,
          icon: createElement(PlusIcon),
          action: () => runPaletteMutation(() => quickCapture({ title: trimmedQuery, listId: list.id }), 'quick-capture-list'),
        });
      }
      for (const list of matchedLists.slice(0, 3)) {
        // delete opens the shared confirm() modal; no
        // inline armed state is needed anymore.
        items.push({
          kind: 'action',
          label: `${t('palette.deleteList')}: ${list.name}`,
          icon: createElement(TrashIcon),
          action: () => deleteListFromPalette(list.id),
        });
      }
      for (const task of searchResults) {
        items.push({ kind: 'task', task });
      }
      // surface matching system actions during live search so a
      // user typing "export" sees the Export Data entry inline with
      // the task results.
      for (const item of systemActions.items) {
        items.push(item);
      }
      if (trimmedQuery.length >= 1 && items.length === 0) {
        items.push(createNoResultCreateTaskItem({
          onClose,
          onQuickCapture,
          query: trimmedQuery,
          t,
        }));
      }
    }

    return items;
  }, [
    shelveListFromPalette,
    confirmArchiveListId,
    createListFromPalette,
    deleteListFromPalette,
    frequentTasks,
    lists,
    moveTask,
    navItems,
    onClose,
    onQuickCapture,
    onSelectTask,
    query,
    recentActivations,
    recentUndoTokens,
    runPaletteMutation,
    searchResults,
    sectionOverrides,
    systemActions.items,
    t,
    format,
  ]);

  const keyedResults = useMemo<KeyedResult[]>(() => {
    const duplicateCountByKey = new Map<string, number>();
    return results.map((item) => {
      const baseKey = resultIdentity(item);
      const duplicateIdx = duplicateCountByKey.get(baseKey) ?? 0;
      duplicateCountByKey.set(baseKey, duplicateIdx + 1);
      const section = sectionOverrides.get(item);
      return {
        key: `${baseKey}#${duplicateIdx}`,
        item,
        ...(section !== undefined ? { section } : {}),
      };
    });
  }, [results, sectionOverrides]);

  return { keyedResults, results };
}
