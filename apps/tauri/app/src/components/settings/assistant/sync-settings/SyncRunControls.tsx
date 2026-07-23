import { useEffect, useRef, useState } from 'react';

import { Button } from '@/components/ui/Button';
import { TonalButton } from '@/components/ui/TonalButton';
import { reportClientError } from '@/lib/errors/errorLogging';
import { useI18n } from '@/lib/i18n';
import { cancelSync, type SyncKind } from '@/lib/ipc/sync';
import type { SyncBackendKind } from '@/lib/syncBackend/kinds';
import { useNetworkStatus } from '@/lib/useNetworkStatus';

interface SyncRunControlsProps {
  syncEnabled: boolean;
  hasAvailableSyncBackends: boolean;
  syncRunning: boolean;
  seedSyncRunning: boolean;
  runtimeEffectiveSyncBackendKind: SyncBackendKind | null;
  onRunSyncNow: () => Promise<void>;
}

function syncKindForBackend(backendKind: SyncBackendKind | null): SyncKind | null {
  if (backendKind === null) {
    return null;
  }
  return 'filesystem_bridge';
}

export function SyncRunControls({
  syncEnabled,
  hasAvailableSyncBackends,
  syncRunning,
  seedSyncRunning,
  runtimeEffectiveSyncBackendKind,
  onRunSyncNow,
}: SyncRunControlsProps) {
  const { t } = useI18n();
  const { online } = useNetworkStatus();
  const [cancelling, setCancelling] = useState(false);
  const [cancelDisabled, setCancelDisabled] = useState(false);
  const cancelDisableTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  useEffect(() => {
    return () => {
      if (cancelDisableTimerRef.current !== null) {
        clearTimeout(cancelDisableTimerRef.current);
      }
    };
  }, []);

  useEffect(() => {
    if (!syncRunning && !seedSyncRunning && cancelling) {
      setCancelling(false);
    }
  }, [syncRunning, seedSyncRunning, cancelling]);

  if (!syncEnabled || !hasAvailableSyncBackends) {
    return null;
  }

  const handleCancel = () => {
    const kind = syncKindForBackend(runtimeEffectiveSyncBackendKind);
    if (kind === null || cancelDisabled) return;

    setCancelling(true);
    setCancelDisabled(true);
    if (cancelDisableTimerRef.current !== null) {
      clearTimeout(cancelDisableTimerRef.current);
    }
    cancelDisableTimerRef.current = setTimeout(() => {
      setCancelDisabled(false);
      cancelDisableTimerRef.current = null;
    }, 500);
    void cancelSync(kind).catch((error: unknown) => {
      reportClientError(
        'settings.cancelSync',
        'cancel_sync IPC failed',
        error,
        `kind=${kind}`,
        'warn',
      );
    });
  };

  return (
    <div className="flex flex-wrap items-center gap-2">
      <TonalButton
        tone="accent"
        onClick={() => { void onRunSyncNow(); }}
        disabled={syncRunning || seedSyncRunning || !online}
        title={!online ? t('settings.syncOfflineHint') : undefined}
      >
        {syncRunning ? t('settings.syncRunning') : t('settings.syncNow')}
      </TonalButton>
      {(syncRunning || seedSyncRunning) && (
        <Button
          variant="outline"
          onClick={handleCancel}
          disabled={cancelDisabled}
        >
          {cancelling ? t('settings.syncCancelling') : t('settings.syncCancel')}
        </Button>
      )}
      {!online && (
        <span className="text-xs text-warning" role="status">
          {t('settings.syncOfflineHint')}
        </span>
      )}
    </div>
  );
}
