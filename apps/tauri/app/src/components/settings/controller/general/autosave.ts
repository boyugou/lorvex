import { useCallback, useEffect, useRef, useState } from 'react';

import { toast } from '@/lib/notifications/toast';
import {
  cleanupGeneralSettingsAutosaveReset,
  createBrowserGeneralSettingsAutosaveTimerHost,
  installGeneralSettingsAutosaveRuntime,
  runGeneralSettingsAutosaveTick,
  type GeneralSettingsAutosaveState,
  type GeneralSettingsAutosaveTimerHandle,
} from './autosave.runtime';

const generalSettingsAutosaveTimerHost = createBrowserGeneralSettingsAutosaveTimerHost();

interface UseGeneralSettingsAutosaveArgs {
  logSettingsError: (source: string, message: string, error: unknown) => void;
  persistAdvanced: () => Promise<void>;
  persistWorkingHours: () => Promise<void>;
  ready: boolean;
  t: (key: 'common.error') => string;
}

export function useGeneralSettingsAutosave({
  logSettingsError,
  persistAdvanced,
  persistWorkingHours,
  ready,
  t,
}: UseGeneralSettingsAutosaveArgs): {
  autosaveState: GeneralSettingsAutosaveState;
} {
  const [autosaveState, setAutosaveState] = useState<GeneralSettingsAutosaveState>('idle');
  const autosaveResetTimerRef = useRef<GeneralSettingsAutosaveTimerHandle | null>(null);

  // Skip the first fire of each autosave effect after bootstrap completes.
  // On mount, bootstrap loads saved values and sets ready=true, which changes
  // the persist callback identities and would trigger a spurious save.
  const workingHoursBaselineRef = useRef(false);
  const advancedBaselineRef = useRef(false);

  const runAutosave = useCallback(async (action: () => Promise<void>) => {
    cleanupGeneralSettingsAutosaveReset(
      autosaveResetTimerRef,
      generalSettingsAutosaveTimerHost,
    );
    setAutosaveState('saving');
    runGeneralSettingsAutosaveTick({
      action,
      reportSaveError: (error) => {
        logSettingsError('frontend.settings.autosave', 'Settings autosave failed', error);
        toast.errorWithDetail(error, t('common.error'));
      },
      resetDelayMs: 1400,
      resetTimerRef: autosaveResetTimerRef,
      setAutosaveState,
      timerHost: generalSettingsAutosaveTimerHost,
    });
  }, [logSettingsError, t]);

  useEffect(() => {
    if (!ready) return;
    if (!workingHoursBaselineRef.current) {
      workingHoursBaselineRef.current = true;
      return;
    }
    setAutosaveState('saving');
    return installGeneralSettingsAutosaveRuntime({
      delayMs: 250,
      onTick: () => {
        void runAutosave(persistWorkingHours);
      },
      timerHost: generalSettingsAutosaveTimerHost,
    });
  }, [persistWorkingHours, ready, runAutosave]);

  useEffect(() => {
    if (!ready) return;
    if (!advancedBaselineRef.current) {
      advancedBaselineRef.current = true;
      return;
    }
    setAutosaveState('saving');
    return installGeneralSettingsAutosaveRuntime({
      delayMs: 300,
      onTick: () => {
        void runAutosave(persistAdvanced);
      },
      timerHost: generalSettingsAutosaveTimerHost,
    });
  }, [persistAdvanced, ready, runAutosave]);

  useEffect(() => {
    return () => {
      cleanupGeneralSettingsAutosaveReset(
        autosaveResetTimerRef,
        generalSettingsAutosaveTimerHost,
      );
    };
  }, []);

  return { autosaveState };
}
