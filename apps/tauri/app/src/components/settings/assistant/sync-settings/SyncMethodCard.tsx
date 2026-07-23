import { useId, useState } from 'react';

import { buildSyncStatusLine } from '@/components/settings/controller/assistant/sync/presentation';
import { Toggle } from '@/components/ui/Toggle';
import { useI18n } from '@/lib/i18n';
import type { SyncBackendKind } from '@/lib/syncBackend/kinds';
import type { AssistantSyncSettingsModel } from '../types';
import { resolveSyncSettingsBackendContext } from './backendContext';
import { syncBackendLabel } from './backendLabels';
import { FilesystemBridgePathEditor } from './FilesystemBridgePathEditor';
import { LastSyncSummary } from './LastSyncSummary';
import { SeedFullSyncControl } from './SeedFullSyncControl';
import { SyncBackendSelector } from './SyncBackendSelector';
import { SyncProgressStatus } from './SyncProgressStatus';
import { SyncRunControls } from './SyncRunControls';
import { SyncStatusAlerts } from './SyncStatusAlerts';

interface SyncMethodCardProps {
  sync: AssistantSyncSettingsModel;
}

export function SyncMethodCard({ sync }: SyncMethodCardProps) {
  const { t } = useI18n();
  const {
    draftSyncBackendKind,
    runtimeConfiguredSyncBackendKind,
    runtimeEffectiveSyncBackendKind,
    availableSyncBackendDescriptors,
    syncBackendConfigs,
    syncEnabled,
    defaultFilesystemBridgeRootPath,
    syncBackendSaveState,
    syncRunning,
    lastSyncRunResult,
    syncLastRunAt,
    syncStatus,
    lastSyncErrorEnvelope,
    formatSyncTimestamp,
    onRefreshSyncStatus,
    onSelectSyncBackend,
    onSyncEnabledChange,
    onFilesystemBridgeRootPathChange,
    onUseDefaultFilesystemBridgeRootPath,
    onRetrySaveSyncBackend,
    onRunSyncNow,
    onSeedFullSync,
    seedSyncRunning,
  } = sync;
  const [advancedOpen, setAdvancedOpen] = useState(false);
  const advancedPanelId = useId();

  const hasAvailableSyncBackends = availableSyncBackendDescriptors.length > 0;
  const advancedBackendContext = resolveSyncSettingsBackendContext({
    draftConfiguredBackendKind: draftSyncBackendKind,
  });
  const showFilesystemRootPathEditor = advancedBackendContext.usesFilesystemRootPathEditor;

  const statusLine = buildSyncStatusLine(
    {
      hasAvailableSyncBackends,
      syncEnabled,
      syncRunning,
      seedSyncRunning,
      syncLastRunAt,
      syncStatus,
    },
    t,
  );
  const backendLabel = (backendKind: SyncBackendKind): string => syncBackendLabel(backendKind, t);
  const backendSummary = (() => {
    if (runtimeEffectiveSyncBackendKind === null) {
      return t('settings.syncNotAvailableOnDevice');
    }
    if (syncStatus?.sync_backend_kind_malformed) {
      return `${t('settings.syncBackendStatusMalformed')}: ${backendLabel(runtimeEffectiveSyncBackendKind)}`;
    }
    if (runtimeConfiguredSyncBackendKind === null) {
      return `${t('settings.syncBackendStatusDefault')}: ${backendLabel(runtimeEffectiveSyncBackendKind)}`;
    }
    if (runtimeConfiguredSyncBackendKind !== runtimeEffectiveSyncBackendKind) {
      return `${t('settings.syncBackendStatusFallback')}: ${backendLabel(runtimeEffectiveSyncBackendKind)}`;
    }
    return `${t('settings.syncBackendStatusSelected')}: ${backendLabel(runtimeEffectiveSyncBackendKind)}`;
  })();

  return (
    <div className="bg-surface-2/60 border border-surface-3 rounded-r-card p-3.5 space-y-3">
      <div className="flex items-center justify-between gap-3">
        <div>
          <p className="text-sm text-text-primary font-medium">{t('settings.sync')}</p>
          <p className="text-xs text-text-muted mt-0.5">{backendSummary}</p>
        </div>
        <Toggle
          checked={syncEnabled}
          onChange={onSyncEnabledChange}
          disabled={!hasAvailableSyncBackends}
          ariaLabel={t('settings.sync')}
        />
      </div>

      <p
        className={`text-xs ${statusLine.className}`}
        aria-live={statusLine.ariaLive}
        aria-atomic="true"
      >
        {statusLine.text}
      </p>

      <SyncProgressStatus
        syncRunning={syncRunning}
        seedSyncRunning={seedSyncRunning}
      />

      <SyncStatusAlerts
        lastSyncErrorEnvelope={lastSyncErrorEnvelope}
        syncStatus={syncStatus}
        syncBackendSaveState={syncBackendSaveState}
        onRetrySaveSyncBackend={onRetrySaveSyncBackend}
        onRunSyncNow={onRunSyncNow}
      />

      <SyncRunControls
        syncEnabled={syncEnabled}
        hasAvailableSyncBackends={hasAvailableSyncBackends}
        syncRunning={syncRunning}
        seedSyncRunning={seedSyncRunning}
        runtimeEffectiveSyncBackendKind={runtimeEffectiveSyncBackendKind}
        onRunSyncNow={onRunSyncNow}
      />

      {syncEnabled && hasAvailableSyncBackends && (
        <>
          <button
            type="button"
            onClick={() => setAdvancedOpen((prev) => !prev)}
            aria-expanded={advancedOpen}
            aria-controls={advancedPanelId}
            className="flex items-center gap-1.5 text-xs text-text-muted hover:text-text-secondary transition-colors focus-ring-soft rounded-r-control"
          >
            <span className={`inline-block transition-transform text-[9px] ${advancedOpen ? 'rotate-90' : ''}`}>&#9654;</span>
            {t('settings.advanced')}
          </button>

          <div
            id={advancedPanelId}
            hidden={!advancedOpen}
            className="space-y-3 ps-3 border-s-2 border-card"
          >
            {advancedOpen && (
              <>
                <SyncBackendSelector
                  draftSyncBackendKind={draftSyncBackendKind}
                  runtimeConfiguredSyncBackendKind={runtimeConfiguredSyncBackendKind}
                  runtimeEffectiveSyncBackendKind={runtimeEffectiveSyncBackendKind}
                  availableSyncBackendDescriptors={availableSyncBackendDescriptors}
                  syncStatus={syncStatus}
                  onSelectSyncBackend={onSelectSyncBackend}
                />

                {showFilesystemRootPathEditor && (
                  <FilesystemBridgePathEditor
                    rootPath={syncBackendConfigs.filesystem_bridge.rootPath}
                    defaultFilesystemBridgeRootPath={defaultFilesystemBridgeRootPath}
                    onFilesystemBridgeRootPathChange={onFilesystemBridgeRootPathChange}
                    onUseDefaultFilesystemBridgeRootPath={onUseDefaultFilesystemBridgeRootPath}
                  />
                )}

                <SeedFullSyncControl
                  syncRunning={syncRunning}
                  seedSyncRunning={seedSyncRunning}
                  onSeedFullSync={onSeedFullSync}
                />

                <LastSyncSummary
                  lastSyncRunResult={lastSyncRunResult}
                  syncLastRunAt={syncLastRunAt}
                  formatSyncTimestamp={formatSyncTimestamp}
                />

                <button
                  type="button"
                  onClick={() => { void onRefreshSyncStatus(); }}
                  className="text-xs text-text-muted hover:text-text-secondary"
                >
                  {t('settings.syncRefresh')}
                </button>
              </>
            )}
          </div>
        </>
      )}
    </div>
  );
}
