import { useCallback } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import { useI18n } from '@/lib/i18n';
import type { RuntimeProfile } from '@/lib/platform/platform';
import { useTheme } from '@/lib/theme';

import type { MainWindowController, QuickCaptureInitialData } from './types';
import { useAssistantUiRuntime } from './runtime/useAssistantUiRuntime';
import { useBackgroundMaintenance } from './runtime/useBackgroundMaintenance';
import { useMainWindowShortcuts } from './runtime/useMainWindowShortcuts';
import { useMainWindowSubscriptions } from './runtime/useMainWindowSubscriptions';
import { useMenuEvents } from './runtime/useMenuEvents';
import { useShellEventToasts } from '@/lib/sync/useShellEventToasts';
import { useMainWindowActions } from './useMainWindowActions';
import { useMainWindowNavigation } from './useMainWindowNavigation';
import { useMainWindowQueries } from './useMainWindowQueries';
import { useMobileTitle } from './useMobileTitle';
import { useOverlaySession } from './useOverlaySession';
import { useUiViewStatePersistence } from './useUiViewStatePersistence';

export function useMainWindowController(runtimeProfile: RuntimeProfile): MainWindowController {
  const usesMobileLayout = runtimeProfile.runtimeClass === 'mobile';
  const qc = useQueryClient();
  const { setLocale, applySystemLocale } = useI18n();
  const { setMode, setAppearanceProfile } = useTheme();

  const commandPalette = useOverlaySession();
  const quickCapture = useOverlaySession<QuickCaptureInitialData>();

  const {
    startMainWindowDragging,
    toggleMainWindowZoom,
  } = useMainWindowActions(usesMobileLayout);

  const { isOverviewError, lists, overview, refetchOverview } = useMainWindowQueries();

  const {
    applyDeepLinkTarget,
    handleSidebarNavigate,
    mobileListId,
    navigateToView,
    openMobileLists,
    selectMobileList,
    selectedTaskId,
    setSelectedTaskId,
    view,
  } = useMainWindowNavigation({
    usesMobileLayout,
    lists,
    openQuickCapture: quickCapture.open,
  });

  // Wrap openQuickCapture to auto-inject current list context when on a list view
  // Depend on the stable `.open` handler only — the `quickCapture`
  // object literal is a fresh reference each render but `.open` is
  // identity-stable across renders.
  const openQuickCaptureWithContext = useCallback((data?: QuickCaptureInitialData) => {
    if (data) {
      quickCapture.open(data);
    } else if (view.type === 'list') {
      quickCapture.open({ list: view.listId });
    } else {
      quickCapture.open();
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [quickCapture.open, view]);

  useBackgroundMaintenance({
    monitorTimezone: true,
  });
  useAssistantUiRuntime({
    supportsAssistantCommandPolling: runtimeProfile.supportsAssistantCommandPolling,
    navigateToView,
    setAppearanceProfile,
    setLocale,
    setMode,
    setSelectedTaskId,
    applySystemLocale,
  });
  useMainWindowShortcuts({
    closeCommandPalette: commandPalette.close,
    usesMobileLayout,
    selectedTaskId,
    setSelectedTaskId,
    showCapture: quickCapture.visible,
    showPalette: commandPalette.visible,
  });
  useMenuEvents({
    closeCommandPalette: commandPalette.close,
    closeQuickCapture: quickCapture.close,
    navigateToView,
    openCommandPalette: commandPalette.open,
    openQuickCapture: openQuickCaptureWithContext,
    showCapture: quickCapture.visible,
    showPalette: commandPalette.visible,
  });
  useMainWindowSubscriptions({
    applyDeepLinkTarget,
    queryClient: qc,
  });
  // app-shell-level subscriber for backend-emitted toast channels
  // (sync-notice, data-reset-failed, notification-action-error).
  // Overlay windows must not duplicate these.
  useShellEventToasts();

  const mobileTitle = useMobileTitle(view, lists, mobileListId);

  // persist the current view and selected task into `device_state` so
  // the assistant (via the MCP `get_ui_view_state` tool) can see what
  // the user is actually looking at. Debounced at 500 ms inside the
  // hook; writes are local-only. The `get_ui_view_state` snapshot still
  // carries `focus_mode_active`/`focus_mode_task_id`; with focus mode
  // retired they are always the inactive form.
  useUiViewStatePersistence({
    view,
    selectedTaskId,
    focusModeActive: false,
    focusModeTaskId: null,
  });

  return {
    activeCommandPaletteSession: commandPalette.activeSession,
    activeQuickCaptureSession: quickCapture.activeSession,
    closeCommandPalette: commandPalette.close,
    closeQuickCapture: quickCapture.close,
    handleSidebarNavigate,
    isOverviewError,
    lists,
    mobileTitle,
    navigateToView,
    onRetryOverview: refetchOverview,
    onSelectTask: setSelectedTaskId,
    openCommandPalette: commandPalette.open,
    openMobileLists,
    openQuickCapture: openQuickCaptureWithContext,
    quickCaptureInitialData: quickCapture.data,
    overview,
    selectMobileList,
    selectedTaskId,
    setSelectedTaskId,
    showCapture: quickCapture.visible,
    showPalette: commandPalette.visible,
    startMainWindowDragging,
    toggleMainWindowZoom,
    usesMobileLayout,
    view,
  };
}
