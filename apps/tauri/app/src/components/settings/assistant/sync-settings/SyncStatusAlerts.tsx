import { useMemo } from 'react';

import { buildSyncErrorPresentation } from '@/components/settings/controller/assistant/sync/actions/errorToast';
import { Banner } from '@/components/ui/Banner';
import { Button } from '@/components/ui/Button';
import { useI18n } from '@/lib/i18n';
import type { SyncStatus } from '@/lib/ipc/sync';
import type { SyncErrorEnvelope } from '@/lib/syncBackend/errorKind';

interface SyncStatusAlertsProps {
  lastSyncErrorEnvelope: SyncErrorEnvelope | null;
  syncStatus: SyncStatus | null;
  syncBackendSaveState: 'idle' | 'saving' | 'saved' | 'error';
  onRetrySaveSyncBackend: () => void;
  onRunSyncNow: () => Promise<void>;
}

export function SyncStatusAlerts({
  lastSyncErrorEnvelope,
  syncStatus,
  syncBackendSaveState,
  onRetrySaveSyncBackend,
  onRunSyncNow,
}: SyncStatusAlertsProps) {
  const { t, format } = useI18n();
  const errorPresentation = useMemo(() => {
    if (!lastSyncErrorEnvelope || lastSyncErrorEnvelope.kind === 'unknown') {
      return null;
    }
    return buildSyncErrorPresentation({
      envelope: lastSyncErrorEnvelope,
      t,
      format,
      retry: () => {
        void onRunSyncNow();
      },
    });
  }, [lastSyncErrorEnvelope, onRunSyncNow, t, format]);

  return (
    <>
      {errorPresentation && (
        <Banner
          tone="danger"
          actions={
            errorPresentation.action ? (
              <Button
                variant="outline"
                onClick={errorPresentation.action.onClick}
                className="shrink-0"
              >
                {errorPresentation.action.label}
              </Button>
            ) : undefined
          }
        >
          {errorPresentation.message}
        </Banner>
      )}

      {syncStatus?.reseed_required && (
        <Banner tone="danger" title={t('settings.syncReseedRequired')}>
          {t('settings.syncReseedRequiredHint')}
        </Banner>
      )}

      {syncBackendSaveState === 'error' && (
        <div className="flex items-center gap-2">
          <span className="text-xs text-danger">{t('settings.autosaveError')}</span>
          <Button
            variant="outline"
            onClick={onRetrySaveSyncBackend}
          >
            {t('settings.syncRetrySave')}
          </Button>
        </div>
      )}
    </>
  );
}
