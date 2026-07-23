import { useEffect, useId, useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { getSyncConflictLog } from '@/lib/ipc/diagnostics';
import type { SyncConflictLogEntry } from '@/lib/ipc/diagnostics';
import { useI18n } from '@/lib/i18n';
import { useLazyRef } from '@/lib/useLazyRef';
import {
  buildConflictLogQueryConfig,
  createDiagnosticsConflictLogRefetchController,
  readDiagnosticsConflictLogEntries,
  type DiagnosticsTimeWindowPreset,
} from '../diagnostics.logic';

export function ConflictLogSection({
  timeWindow,
  sinceIso,
  sourceDeviceId,
  formatSyncTimestamp,
}: {
  timeWindow: DiagnosticsTimeWindowPreset;
  sinceIso: string | null;
  sourceDeviceId: string | null;
  formatSyncTimestamp: (value: string | null) => string;
}) {
  const { t } = useI18n();
  const [expanded, setExpanded] = useState(false);
  const contentId = useId();
  const refetchControllerRef = useLazyRef(() =>
    createDiagnosticsConflictLogRefetchController(sinceIso, sourceDeviceId),
  );
  const { data, isFetching, refetch } = useQuery<{
    sinceIso: string | null;
    sourceDeviceId: string | null;
    entries: SyncConflictLogEntry[];
  }>({
    ...buildConflictLogQueryConfig({
      timeWindow,
      sourceDeviceId,
      enabled: expanded,
    }),
    queryFn: async ({ signal }) => ({
      sinceIso,
      sourceDeviceId,
      entries: await getSyncConflictLog(200, sinceIso, sourceDeviceId, signal),
    }),
  });
  const entries = readDiagnosticsConflictLogEntries(data, sinceIso, sourceDeviceId);

  useEffect(() => {
    if (refetchControllerRef.current.shouldRefetch({ expanded, sinceIso, sourceDeviceId })) {
      void refetch();
    }
    // refetchControllerRef is a stable MutableRefObject from useLazyRef/useRef.
  }, [expanded, refetch, refetchControllerRef, sinceIso, sourceDeviceId]);

  return (
    <div className="bg-surface-2/60 border border-surface-3 rounded-r-card p-3.5 space-y-3">
      <div className="flex items-start justify-between gap-3">
        <button
          type="button"
          onClick={() => setExpanded((prev) => !prev)}
          aria-expanded={expanded}
          aria-controls={contentId}
          className="text-xs text-text-secondary font-medium flex items-center gap-1.5 focus-ring-soft rounded-r-control"
        >
          <span aria-hidden="true">{expanded ? '▾' : '▸'}</span>
          <span>{t('diagnostics.conflictLog.title')}</span>
          {entries.length > 0 && (
            <span className="text-text-muted">({entries.length})</span>
          )}
        </button>
        {expanded && (
          <button
            type="button"
            onClick={() => {
              void refetch();
            }}
            disabled={isFetching}
            className="text-xs px-2.5 py-1.5 rounded-r-control bg-surface-1 border border-surface-3 text-text-secondary hover:bg-surface-3 disabled:opacity-50 disabled:cursor-not-allowed focus-ring-soft"
          >
            {t('settings.errorLogsRefresh')}
          </button>
        )}
      </div>
      <div id={contentId} hidden={!expanded}>
        {expanded && (
          <>
            {entries.length === 0 ? (
              <p className="text-xs text-text-muted">{t('diagnostics.conflictLog.empty')}</p>
            ) : (
              <div className="max-h-56 overflow-y-auto rounded-r-card border border-surface-3 bg-surface-1 divide-y divide-surface-3">
                {entries.map((entry) => (
                  <div key={entry.id} className="p-2.5 space-y-1.5">
                    <div className="flex items-center gap-2 flex-wrap">
                      <span className="chip-tight chip-warning text-xs uppercase tracking-wide">
                        {entry.kind}
                      </span>
                      <span className="text-xs text-text-muted">{entry.entity_type}</span>
                      <span className="text-xs text-text-muted font-mono">{entry.entity_id}</span>
                      <span className="ms-auto text-xs text-text-muted">
                        {formatSyncTimestamp(entry.occurred_at)}
                      </span>
                    </div>
                    <div className="text-xs text-text-muted font-mono space-y-0.5">
                      <p>
                        <span className="text-text-secondary">
                          {t('diagnostics.conflictLog.localVersion')}:
                        </span>{' '}
                        {entry.local_version}
                      </p>
                      <p>
                        <span className="text-text-secondary">
                          {t('diagnostics.conflictLog.remoteVersion')}:
                        </span>{' '}
                        {entry.remote_version}
                      </p>
                      {entry.loser_device_id && (
                        <p className="wrap-break-word">device: {entry.loser_device_id}</p>
                      )}
                    </div>
                    {entry.details && (
                      <pre className="text-xs text-text-muted whitespace-pre-wrap wrap-break-word font-mono">
                        {entry.details}
                      </pre>
                    )}
                  </div>
                ))}
              </div>
            )}
          </>
        )}
      </div>
    </div>
  );
}
