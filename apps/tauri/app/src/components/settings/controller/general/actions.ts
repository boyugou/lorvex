import { useCallback, useRef, useState, type Dispatch, type RefObject, type SetStateAction } from 'react';
import { useQueryClient } from '@tanstack/react-query';

import {
  DEFAULT_SIDEBAR_MODULE_CONFIG,
  cloneSidebarModuleConfig,
  getModuleState,
  isSidebarPrimaryModule,
  serializeSidebarModuleConfig,
  type SidebarModule,
  type SidebarModuleConfig,
  type SidebarModuleState,
  type SidebarPrimaryModule,
} from '@/lib/sidebarModules';
import { toast } from '@/lib/notifications/toast';
import { setPreferenceQueryData } from '@/lib/query/preferenceCache';
import { PREF_SIDEBAR_VISIBLE_MODULES } from '@/lib/preferences/keys';
import type { TranslationKey } from '@/locales';
import type { DesktopCloseActionPreference } from '@/components/settings/general/types';
import { saveSidebarModulesPreference } from './preferences';
import {
  persistAutostartPreference,
  persistMemoryLockPreference,
  persistTrayIconVisibility,
} from './runtime';

interface UseGeneralSettingsActionsArgs {
  autostart: boolean;
  logSettingsError: (source: string, message: string, error: unknown) => void;
  memoryLock: boolean;
  settingsMountedRef: RefObject<boolean>;
  setAutostart: Dispatch<SetStateAction<boolean>>;
  setDesktopCloseAction: Dispatch<SetStateAction<DesktopCloseActionPreference>>;
  setDesktopCloseActionDirty: Dispatch<SetStateAction<boolean>>;
  setMemoryLock: Dispatch<SetStateAction<boolean>>;
  setSidebarModuleConfig: Dispatch<SetStateAction<SidebarModuleConfig>>;
  setTrayIconVisible: Dispatch<SetStateAction<boolean>>;
  t: (key: TranslationKey) => string;
  trayIconRollbackKey: TranslationKey;
  trayIconVisible: boolean;
}

