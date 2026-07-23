import { InfoRow } from '@/components/settings/SettingsPrimitives';
import { useI18n } from '@/lib/i18n';
import type { RunSyncBackendNowResult } from '@/lib/syncBackend/model';

interface LastSyncSummaryProps {
  lastSyncRunResult: RunSyncBackendNowResult | null;
  syncLastRunAt: string | null;
  formatSyncTimestamp: (value: string | null) => string;
}

export function LastSyncSummary({
  lastSyncRunResult,
  syncLastRunAt,
  formatSyncTimestamp,
}: LastSyncSummaryProps) {
  const { t, formatNumber } = useI18n();

  if (!lastSyncRunResult) {
    return null;
  }

  const commonRows = (
    <>
      <InfoRow label={t('settings.syncLastSynced')} value={formatSyncTimestamp(syncLastRunAt)} />
      <InfoRow label={t('settings.syncSummaryPushed')} value={formatNumber(lastSyncRunResult.summary.pushed)} />
      <InfoRow label={t('settings.syncSummaryPulled')} value={formatNumber(lastSyncRunResult.summary.pulledRemoteEvents)} />
      <InfoRow label={t('settings.syncSummaryApplied')} value={formatNumber(lastSyncRunResult.summary.applied)} />
      {lastSyncRunResult.summary.diagnosticsLogFailures > 0 && (
        <InfoRow
          label={t('settings.syncSummaryDiagnosticsLogFailures')}
          value={formatNumber(lastSyncRunResult.summary.diagnosticsLogFailures)}
        />
      )}
    </>
  );

  return (
    <div className="text-xs text-text-muted bg-surface-1 border border-surface-3 rounded-r-card p-3 space-y-1">
      <p className="text-xs font-medium text-text-muted">{t('settings.syncLastRun')}</p>
      {!lastSyncRunResult.backendResult && commonRows}
      {lastSyncRunResult.backendResult && (
        <>
          {commonRows}
          {lastSyncRunResult.backendResult.push_write_errors > 0 && (
            <InfoRow
              label={t('settings.syncSummaryPushErrors')}
              value={formatNumber(lastSyncRunResult.backendResult.push_write_errors)}
            />
          )}
          <InfoRow
            label={t('settings.syncSummaryLookbackKnownIdSkipped')}
            value={formatNumber(lastSyncRunResult.backendResult.lookback_known_id_skipped)}
          />
        </>
      )}
    </div>
  );
}
