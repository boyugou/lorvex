import { openUrl } from '@tauri-apps/plugin-opener';
import { useQuery } from '@tanstack/react-query';
import { useCallback, useEffect, useMemo, useState } from 'react';

import { reportClientError } from '@/lib/errors/errorLogging';
import { useI18n } from '@/lib/i18n';
import { getUnseenErrorLogCount } from '@/lib/ipc/settings';
import { createList } from '@/lib/ipc/tasks/lists';
import type { ListWithCount, Stats } from '@/lib/ipc/tasks/models';
import { checkForUpdateCached } from '@/lib/checkForUpdateCached';
import { useNetworkStatus } from '@/lib/useNetworkStatus';
import { PREF_SIDEBAR_HIDE_EMPTY_LISTS, PREF_SIDEBAR_VISIBLE_MODULES } from '@/lib/preferences/keys';
import { QUERY_KEYS } from '@/lib/query/queryKeys';
import { REFETCH_INTERVAL } from '@/lib/query/timing';
import { defineEntityHooks } from '@/lib/query/defineEntityHooks';
import { usePreference } from '@/lib/query/usePreference';
import { parseBool } from '@/lib/query/usePreference.logic';
import { formatShortcut } from '@/lib/shortcuts';
import {
  isModuleInToolbox as isModuleInToolboxFn,
  isModuleVisible,
  parseSidebarModuleConfig,
  type SidebarModule,
} from '@/lib/sidebarModules';
import type { View } from '@/lib/types';

const RELEASES_URL = 'https://github.com/boyugou/ai-native-todo/releases';

const sidebarHooks = defineEntityHooks({
  entity: 'list',
  mutations: {
    createList: {
      run: (name: string) => createList({ name }),
      errorContext: 'sidebar.createList',
    },
  },
});

export interface SidebarProps {
  lists: ListWithCount[];
  stats: Stats | null;
  currentView: View;
  onNavigate: (view: View) => void;
  onQuickCapture: () => void;
  onOpenPalette?: () => void;
  onWindowDragStart?: () => void;
  usesMobileLayout?: boolean;
}

export interface SidebarControllerState extends SidebarProps {
  availableVersion: string | null;
  canShowModule: (module: SidebarModule) => boolean;
  creatingList: boolean;
  handleCreateList: (name: string) => void;
  handleOpenReleaseNotes: () => void;
  isCreatingList: boolean;
  isModuleInToolbox: (module: SidebarModule) => boolean;
  navShortcuts: {
    // Primary row (⌘1 – ⌘4)
    today: string;
    upcoming: string;
    allTasks: string;
    someday: string;
    // Secondary digit row (⌘5 – ⌘0)
    calendar: string;
    eisenhower: string;
    kanban: string;
    habits: string;
    dailyReview: string;
    // Secondary ⌘⇧-letter row
    memory: string;
    dependencies: string;
    changelog: string;
    review: string;
    recurring: string;
  };
  quickCaptureShortcut: string;
  setCreatingList: (v: boolean) => void;
  showDesktopFeatures: boolean;
  t: ReturnType<typeof useI18n>['t'];
  todayBadge: number | null;
  unseenErrorLogCount: number | null;
}

