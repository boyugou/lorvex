import {
  useCallback,
  useRef,
  useState,
} from 'react';

import { appendClientErrorLog } from '@/lib/errors/errorLogging';
import { useLazyRef } from '@/lib/useLazyRef';
import { useVisibilityGatedInterval } from '@/lib/time/useVisibilityGatedInterval';
import {
  beginDiagnosticsRefreshRequest,
  createDiagnosticsFilterIntentController,
  createDiagnosticsRefreshCoordinator,
  DEFAULT_DIAGNOSTICS_FILTERS,
  loadFilteredRecentSyncEvents,
  shouldIncludeDiagnosticsErrorLogs,
  type DiagnosticsFilters,
} from '@/components/settings/data/diagnostics.logic';
import { toIpcErrorMessage } from '@/lib/ipc/core.logic';
import { getErrorLogs } from '@/lib/ipc/settings';
import type { ErrorLogEntry } from '@/lib/ipc/settings';
import { getRecentOutboxEntries } from '@/lib/ipc/sync';
import type { SyncOutboxEntry } from '@/lib/ipc/sync';
import type { ChangelogEntry } from '@/lib/ipc/tasks/models';
import { getChangelog } from '@/lib/ipc/tasks/reviews';
import type { RefreshErrorLogsResult } from '@/components/settings/data/types';
import type { UseDataDiagnosticsRefreshArgs } from './types';

export function useDataDiagnosticsRefresh({
  settingsMountedRef,
  t,
}: UseDataDiagnosticsRefreshArgs) {
  const [errorLogs, setErrorLogs] = useState<ErrorLogEntry[]>([]);
  const [changelogEntries, setChangelogEntries] = useState<ChangelogEntry[]>([]);
  const [recentSyncEvents, setRecentSyncEvents] = useState<SyncOutboxEntry[]>([]);
  const [errorLogsBusy, setErrorLogsBusy] = useState(false);
  const [errorLogsActionMessage, setErrorLogsActionMessage] = useState<string | null>(null);
  const [recentLogsActionMessage, setRecentLogsActionMessage] = useState<string | null>(null);
  const diagnosticsRefreshRunningRef = useRef(false);
  const filtersRef = useLazyRef(() => createDiagnosticsFilterIntentController(DEFAULT_DIAGNOSTICS_FILTERS));
  const refreshCoordinatorRef = useLazyRef(() => createDiagnosticsRefreshCoordinator());

  const setDiagnosticsFilters = useCallback((next: DiagnosticsFilters) => {
    filtersRef.current.setFilters(next);
    // filtersRef is a stable MutableRefObject from useLazyRef.
  }, [filtersRef]);

  const refreshErrorLogs = useCallback(async (silent = false, announce = false): Promise<RefreshErrorLogsResult | null> => {
    const requestId = beginDiagnosticsRefreshRequest(refreshCoordinatorRef.current, silent);
    if (requestId === null) {
      return null;
    }
    if (!silent && settingsMountedRef.current) {
      setErrorLogsBusy(true);
    }
    try {
      const { sinceIso, sourceDeviceId } = filtersRef.current.resolve(Date.now());
      const shouldIncludeErrorLogs = shouldIncludeDiagnosticsErrorLogs(sourceDeviceId);
      const [entries, changelog, filteredSyncEvents] = await Promise.all([
        shouldIncludeErrorLogs
          ? getErrorLogs(200, { sinceIso })
          : Promise.resolve([]),
        getChangelog(120, { sinceIso, sourceDeviceId }),
        loadFilteredRecentSyncEvents({
          fetchRecentOutboxEntries: (limit) => getRecentOutboxEntries(limit),
          filters: { sinceIso, sourceDeviceId },
        }),
      ]);
      if (!settingsMountedRef.current || !refreshCoordinatorRef.current.isLatest(requestId)) return null;
      const errorCount = entries.length;
      const recentCount = errorCount + changelog.length + filteredSyncEvents.length;
      setErrorLogs(entries);
      setChangelogEntries(changelog);
      setRecentSyncEvents(filteredSyncEvents);
      if (announce) {
        const message = `${t('settings.errorLogsRefresh')}: ${errorCount} · ${t('settings.recentLogsTitle')}: ${recentCount}`;
        setErrorLogsActionMessage(message);
        setRecentLogsActionMessage(message);
      } else if (!silent) {
        setErrorLogsActionMessage(null);
        setRecentLogsActionMessage(null);
      }
      return { errorCount, recentCount };
    } catch (error) {
      if (!settingsMountedRef.current || !refreshCoordinatorRef.current.isLatest(requestId)) return null;
      const message = `${t('common.error')}: ${toIpcErrorMessage(error)}`;
      setErrorLogsActionMessage(message);
      setRecentLogsActionMessage(message);
      return null;
    } finally {
      if (!silent && settingsMountedRef.current && refreshCoordinatorRef.current.releaseBusy(requestId)) {
        setErrorLogsBusy(false);
      }
    }
    // filtersRef and refreshCoordinatorRef are stable MutableRefObjects from useLazyRef.
  }, [filtersRef, refreshCoordinatorRef, settingsMountedRef, t]);

  const logDataSettingsError = useCallback((source: string, message: string, error: unknown) => {
    const details = toIpcErrorMessage(error);
    void appendClientErrorLog(source, message, error, details, 'error')
      .then((appended) => {
        if (appended) {
          void refreshErrorLogs(true);
          return;
        }
        if (!settingsMountedRef.current) return;
        setErrorLogsActionMessage(`${t('common.error')}: ${details}`);
      });
  }, [refreshErrorLogs, settingsMountedRef, t]);

  // visibility-gate the 30s diagnostics refresh so a
  // hidden window doesn't keep polling error logs.
  const diagnosticsTick = useCallback(() => {
    if (diagnosticsRefreshRunningRef.current) return;
    diagnosticsRefreshRunningRef.current = true;
    void refreshErrorLogs(true)
      .finally(() => {
        diagnosticsRefreshRunningRef.current = false;
      });
  }, [refreshErrorLogs]);
  useVisibilityGatedInterval(diagnosticsTick, 30_000);

  return {
    changelogEntries,
    errorLogs,
    errorLogsActionMessage,
    recentLogsActionMessage,
    errorLogsBusy,
    logDataSettingsError,
    recentSyncEvents,
    refreshErrorLogs,
    setErrorLogsActionMessage,
    setRecentLogsActionMessage,
    setErrorLogsBusy,
    setDiagnosticsFilters,
  };
}
