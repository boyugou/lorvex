import {
  useEffect,
  type RefObject,
} from 'react';

import { reportClientError } from '@/lib/errors/errorLogging';
import type { SyncBackendConfigs } from '@/lib/syncBackend/model';
import type { SyncBackendKind } from '@/lib/syncBackend/kinds';
import type { SyncBackendSaveState } from './types';
import {
  cleanupAssistantSyncAutosaveReset,
  createBrowserAssistantSyncAutosaveTimerHost,
  installAssistantSyncAutosaveRuntime,
  runAssistantSyncAutosaveTick,
  type AssistantSyncAutosaveTimerHandle,
} from './autosave.runtime';

const assistantSyncAutosaveTimerHost = createBrowserAssistantSyncAutosaveTimerHost();

interface UseAssistantSyncAutosaveArgs {
  ready: boolean;
  saveSyncBackend: (notify: boolean) => Promise<void>;
  setSyncBackendSaveState: (value: SyncBackendSaveState) => void;
  settingsMountedRef: RefObject<boolean>;
  syncBackendAutosaveReadyRef: RefObject<boolean>;
  syncBackendAutosaveResetTimerRef: RefObject<AssistantSyncAutosaveTimerHandle | null>;
  syncBackendSaveSeqRef: RefObject<number>;
  syncEnabled: boolean;
  syncBackendConfigs: SyncBackendConfigs;
  configuredSyncBackendKind: SyncBackendKind | null;
}

export function useAssistantSyncAutosave({
  ready,
  saveSyncBackend,
  setSyncBackendSaveState,
  settingsMountedRef,
  syncBackendAutosaveReadyRef,
  syncBackendAutosaveResetTimerRef,
  syncBackendSaveSeqRef,
  syncEnabled,
  syncBackendConfigs,
  configuredSyncBackendKind,
}: UseAssistantSyncAutosaveArgs): void {
  useEffect(() => {
    if (!ready) return;
    if (!syncBackendAutosaveReadyRef.current) {
      syncBackendAutosaveReadyRef.current = true;
      return;
    }
    cleanupAssistantSyncAutosaveReset(
      syncBackendAutosaveResetTimerRef,
      assistantSyncAutosaveTimerHost,
    );

    setSyncBackendSaveState('saving');
    const seq = syncBackendSaveSeqRef.current + 1;
    syncBackendSaveSeqRef.current = seq;
    return installAssistantSyncAutosaveRuntime({
      delayMs: 250,
      onTick: () => {
        runAssistantSyncAutosaveTick({
          isCurrent: () => seq === syncBackendSaveSeqRef.current,
          isMounted: () => settingsMountedRef.current,
          reportSaveError: (error) => {
            reportClientError('settings.syncAutosave', 'Sync backend autosave failed', error, undefined, 'warn');
          },
          resetDelayMs: 1200,
          resetTimerRef: syncBackendAutosaveResetTimerRef,
          save: () => saveSyncBackend(false),
          setSaveState: setSyncBackendSaveState,
          timerHost: assistantSyncAutosaveTimerHost,
        });
      },
      timerHost: assistantSyncAutosaveTimerHost,
    });
  }, [
    ready,
    saveSyncBackend,
    setSyncBackendSaveState,
    settingsMountedRef,
    syncBackendAutosaveReadyRef,
    syncBackendAutosaveResetTimerRef,
    syncBackendSaveSeqRef,
    syncEnabled,
    syncBackendConfigs.filesystem_bridge.rootPath,
    configuredSyncBackendKind,
  ]);

  useEffect(() => {
    return () => {
      cleanupAssistantSyncAutosaveReset(
        syncBackendAutosaveResetTimerRef,
        assistantSyncAutosaveTimerHost,
      );
    };
  }, [syncBackendAutosaveResetTimerRef]);
}