export function useSidebarController({
  usesMobileLayout = false,
  ...props
}: SidebarProps): SidebarControllerState {
  const { t } = useI18n();
  const [availableVersion, setAvailableVersion] = useState<string | null>(null);
  const showDesktopFeatures = !usesMobileLayout;
  // first-launch offline path. `checkForUpdateCached` already
  // short-circuits on `navigator.onLine === false`, but it still pays the
  // cost of awaiting `getVersion` and priming the cache promise. More
  // importantly, we want the effect to *re-run* when the browser flips back
  // to online so a user who launches offline and then reconnects still
  // picks up the update banner without needing to restart or remount the
  // sidebar. Observing `online` in the effect dep gives us that resume
  // path for free.
  const { online } = useNetworkStatus();
  const quickCaptureShortcut = formatShortcut(['Mod', 'N']);
  const navShortcuts = {
    // Primary row
    today: formatShortcut(['Mod', '1']),
    upcoming: formatShortcut(['Mod', '2']),
    allTasks: formatShortcut(['Mod', '3']),
    someday: formatShortcut(['Mod', '4']),
    // Secondary digit row
    calendar: formatShortcut(['Mod', '5']),
    eisenhower: formatShortcut(['Mod', '6']),
    kanban: formatShortcut(['Mod', '7']),
    habits: formatShortcut(['Mod', '8']),
    dailyReview: formatShortcut(['Mod', '9']),
    // Secondary ⌘⇧-letter row
    memory: formatShortcut(['Mod', 'Shift', 'M']),
    dependencies: formatShortcut(['Mod', 'Shift', 'D']),
    changelog: formatShortcut(['Mod', 'Shift', 'A']),
    review: formatShortcut(['Mod', 'Shift', 'W']),
    recurring: formatShortcut(['Mod', 'Shift', 'R']),
  };
  const { value: moduleConfig } = usePreference(
    PREF_SIDEBAR_VISIBLE_MODULES,
    parseSidebarModuleConfig,
    {
      // `staleTime: 0` forced an IPC round-trip on every
      // re-mount (sidebar collapse/expand, view-tree switch). The
      // refetchInterval already polls cross-process changes, so the
      // sidebar is safe to read from cache between ticks. Match the
      // poll cadence so the cache horizon equals the freshness
      // contract.
      staleTime: REFETCH_INTERVAL,
      enabled: showDesktopFeatures,
      refetchInterval: REFETCH_INTERVAL,
    },
  );
  const { value: hideEmptyLists } = usePreference(
    PREF_SIDEBAR_HIDE_EMPTY_LISTS,
    parseBool(false),
    {
      staleTime: REFETCH_INTERVAL,
      refetchInterval: REFETCH_INTERVAL,
    },
  );
  const todayBadge = props.stats ? props.stats.today_pool_count || null : null;
  const { data: unseenErrorLogCountData } = useQuery({
    queryKey: QUERY_KEYS.unseenErrorLogCount(),
    queryFn: ({ signal }) => getUnseenErrorLogCount(signal),
    enabled: showDesktopFeatures,
    staleTime: REFETCH_INTERVAL,
    refetchInterval: REFETCH_INTERVAL,
  });
  const unseenErrorLogCount =
    showDesktopFeatures && unseenErrorLogCountData && unseenErrorLogCountData > 0
      ? unseenErrorLogCountData
      : null;
  const canShowModule = useCallback(
    (module: SidebarModule): boolean => isModuleVisible(module, moduleConfig),
    [moduleConfig],
  );
  const isModuleInToolbox = useCallback(
    (module: SidebarModule): boolean => isModuleInToolboxFn(module, moduleConfig),
    [moduleConfig],
  );

  const filteredLists = useMemo(() => {
    if (!hideEmptyLists) return props.lists;
    return props.lists.filter((list) =>
      list.open_count > 0
      || (props.currentView.type === 'list' && props.currentView.listId === list.id),
    );
  }, [hideEmptyLists, props.lists, props.currentView]);

  useEffect(() => {
    if (!showDesktopFeatures) return;
    // skip the update probe entirely while offline.
    // `checkForUpdateCached` already returns `null` when
    // `navigator.onLine` is false, but gating here avoids the
    // `getVersion()` Tauri round-trip on the sidebar-mount path of a
    // first-launch-offline user and — more importantly — re-arms the
    // effect the moment the browser reports back online, so a user who
    // launches on a plane and then reconnects gets an update banner
    // without restarting. The `online` dep drives that resume.
    if (!online) return;
    let mounted = true;

    // cached + deduped. 6 h TTL in localStorage so
    // repeated sidebar mounts within a session share one network hit.
    checkForUpdateCached()
      .then((version) => {
        if (mounted) {
          setAvailableVersion(version);
        }
      })
      .catch((error: unknown) => {
        // The IPC's "no release published yet" path returns `null`
        // from `checkForUpdateCached` — it does NOT throw. A thrown
        // error here means something genuinely went wrong: DNS
        // failure, malformed updater feed, regression in the IPC
        // handler. Route through `reportClientError` at `warn`
        // severity — the absent banner is non-blocking so the user
        // doesn't need an alarming toast, but the breadcrumb has to
        // land in error_logs.
        reportClientError(
          'sidebar.checkForUpdate',
          'Failed to check for app update',
          error,
          undefined,
          'warn',
        );
      });

    return () => {
      mounted = false;
    };
  }, [showDesktopFeatures, online]);

  const handleOpenReleaseNotes = useCallback(() => {
    openUrl(RELEASES_URL).catch((error) => {
      reportClientError('sidebar.openReleaseNotes', 'Failed to open release notes', error);
    });
  }, []);

  const [creatingList, setCreatingList] = useState(false);
  // Entity-keyed `'list'` invalidation covers overview + lists +
  // today-surface + weeklyReview, which the sidebar already showed.
  const createListMutation = sidebarHooks.mutations.createList.useMutation({
    successMessage: t('list.createSuccess'),
    errorMessage: t('common.error'),
    onSuccess: (newList) => {
      setCreatingList(false);
      props.onNavigate({ type: 'list', listId: newList.id });
    },
  });

  const handleCreateList = useCallback((name: string) => {
    const trimmed = name.trim();
    if (!trimmed) {
      setCreatingList(false);
      return;
    }
    createListMutation.mutate(trimmed);
  }, [createListMutation]);

  return {
    ...props,
    lists: filteredLists,
    availableVersion,
    canShowModule,
    creatingList,
    handleCreateList,
    handleOpenReleaseNotes,
    isCreatingList: createListMutation.isPending,
    isModuleInToolbox,
    navShortcuts,
    quickCaptureShortcut,
    setCreatingList,
    showDesktopFeatures,
    t,
    todayBadge,
    unseenErrorLogCount,
    usesMobileLayout,
  };
}
