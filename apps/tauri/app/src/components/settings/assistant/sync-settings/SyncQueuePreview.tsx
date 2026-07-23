import { useI18n } from '@/lib/i18n';
import type { AssistantSyncSettingsModel } from '../types';

interface SyncQueuePreviewProps {
  sync: AssistantSyncSettingsModel;
}

export function SyncQueuePreview({ sync }: SyncQueuePreviewProps) {
  const { t } = useI18n();
  const { syncPendingPreview, syncStatusError } = sync;

  return (
    <>
      <div className="bg-surface-2/60 border border-surface-3 rounded-r-card p-3.5 space-y-1.5">
        <p className="text-xs text-text-muted font-medium">{t('settings.syncPendingPreview')}</p>
        {syncPendingPreview.length === 0 ? (
          <p className="text-xs text-text-muted">{t('settings.syncNoPendingPreview')}</p>
        ) : (
          <div className="space-y-1">
            {syncPendingPreview.map((event) => (
              <p key={event.id} className="text-xs text-text-secondary font-mono break-all">
                {event.entity_type}:{event.operation} {event.entity_id}
              </p>
            ))}
          </div>
        )}
      </div>

      {syncStatusError && (
        <p className="text-xs text-danger">
          {t('settings.syncStatusLoadFailed')}: {syncStatusError}
        </p>
      )}
    </>
  );
}
