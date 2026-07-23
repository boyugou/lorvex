import { useCallback, useEffect, useMemo, useState } from 'react';
import type { ErrorLogEntry } from '@/lib/ipc/settings';
import { useLazyRef } from '@/lib/useLazyRef';
import { useVisibilityGatedInterval } from '@/lib/time/useVisibilityGatedInterval';
import {
  buildDiagnosticsRawFilters,
  createDiagnosticsPanelFilterEffectController,
  DEFAULT_DIAGNOSTICS_TIME_WINDOW,
  resolveDiagnosticsFilters,
  type DiagnosticsFilters,
  type DiagnosticsTimeWindowPreset,
} from './diagnostics.logic';
import {
  ConflictLogSection,
  ErrorLogsSection,
  ExportBundleCard,
  FiltersCard,
  RecentLogsSection,
} from './diagnostics-panel';
import type { RecentLogItem } from './types';

interface DiagnosticsPanelProps {
  errorLogs: ErrorLogEntry[];
  errorLogsBusy: boolean;
  errorLogsActionMessage: string | null;
  recentLogsActionMessage: string | null;
  recentLogs: RecentLogItem[];
  formatSyncTimestamp: (value: string | null) => string;
  onRefreshErrorLogs: (announce?: boolean) => Promise<void>;
  onCopyErrorLogs: () => Promise<void>;
  onCopyRecentLogs: () => Promise<void>;
  onRetrySyncOutboxEntry: (id: string) => Promise<void>;
  /** Pushes filter state into the refresh hook so the next error-logs /
   * changelog fetch applies the time-window + device-scope filters. */
  onSetFilters: (filters: DiagnosticsFilters) => void;
}

export function DiagnosticsPanel({
  errorLogs,
  errorLogsBusy,
  errorLogsActionMessage,
  recentLogsActionMessage,
  recentLogs,
  formatSyncTimestamp,
  onRefreshErrorLogs,
  onCopyErrorLogs,
  onCopyRecentLogs,
  onRetrySyncOutboxEntry,
  onSetFilters,
}: DiagnosticsPanelProps) {
  const [timeWindow, setTimeWindow] = useState<DiagnosticsTimeWindowPreset>(
    DEFAULT_DIAGNOSTICS_TIME_WINDOW,
  );
  // Type parameter inferred from the literal — dropped redundant
  // `<string>` annotation. frontend-cleanup pass.
  const [deviceScope, setDeviceScope] = useState('');
  const [filterNowMs, setFilterNowMs] = useState(() => Date.now());
  const filterEffectControllerRef = useLazyRef(() => createDiagnosticsPanelFilterEffectController());

  const rawFilters = useMemo(() => buildDiagnosticsRawFilters({
    timeWindow,
    sourceDeviceId: deviceScope || null,
  }), [deviceScope, timeWindow]);

  const syncFilterNow = useCallback(() => {
    const nowMs = Date.now();
    setFilterNowMs(nowMs);
    return nowMs;
  }, []);

  // Keep rolling windows genuinely rolling while the panel stays open by
  // advancing the shared rolling cutoff on an explicit timer. Manual refreshes
  // and filter changes also bump this clock, so the conflict-log query key does
  // not churn on unrelated parent rerenders.
  useVisibilityGatedInterval(() => {
    syncFilterNow();
  }, 30_000);

  const filters = useMemo(
    () => resolveDiagnosticsFilters(rawFilters, filterNowMs),
    [filterNowMs, rawFilters],
  );

  // Thread the raw filter intent into the refresh hook. It resolves the
  // rolling time-window cutoff at refresh time, so auto/manual refreshes
  // cannot lag behind the displayed preset.
  useEffect(() => {
    filterEffectControllerRef.current.apply({
      filters: rawFilters,
      syncNow: syncFilterNow,
      setFilters: onSetFilters,
      refresh: () => {
        void onRefreshErrorLogs(false);
      },
    });
    // filterEffectControllerRef is a stable MutableRefObject from useLazyRef.
  }, [filterEffectControllerRef, onRefreshErrorLogs, onSetFilters, rawFilters, syncFilterNow]);

  return (
    <div className="space-y-4">
      <FiltersCard
        deviceScope={deviceScope}
        onDeviceScopeChange={setDeviceScope}
        onTimeWindowChange={setTimeWindow}
        timeWindow={timeWindow}
      />

      <ExportBundleCard />

      <ConflictLogSection
        timeWindow={timeWindow}
        sinceIso={filters.sinceIso}
        sourceDeviceId={filters.sourceDeviceId}
        formatSyncTimestamp={formatSyncTimestamp}
      />

      <ErrorLogsSection
        errorLogs={errorLogs}
        errorLogsActionMessage={errorLogsActionMessage}
        errorLogsBusy={errorLogsBusy}
        formatSyncTimestamp={formatSyncTimestamp}
        onCopyErrorLogs={onCopyErrorLogs}
        onRefreshErrorLogs={onRefreshErrorLogs}
        syncFilterNow={syncFilterNow}
      />

      <RecentLogsSection
        errorLogsBusy={errorLogsBusy}
        formatSyncTimestamp={formatSyncTimestamp}
        onCopyRecentLogs={onCopyRecentLogs}
        onRefreshErrorLogs={onRefreshErrorLogs}
        onRetrySyncOutboxEntry={onRetrySyncOutboxEntry}
        recentLogs={recentLogs}
        recentLogsActionMessage={recentLogsActionMessage}
        syncFilterNow={syncFilterNow}
      />
    </div>
  );
}
