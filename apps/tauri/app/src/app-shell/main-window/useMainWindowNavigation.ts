import { useCallback, useEffect, useMemo, useState } from 'react';

import { usePreference } from '@/lib/query/usePreference';
import { REFETCH_INTERVAL } from '@/lib/query/timing';
import type { DeepLinkTarget } from '@/lib/ipc/runtime';
import { PREF_SIDEBAR_VISIBLE_MODULES } from '@/lib/preferences/keys';
import { parseSidebarVisibleModulesPreference, type SidebarModule } from '@/lib/sidebarModules';
import type { View } from '@/lib/types';
import {
  areViewsEqual,
  mapViewToSidebarModule,
} from '../support';

import type { ListsData, QuickCaptureInitialData } from './types';

interface MainWindowNavigationOptions {
  usesMobileLayout: boolean;
  lists: ListsData;
  openQuickCapture: (data?: QuickCaptureInitialData) => void;
}

export function useMainWindowNavigation({
  usesMobileLayout,
  lists,
  openQuickCapture,
}: MainWindowNavigationOptions) {
  const [view, setView] = useState<View>({ type: 'today' });
  const [selectedTaskId, setSelectedTaskId] = useState<string | null>(null);
  const [mobileListId, setMobileListId] = useState<string | null>(null);

  const { value: sidebarVisibleModules } = usePreference(
    PREF_SIDEBAR_VISIBLE_MODULES,
    parseSidebarVisibleModulesPreference,
    {
      staleTime: 0,
      enabled: !usesMobileLayout,
      refetchInterval: REFETCH_INTERVAL,
    },
  );

  const visibleSidebarModules = useMemo(
    () => new Set<SidebarModule>(sidebarVisibleModules),
    [sidebarVisibleModules],
  );

  const resolveGuardedView = useCallback((target: View): View => {
    if (!usesMobileLayout) {
      const requiredModule = mapViewToSidebarModule(target);
      if (requiredModule && !visibleSidebarModules.has(requiredModule)) {
        return { type: 'today' };
      }
    }

    return target;
  }, [usesMobileLayout, visibleSidebarModules]);

  const navigateToView = useCallback((target: View): View => {
    const resolved = resolveGuardedView(target);
    setView((prev) => (areViewsEqual(prev, resolved) ? prev : resolved));
    return resolved;
  }, [resolveGuardedView]);

  const handleSidebarNavigate = useCallback((target: View) => {
    navigateToView(target);
    setSelectedTaskId(null);
  }, [navigateToView]);

  const applyDeepLinkTarget = useCallback((target: DeepLinkTarget | null) => {
    if (!target) return;

    if (target.route === 'task') {
      const taskId = typeof target.task_id === 'string' ? target.task_id : null;
      navigateToView({ type: 'today' });
      if (taskId === null) {
        setSelectedTaskId(null);
        return;
      }
      setSelectedTaskId(taskId);
      return;
    }

    if (target.route === 'quick_capture') {
      setSelectedTaskId(null);
      openQuickCapture();
      return;
    }

    if (target.route === 'today') {
      navigateToView({ type: 'today' });
      setSelectedTaskId(null);
      return;
    }

    if (target.route === 'search') {
      setSelectedTaskId(null);
      const q = target.params?.q;
      navigateToView(q ? { type: 'all_tasks', initialSearch: q } : { type: 'all_tasks' });
      return;
    }

    if (target.route === 'add_task') {
      // Security: open quick capture for user review instead of silently creating.
      // The user can review and submit manually. Pre-fill from deep link params.
      const params = target.params;
      openQuickCapture(params ? {
        title: params.title,
        list: params.list,
        due: params.due,
        priority: params.priority ? Number(params.priority) : undefined,
      } : undefined);
      return;
    }

    if (target.route === 'complete_task') {
      const taskId = typeof target.task_id === 'string' ? target.task_id : null;
      if (!taskId) return;

      // Security: navigate to the task instead of auto-completing.
      // The user can review the task and complete it manually.
      navigateToView({ type: 'today' });
      setSelectedTaskId(taskId);
    }
  }, [navigateToView, openQuickCapture]);

  useEffect(() => {
    if (!usesMobileLayout) return;
    if (view.type === 'list') {
      setMobileListId(view.listId);
    }
  }, [usesMobileLayout, view]);

  useEffect(() => {
    if (!usesMobileLayout) return;
    if (mobileListId === null && lists.length > 0) {
      setMobileListId(lists[0]!.id);
    }
  }, [usesMobileLayout, lists, mobileListId]);

  useEffect(() => {
    if (view.type !== 'list') return;
    const listExists = lists.some((list) => list.id === view.listId);
    if (listExists) return;
    setSelectedTaskId(null);
    if (usesMobileLayout) {
      const fallbackListId = (mobileListId !== null && lists.some((list) => list.id === mobileListId))
        ? mobileListId
        : lists[0]?.id;
      if (fallbackListId !== undefined) {
        setMobileListId(fallbackListId);
        navigateToView({ type: 'list', listId: fallbackListId });
      } else {
        navigateToView({ type: 'today' });
      }
      return;
    }
    navigateToView({ type: 'today' });
  }, [usesMobileLayout, lists, mobileListId, navigateToView, view]);

  useEffect(() => {
    const resolved = resolveGuardedView(view);
    if (areViewsEqual(resolved, view)) return;
    setSelectedTaskId(null);
    setView(resolved);
  }, [resolveGuardedView, view]);

  const openMobileLists = useCallback(() => {
    const targetListId = mobileListId ?? lists[0]?.id;
    if (targetListId === undefined) {
      navigateToView({ type: 'today' });
      return;
    }
    setMobileListId(targetListId);
    navigateToView({ type: 'list', listId: targetListId });
    setSelectedTaskId(null);
  }, [lists, mobileListId, navigateToView]);

  const selectMobileList = useCallback((listId: string) => {
    setMobileListId(listId);
    navigateToView({ type: 'list', listId });
    setSelectedTaskId(null);
  }, [navigateToView]);

  return {
    applyDeepLinkTarget,
    handleSidebarNavigate,
    mobileListId,
    navigateToView,
    openMobileLists,
    selectMobileList,
    selectedTaskId,
    setSelectedTaskId,
    view,
    visibleSidebarModules,
  };
}
