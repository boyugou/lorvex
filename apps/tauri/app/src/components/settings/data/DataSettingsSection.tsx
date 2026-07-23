import { useI18n } from '@/lib/i18n';
import type { DataSettingsController } from '../controller/useDataSettingsController';
import { SettingsSection } from '../SettingsPrimitives';
import { AboutPanel } from './AboutPanel';
import { DangerZonePanel } from './DangerZonePanel';
import { DiagnosticsPanel } from './DiagnosticsPanel';
import { MigrationPanel } from './MigrationPanel';
import { RetentionSettingsPanel } from './RetentionSettingsPanel';
import { SnapshotPanel } from './SnapshotPanel';
import { TrashPanel } from './TrashPanel';

interface DataSettingsSectionProps {
  /** Controller bag from `useDataSettingsController`. Passed through
   * as one prop (mirroring the `<SyncSettingsPanel sync={...}>` /
   * `<McpSetupSection mcp={...}>` convention used by the sibling
   * sections) so a new field on the controller does not need to be
   * re-listed at the SettingsView call site. */
  data: DataSettingsController;
  /** Render-time helper for ISO timestamps. Lives outside the
   * controller because it depends on the user's active locale +
   * day-context preferences, both of which the SettingsView already
   * has in scope. */
  formatSyncTimestamp: (value: string | null) => string;
  appVersion?: string | null | undefined;
}

export function DataSettingsSection({
  data,
  formatSyncTimestamp,
  appVersion,
}: DataSettingsSectionProps) {
  const { t } = useI18n();

  return (
    <>
      {/* Backup / restore is a single concern (snapshot export + import),
          so it stays in its own `Your Data` panel. Retention, Trash,
          Diagnostics, Danger Zone, and About are now peer panels rather
          than nested children — the prior shape had four nested cards
          inside one outer card, which read as a cluttered hierarchy. */}
      <SettingsSection
        title={t('settings.yourData')}
        description={t('settings.yourDataDesc')}
      >
        <SnapshotPanel
          snapshotBusy={data.snapshotBusy}
          lastSnapshotResult={data.lastSnapshotResult}
          snapshotErrorDetail={data.snapshotErrorDetail}
          snapshotStatus={data.snapshotStatus}
          lastExportPath={data.lastExportPath}
          snapshotPreview={data.snapshotPreview}
          exportScopeMode={data.exportScopeMode}
          exportScopeCategories={data.exportScopeCategories}
          onExportSnapshot={data.handleExportSnapshot}
          onSetExportScopeMode={data.setExportScopeMode}
          onToggleExportScopeCategory={data.toggleExportScopeCategory}
          onLoadSnapshotFile={data.handleLoadSnapshotFile}
          onImportSnapshot={data.handleImportSnapshot}
        />
      </SettingsSection>

      <SettingsSection
        title={t('settings.migration.title')}
        description={t('settings.migration.desc')}
      >
        <MigrationPanel />
      </SettingsSection>

      <SettingsSection
        title={t('settings.retentionSection')}
        description={t('settings.retentionSectionDesc')}
      >
        <RetentionSettingsPanel />
      </SettingsSection>

      <TrashPanel />

      <SettingsSection
        title={t('settings.diagnosticsSection')}
        description={t('settings.diagnosticsSectionDesc')}
      >
        <DiagnosticsPanel
          errorLogs={data.errorLogs}
          errorLogsBusy={data.errorLogsBusy}
          errorLogsActionMessage={data.errorLogsActionMessage}
          recentLogsActionMessage={data.recentLogsActionMessage}
          recentLogs={data.recentLogs}
          formatSyncTimestamp={formatSyncTimestamp}
          onRefreshErrorLogs={data.handleRefreshErrorLogs}
          onCopyErrorLogs={data.handleCopyErrorLogs}
          onCopyRecentLogs={data.handleCopyRecentLogs}
          onRetrySyncOutboxEntry={data.handleRetrySyncOutboxEntry}
          onSetFilters={data.setDiagnosticsFilters}
        />
      </SettingsSection>

      <div id="settings-section-danger-zone">
        <SettingsSection
          title={t('settings.dangerZone')}
          description={t('settings.dangerZoneDesc')}
          variant="danger"
        >
          <DangerZonePanel
            onClearErrorLogs={data.handleClearErrorLogs}
            errorLogsBusy={data.errorLogsBusy}
          />
        </SettingsSection>
      </div>

      <AboutPanel appVersion={appVersion} />
    </>
  );
}
