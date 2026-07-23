import { useI18n } from '@/lib/i18n';
import { SYNC_BACKEND_FILESYSTEM_BRIDGE } from '@/lib/syncBackend/kinds';
import { shouldShowRuntimeBackendDiagnostics } from './backendContext';
import { InfoRow } from '@/components/settings/SettingsPrimitives';
import type { AssistantSyncSettingsModel } from '../types';
import type { TranslationKey } from '@/locales';

interface SyncDiagnosticsPanelProps {
  sync: AssistantSyncSettingsModel;
}

export function SyncDiagnosticsPanel({ sync }: SyncDiagnosticsPanelProps) {
  const { t, format, formatNumber } = useI18n();
  const { syncStatus, formatSyncTimestamp } = sync;

  if (!syncStatus) {
    return <p className="text-xs text-text-muted">{t('settings.loading')}</p>;
  }

  // The previous shape was 65 hand-spelled `<InfoRow>` JSX blocks
  // where each timestamp/malformed-flag pair was three duplicated
  // lines that could drift independently — a missing `*_malformed`
  // companion was a silent regression. Imperative builders below
  // collapse each row class to one line and bundle the
  // malformed-pair invariant into the helpers themselves.
  const rows: { label: string; value: string }[] = [];

  const formatMalformed = (malformed: boolean, reason: string | null | undefined): string =>
    !malformed
      ? t('settings.syncNo')
      : reason
        ? `${t('settings.syncYes')} (${reason})`
        : t('settings.syncYes');

  const num = (labelKey: TranslationKey, value: number): void => {
    rows.push({ label: t(labelKey), value: formatNumber(value) });
  };
  const str = (
    labelKey: TranslationKey,
    value: string | null,
    fallbackKey: TranslationKey,
  ): void => {
    rows.push({ label: t(labelKey), value: value ?? t(fallbackKey) });
  };
  const literal = (labelKey: TranslationKey, value: string): void => {
    rows.push({ label: t(labelKey), value });
  };
  const malformed = (
    labelKey: TranslationKey,
    isMalformed: boolean,
    reason: string | null | undefined,
  ): void => {
    rows.push({ label: t(labelKey), value: formatMalformed(isMalformed, reason) });
  };
  const ts = (
    labelKey: TranslationKey,
    value: string | null,
    pair?: {
      malformedKey: TranslationKey;
      malformed: boolean;
      reason: string | null | undefined;
    },
  ): void => {
    rows.push({ label: t(labelKey), value: formatSyncTimestamp(value) });
    if (pair) {
      malformed(pair.malformedKey, pair.malformed, pair.reason);
    }
  };
  const bool = (
    labelKey: TranslationKey,
    value: boolean,
    pair?: {
      malformedKey: TranslationKey;
      malformed: boolean;
      reason: string | null | undefined;
    },
  ): void => {
    rows.push({
      label: t(labelKey),
      value: value ? t('settings.syncYes') : t('settings.syncNo'),
    });
    if (pair) {
      malformed(pair.malformedKey, pair.malformed, pair.reason);
    }
  };
  const duration = (labelKey: TranslationKey, durationMs: number | null): void => {
    rows.push({
      label: t(labelKey),
      value:
        durationMs === null
          ? t('settings.syncUnknown')
          : format('settings.syncDurationMs', { count: formatNumber(durationMs) }),
    });
  };

  // Core sync runtime diagnostics (order = display order).
  str(
    'settings.syncBackendRaw',
    syncStatus.sync_backend_kind_raw,
    'settings.syncUnknown',
  );
  str(
    'settings.syncBackendConfigured',
    syncStatus.sync_backend_kind,
    'settings.syncUnknown',
  );
  literal('settings.syncBackendEffective', syncStatus.sync_backend_kind_effective);
  malformed(
    'settings.syncBackendMalformed',
    syncStatus.sync_backend_kind_malformed,
    syncStatus.sync_backend_kind_malformed_reason,
  );
  num('settings.syncPendingEvents', syncStatus.pending_count);
  num('settings.syncRetryingEvents', syncStatus.retrying_count);
  num('settings.syncFailedEvents', syncStatus.failed_count);
  ts('settings.syncOldestPending', syncStatus.oldest_pending_at);

  num('settings.syncApplyCycleCount', syncStatus.apply_cycle_count);
  ts('settings.syncApplyCycleLastStartedAt', syncStatus.apply_cycle_last_started_at);
  ts('settings.syncApplyCycleLastCompletedAt', syncStatus.apply_cycle_last_completed_at);
  duration(
    'settings.syncApplyCycleLastDuration',
    syncStatus.apply_cycle_last_duration_ms,
  );
  num('settings.syncApplyCycleLastReceived', syncStatus.apply_cycle_last_received);
  num('settings.syncApplyCycleLastProcessed', syncStatus.apply_cycle_last_processed);
  num('settings.syncApplyCycleLastApplied', syncStatus.apply_cycle_last_applied);
  num(
    'settings.syncApplyCycleLastSkippedDuplicate',
    syncStatus.apply_cycle_last_skipped_duplicate,
  );
  num(
    'settings.syncApplyCycleLastSkippedStale',
    syncStatus.apply_cycle_last_skipped_stale,
  );
  num(
    'settings.syncApplyCycleLastSkippedDeferred',
    syncStatus.apply_cycle_last_skipped_deferred,
  );
  num(
    'settings.syncApplyCycleLastSkippedMalformed',
    syncStatus.apply_cycle_last_skipped_malformed,
  );
  str(
    'settings.syncApplyCycleLastError',
    syncStatus.apply_cycle_last_error,
    'settings.syncNone',
  );
  num(
    'settings.syncApplyCyclesRetainedReceived',
    syncStatus.apply_cycles_retained_received,
  );
  num(
    'settings.syncApplyCyclesRetainedProcessed',
    syncStatus.apply_cycles_retained_processed,
  );
  num(
    'settings.syncApplyCyclesRetainedApplied',
    syncStatus.apply_cycles_retained_applied,
  );
  num(
    'settings.syncApplyCyclesRetainedSkippedDuplicate',
    syncStatus.apply_cycles_retained_skipped_duplicate,
  );
  num(
    'settings.syncApplyCyclesRetainedSkippedStale',
    syncStatus.apply_cycles_retained_skipped_stale,
  );
  num(
    'settings.syncApplyCyclesRetainedSkippedDeferred',
    syncStatus.apply_cycles_retained_skipped_deferred,
  );
  num(
    'settings.syncApplyCyclesRetainedSkippedMalformed',
    syncStatus.apply_cycles_retained_skipped_malformed,
  );

  num('settings.syncPendingInboxEntries', syncStatus.pending_inbox_count);
  ts('settings.syncPendingInboxOldest', syncStatus.pending_inbox_oldest_at, {
    malformedKey: 'settings.syncPendingInboxOldestMalformed',
    malformed: syncStatus.pending_inbox_oldest_at_malformed,
    reason: syncStatus.pending_inbox_oldest_at_malformed_reason,
  });

  num('settings.syncTombstoneCount', syncStatus.tombstone_count);
  ts(
    'settings.syncTombstoneOldestDeletedAt',
    syncStatus.tombstone_oldest_deleted_at,
    {
      malformedKey: 'settings.syncTombstoneOldestDeletedAtMalformed',
      malformed: syncStatus.tombstone_oldest_deleted_at_malformed,
      reason: syncStatus.tombstone_oldest_deleted_at_malformed_reason,
    },
  );
  ts(
    'settings.syncTombstoneNewestDeletedAt',
    syncStatus.tombstone_newest_deleted_at,
    {
      malformedKey: 'settings.syncTombstoneNewestDeletedAtMalformed',
      malformed: syncStatus.tombstone_newest_deleted_at_malformed,
      reason: syncStatus.tombstone_newest_deleted_at_malformed_reason,
    },
  );

  num('settings.syncConflictLogEntries', syncStatus.conflict_log_count);
  ts(
    'settings.syncConflictLogLastResolvedAt',
    syncStatus.conflict_log_last_resolved_at,
    {
      malformedKey: 'settings.syncConflictLogLastResolvedAtMalformed',
      malformed: syncStatus.conflict_log_last_resolved_at_malformed,
      reason: syncStatus.conflict_log_last_resolved_at_malformed_reason,
    },
  );

  literal(
    'settings.syncIcalSubscriptionsHealth',
    `${formatNumber(syncStatus.ical_subscription_failing_count)} / ${formatNumber(syncStatus.ical_subscription_total_count)}`,
  );
  num(
    'settings.syncIcalSubscriptionsNeverRefreshed',
    syncStatus.ical_subscription_never_refreshed_count,
  );
  num('settings.syncIcalSubscriptionsStale', syncStatus.ical_subscription_stale_count);

  bool('settings.syncReseedRequiredCheckpoint', syncStatus.reseed_required, {
    malformedKey: 'settings.syncReseedRequiredCheckpointMalformed',
    malformed: syncStatus.reseed_required_malformed,
    reason: syncStatus.reseed_required_malformed_reason,
  });

  ts('settings.syncLastSynced', syncStatus.last_synced_at, {
    malformedKey: 'settings.syncLastSyncedMalformed',
    malformed: syncStatus.last_synced_at_malformed,
    reason: syncStatus.last_synced_at_malformed_reason,
  });
  ts('settings.syncLastSuccess', syncStatus.last_success_at, {
    malformedKey: 'settings.syncLastSuccessMalformed',
    malformed: syncStatus.last_success_at_malformed,
    reason: syncStatus.last_success_at_malformed_reason,
  });
  ts('settings.syncLastPull', syncStatus.last_pull_at, {
    malformedKey: 'settings.syncLastPullMalformed',
    malformed: syncStatus.last_pull_at_malformed,
    reason: syncStatus.last_pull_at_malformed_reason,
  });
  str('settings.syncDeviceId', syncStatus.device_id, 'settings.syncUnknown');
  str('settings.syncLastError', syncStatus.last_error, 'settings.syncNone');

  // Backend-specific cursor diagnostics, only shown when the runtime
  // is actively using the backend AND has produced cursor state.
  const showFsBridge =
    shouldShowRuntimeBackendDiagnostics(syncStatus, SYNC_BACKEND_FILESYSTEM_BRIDGE)
    && (syncStatus.filesystem_bridge_last_pull_cursor !== null
      || syncStatus.filesystem_bridge_last_pull_cursor_malformed);
  if (showFsBridge) {
    malformed(
      'settings.syncFilesystemBridgeCursorMalformed',
      syncStatus.filesystem_bridge_last_pull_cursor_malformed,
      syncStatus.filesystem_bridge_last_pull_cursor_malformed_reason,
    );
    ts(
      'settings.syncFilesystemBridgeCursorUpdatedAt',
      syncStatus.filesystem_bridge_last_pull_updated_at,
    );
    str(
      'settings.syncFilesystemBridgeCursorDeviceId',
      syncStatus.filesystem_bridge_last_pull_device_id,
      'settings.syncUnknown',
    );
    str(
      'settings.syncFilesystemBridgeCursorEventId',
      syncStatus.filesystem_bridge_last_pull_event_id,
      'settings.syncUnknown',
    );
    num(
      'settings.syncFilesystemBridgeLookbackKnownIdSkippedLastRun',
      syncStatus.filesystem_bridge_lookback_known_id_skipped_last_run,
    );
    malformed(
      'settings.syncFilesystemBridgeLookbackKnownIdSkippedMalformed',
      syncStatus.filesystem_bridge_lookback_known_id_skipped_last_run_malformed,
      syncStatus.filesystem_bridge_lookback_known_id_skipped_last_run_malformed_reason,
    );
    str(
      'settings.syncFilesystemBridgeLookbackKnownIdSkippedAt',
      syncStatus.filesystem_bridge_lookback_known_id_skipped_last_run_at,
      'settings.syncUnknown',
    );
    malformed(
      'settings.syncFilesystemBridgeLookbackKnownIdSkippedAtMalformed',
      syncStatus.filesystem_bridge_lookback_known_id_skipped_last_run_at_malformed,
      syncStatus.filesystem_bridge_lookback_known_id_skipped_last_run_at_malformed_reason,
    );
  }

  return (
    <div className="space-y-2">
      {rows.map((row, index) => (
        <InfoRow key={`${row.label}-${index}`} label={row.label} value={row.value} />
      ))}
    </div>
  );
}