export function useGeneralSettingsActions({
  autostart,
  logSettingsError,
  memoryLock,
  settingsMountedRef,
  setAutostart,
  setDesktopCloseAction,
  setDesktopCloseActionDirty,
  setMemoryLock,
  setSidebarModuleConfig,
  setTrayIconVisible,
  t,
  trayIconRollbackKey,
  trayIconVisible,
}: UseGeneralSettingsActionsArgs): {
  autostartBusy: boolean;
  cycleSidebarModule: (moduleId: SidebarModule) => void;
  setSidebarModuleState: (moduleId: SidebarModule, state: SidebarModuleState) => void;
  handleAutostartToggle: (enabled: boolean) => Promise<void>;
  handleDesktopCloseActionChange: (next: DesktopCloseActionPreference) => void;
  handleMemoryLockToggle: (enabled: boolean) => Promise<void>;
  handleTrayIconToggle: (enabled: boolean) => Promise<void>;
  memoryLockBusy: boolean;
  resetSidebarModules: () => void;
  trayIconBusy: boolean;
} {
  const qc = useQueryClient();
  const [autostartBusy, setAutostartBusy] = useState(false);
  const [trayIconBusy, setTrayIconBusy] = useState(false);
  const [memoryLockBusy, setMemoryLockBusy] = useState(false);

  // dedup guard so a StrictMode-double-invoked functional
  // updater (or a React 19 concurrent replay) doesn't fire the IPC
  // mutation twice. Store the last serialized config; skip if identical.
  const lastPersistedRef = useRef<string | null>(null);
  const persistSidebarConfig = useCallback(async (
    config: SidebarModuleConfig,
    previousConfig: SidebarModuleConfig,
    notify = false,
  ) => {
    const signature = serializeSidebarModuleConfig(config);
    if (lastPersistedRef.current === signature) return;
    lastPersistedRef.current = signature;
    try {
      await saveSidebarModulesPreference({
        queryClient: qc,
        config,
      });
      if (notify) {
        toast.success(t('settings.sidebarModulesSaved'));
      }
    } catch (error) {
      logSettingsError('frontend.settings.sidebar.save', 'Save sidebar modules failed', error);
      setSidebarModuleConfig(previousConfig);
      setPreferenceQueryData(
        qc,
        PREF_SIDEBAR_VISIBLE_MODULES,
        serializeSidebarModuleConfig(previousConfig),
      );
      // Roll back the dedup signature too — the next retry for the
      // same config should actually hit the IPC.
      lastPersistedRef.current = serializeSidebarModuleConfig(previousConfig);
      toast.errorWithDetail(error, t('common.error'));
    }
  }, [logSettingsError, qc, setSidebarModuleConfig, t]);

  const cycleSidebarModule = useCallback((moduleId: SidebarModule) => {
    setSidebarModuleConfig((prev) => {
      const currentState = getModuleState(moduleId, prev);
      // Cycle: show -> more -> hidden -> show
      let nextState: 'show' | 'more' | 'hidden';
      if (currentState === 'show') nextState = 'more';
      else if (currentState === 'more') nextState = 'hidden';
      else nextState = 'show';

      // Guard: primary modules cannot be set to 'more' — they should always be 'show' or 'hidden'
      if (isSidebarPrimaryModule(moduleId) && nextState === 'more') {
        nextState = 'hidden';
      }

      // Guard: ensure at least one primary module remains in 'show'
      if (isSidebarPrimaryModule(moduleId) && nextState === 'hidden') {
        const otherPrimaryInShow = prev.show.filter(
          (m): m is SidebarPrimaryModule => m !== moduleId && isSidebarPrimaryModule(m),
        );
        if (otherPrimaryInShow.length < 1) {
          toast.info(t('settings.sidebarNeedOnePrimary'));
          return prev;
        }
      }

      // Build the new config by removing the module from its current list and adding to the new one
      const newShow = prev.show.filter((m) => m !== moduleId);
      const newMore = prev.more.filter((m) => m !== moduleId);
      if (nextState === 'show') newShow.push(moduleId);
      else if (nextState === 'more') newMore.push(moduleId);
      // 'hidden' = not in either list

      const next: SidebarModuleConfig = { show: newShow, more: newMore };
      void persistSidebarConfig(next, prev);
      return next;
    });
  }, [persistSidebarConfig, setSidebarModuleConfig, t]);

  const setSidebarModuleState = useCallback((moduleId: SidebarModule, targetState: SidebarModuleState) => {
    setSidebarModuleConfig((prev) => {
      const currentState = getModuleState(moduleId, prev);
      if (currentState === targetState) return prev;

      // Guard: primary modules cannot be set to 'more' — they should always be 'show' or 'hidden'
      let resolvedState = targetState;
      if (isSidebarPrimaryModule(moduleId) && resolvedState === 'more') {
        resolvedState = 'hidden';
      }

      // Guard: ensure at least one primary module remains in 'show'
      if (isSidebarPrimaryModule(moduleId) && resolvedState !== 'show') {
        const otherPrimaryInShow = prev.show.filter(
          (m): m is SidebarPrimaryModule => m !== moduleId && isSidebarPrimaryModule(m),
        );
        if (otherPrimaryInShow.length < 1) {
          toast.info(t('settings.sidebarNeedOnePrimary'));
          return prev;
        }
      }

      const newShow = prev.show.filter((m) => m !== moduleId);
      const newMore = prev.more.filter((m) => m !== moduleId);
      if (resolvedState === 'show') newShow.push(moduleId);
      else if (resolvedState === 'more') newMore.push(moduleId);

      const next: SidebarModuleConfig = { show: newShow, more: newMore };
      void persistSidebarConfig(next, prev);
      return next;
    });
  }, [persistSidebarConfig, setSidebarModuleConfig, t]);

  const resetSidebarModules = useCallback(() => {
    setSidebarModuleConfig((prev) => {
      const defaults = cloneSidebarModuleConfig(DEFAULT_SIDEBAR_MODULE_CONFIG);
      if (
        JSON.stringify(prev.show) === JSON.stringify(defaults.show) &&
        JSON.stringify(prev.more) === JSON.stringify(defaults.more)
      ) {
        return prev;
      }
      void persistSidebarConfig(defaults, prev, true);
      return defaults;
    });
  }, [persistSidebarConfig, setSidebarModuleConfig]);

  const handleAutostartToggle = useCallback(async (enabled: boolean) => {
    const previous = autostart;
    setAutostart(enabled);
    setAutostartBusy(true);
    try {
      await persistAutostartPreference(enabled);
      toast.success(t('settings.autosaveSaved'));
    } catch (error) {
      logSettingsError('frontend.settings.autostart.toggle', 'Autostart toggle failed', error);
      if (settingsMountedRef.current) {
        setAutostart(previous);
      }
      toast.errorWithDetail(error, t('common.error'));
    } finally {
      if (settingsMountedRef.current) {
        setAutostartBusy(false);
      }
    }
  }, [autostart, logSettingsError, setAutostart, settingsMountedRef, t]);

  const handleDesktopCloseActionChange = useCallback((next: DesktopCloseActionPreference) => {
    setDesktopCloseAction(next);
    setDesktopCloseActionDirty(true);
  }, [setDesktopCloseAction, setDesktopCloseActionDirty]);

  const handleTrayIconToggle = useCallback(async (enabled: boolean) => {
    const previous = trayIconVisible;
    setTrayIconVisible(enabled);
    setTrayIconBusy(true);
    try {
      await persistTrayIconVisibility({
        enabled,
        previous,
        logSettingsError,
      });
      toast.success(t('settings.autosaveSaved'));
    } catch (error) {
      if (settingsMountedRef.current) {
        setTrayIconVisible(previous);
      }
      // tray toggle wraps a Tauri tray-manager call that can
      // fail for platform-specific reasons (missing tray icon on Windows,
      // no notification-area on Linux). Route via errorWithDetail so the
      // underlying reason reaches the user along with the rollback copy.
      toast.errorWithDetail(error, t(trayIconRollbackKey));
    } finally {
      if (settingsMountedRef.current) {
        setTrayIconBusy(false);
      }
    }
  }, [logSettingsError, setTrayIconVisible, settingsMountedRef, t, trayIconRollbackKey, trayIconVisible]);

  const handleMemoryLockToggle = useCallback(async (enabled: boolean) => {
    const previous = memoryLock;
    setMemoryLock(enabled);
    setMemoryLockBusy(true);
    try {
      await persistMemoryLockPreference(enabled);
      toast.success(t('settings.autosaveSaved'));
    } catch (error) {
      logSettingsError('frontend.settings.memory_lock.toggle', 'Memory lock toggle failed', error);
      if (settingsMountedRef.current) {
        setMemoryLock(previous);
      }
      toast.errorWithDetail(error, t('common.error'));
    } finally {
      if (settingsMountedRef.current) {
        setMemoryLockBusy(false);
      }
    }
  }, [logSettingsError, memoryLock, setMemoryLock, settingsMountedRef, t]);

  return {
    autostartBusy,
    cycleSidebarModule,
    setSidebarModuleState,
    handleAutostartToggle,
    handleDesktopCloseActionChange,
    handleMemoryLockToggle,
    handleTrayIconToggle,
    memoryLockBusy,
    resetSidebarModules,
    trayIconBusy,
  };
}
