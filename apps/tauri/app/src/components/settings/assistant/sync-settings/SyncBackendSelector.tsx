import { InfoRow } from '@/components/settings/SettingsPrimitives';
import { useI18n } from '@/lib/i18n';
import type { SyncStatus } from '@/lib/ipc/sync';
import type { SyncBackendKind } from '@/lib/syncBackend/kinds';
import type { SyncBackendDescriptor } from '@/lib/syncBackend/model';
import { syncBackendDescription, syncBackendLabel } from './backendLabels';

interface SyncBackendSelectorProps {
  draftSyncBackendKind: SyncBackendKind | null;
  runtimeConfiguredSyncBackendKind: SyncBackendKind | null;
  runtimeEffectiveSyncBackendKind: SyncBackendKind | null;
  availableSyncBackendDescriptors: SyncBackendDescriptor[];
  syncStatus: SyncStatus | null;
  onSelectSyncBackend: (backendKind: SyncBackendKind) => void;
}

export function SyncBackendSelector({
  draftSyncBackendKind,
  runtimeConfiguredSyncBackendKind,
  runtimeEffectiveSyncBackendKind,
  availableSyncBackendDescriptors,
  syncStatus,
  onSelectSyncBackend,
}: SyncBackendSelectorProps) {
  const { t } = useI18n();
  const label = (backendKind: SyncBackendKind): string => syncBackendLabel(backendKind, t);

  return (
    <>
      {availableSyncBackendDescriptors.length > 1 && (
        <div className="space-y-1.5">
          <p className="text-xs text-text-secondary font-medium">{t('settings.syncMethod')}</p>
          <div className="flex flex-wrap gap-2">
            {availableSyncBackendDescriptors.map((descriptor) => (
              <button
                key={descriptor.kind}
                type="button"
                onClick={() => onSelectSyncBackend(descriptor.kind)}
                className={`text-xs px-2.5 py-1.5 rounded-r-control border focus-ring-soft ${
                  draftSyncBackendKind === descriptor.kind
                    ? 'bg-[var(--accent-tint-sm)] border-accent/40 text-accent'
                    : 'bg-surface-1 border-surface-3 text-text-secondary hover:bg-surface-3'
                }`}
              >
                {label(descriptor.kind)}
              </button>
            ))}
          </div>
          {draftSyncBackendKind && (
            <p className="text-xs text-text-muted leading-relaxed">
              {syncBackendDescription(draftSyncBackendKind, t)}
            </p>
          )}
        </div>
      )}

      <div className="space-y-1">
        <InfoRow
          label={t('settings.syncMethod')}
          value={draftSyncBackendKind ? label(draftSyncBackendKind) : t('settings.syncBackendStatusDefault')}
        />
        <InfoRow
          label={t('settings.syncBackendConfigured')}
          value={runtimeConfiguredSyncBackendKind ? label(runtimeConfiguredSyncBackendKind) : t('settings.syncBackendStatusDefault')}
        />
        <InfoRow
          label={t('settings.syncBackendEffective')}
          value={runtimeEffectiveSyncBackendKind ? label(runtimeEffectiveSyncBackendKind) : t('settings.syncUnknown')}
        />
        {syncStatus?.sync_backend_kind_malformed && (
          <InfoRow
            label={t('settings.syncBackendMalformed')}
            value={syncStatus.sync_backend_kind_malformed_reason ?? t('settings.syncYes')}
          />
        )}
      </div>
    </>
  );
}
