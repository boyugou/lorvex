import type { ErrorLogEntry } from '@/lib/ipc/settings';
import { useI18n } from '@/lib/i18n';
import { errorLevelPillClass } from '@/components/settings/settingsUtils';
import { DangerZoneLink } from '../DangerZoneLink';
import type { RecentLogItem } from '../types';

export function ErrorLogsSection({
  errorLogs,
  errorLogsActionMessage,
  errorLogsBusy,
  formatSyncTimestamp,
  onCopyErrorLogs,
  onRefreshErrorLogs,
  syncFilterNow,
}: {
  errorLogs: ErrorLogEntry[];
  errorLogsActionMessage: string | null;
  errorLogsBusy: boolean;
  formatSyncTimestamp: (value: string | null) => string;
  onCopyErrorLogs: () => Promise<void>;
  onRefreshErrorLogs: (announce?: boolean) => Promise<void>;
  syncFilterNow: () => number;
}) {
  const { t } = useI18n();

  return (
    <div className="bg-surface-2/60 border border-surface-3 rounded-r-card p-3.5 space-y-3">
      <div className="flex items-start justify-between gap-3">
        <div>
          <p className="text-xs text-text-secondary font-medium">{t('settings.errorLogsTitle')}</p>
          <p className="text-xs text-text-muted mt-0.5">{t('settings.errorLogsDesc')}</p>
          <p className="text-xs text-text-muted mt-1">{t('settings.errorLogsScopeHint')}</p>
        </div>
        <div className="flex flex-wrap items-center gap-2">
          <button
            type="button"
            onClick={() => {
              syncFilterNow();
              void onRefreshErrorLogs(true);
            }}
            disabled={errorLogsBusy}
            className="text-xs px-2.5 py-1.5 rounded-r-control bg-surface-1 border border-surface-3 text-text-secondary hover:bg-surface-3 disabled:opacity-50 disabled:cursor-not-allowed focus-ring-soft"
          >
            {t('settings.errorLogsRefresh')}
          </button>
          <button
            type="button"
            onClick={() => {
              void onCopyErrorLogs();
            }}
            disabled={errorLogsBusy}
            className="text-xs px-2.5 py-1.5 rounded-r-control bg-surface-1 border border-surface-3 text-text-secondary hover:bg-surface-3 disabled:opacity-50 disabled:cursor-not-allowed focus-ring-soft"
          >
            {t('settings.errorLogsCopy')}
          </button>
        </div>
      </div>

      {/* "Clear logs" lived here before the Danger Zone
          consolidation. The button moved; this hint preserves
          discoverability so users who scroll to this panel looking
          for it still find the way. */}
      <DangerZoneLink message={t('settings.errorLogsClearMoved')} />

      {errorLogsActionMessage && (
        <p className="text-xs text-text-muted break-all">{errorLogsActionMessage}</p>
      )}

      {errorLogs.length === 0 ? (
        <div className="text-xs text-text-muted space-y-1">
          <p>{t('settings.errorLogsEmpty')}</p>
          <p>{t('settings.errorLogsEmptyHint')}</p>
        </div>
      ) : (
        <div className="max-h-56 overflow-y-auto rounded-r-card border border-surface-3 bg-surface-1 divide-y divide-surface-3">
          {errorLogs.map((entry) => (
            <div key={entry.id} className="p-2.5 space-y-1.5">
              <div className="flex items-center gap-2">
                <span
                  className={`chip-tight text-xs uppercase tracking-wide ${errorLevelPillClass(entry.level)}`}
                >
                  {entry.level}
                </span>
                <span className="text-xs text-text-muted">{entry.source}</span>
                <span className="text-xs text-text-muted ms-auto">
                  {formatSyncTimestamp(entry.created_at)}
                </span>
              </div>
              <p className="text-xs text-text-secondary wrap-break-word">{entry.message}</p>
              {entry.details && (
                <pre className="text-xs text-text-muted whitespace-pre-wrap wrap-break-word font-mono">
                  {entry.details}
                </pre>
              )}
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

export function RecentLogsSection({
  errorLogsBusy,
  formatSyncTimestamp,
  onCopyRecentLogs,
  onRefreshErrorLogs,
  onRetrySyncOutboxEntry,
  recentLogs,
  recentLogsActionMessage,
  syncFilterNow,
}: {
  errorLogsBusy: boolean;
  formatSyncTimestamp: (value: string | null) => string;
  onCopyRecentLogs: () => Promise<void>;
  onRefreshErrorLogs: (announce?: boolean) => Promise<void>;
  onRetrySyncOutboxEntry: (id: string) => Promise<void>;
  recentLogs: RecentLogItem[];
  recentLogsActionMessage: string | null;
  syncFilterNow: () => number;
}) {
  const { t } = useI18n();

  return (
    <div className="bg-surface-2/60 border border-surface-3 rounded-r-card p-3.5 space-y-3">
      <div className="flex items-start justify-between gap-3">
        <div>
          <p className="text-xs text-text-secondary font-medium">{t('settings.recentLogsTitle')}</p>
          <p className="text-xs text-text-muted mt-0.5">{t('settings.recentLogsDesc')}</p>
        </div>
        <div className="flex flex-wrap items-center gap-2">
          <button
            type="button"
            onClick={() => {
              syncFilterNow();
              void onRefreshErrorLogs(true);
            }}
            disabled={errorLogsBusy}
            className="text-xs px-2.5 py-1.5 rounded-r-control bg-surface-1 border border-surface-3 text-text-secondary hover:bg-surface-3 disabled:opacity-50 disabled:cursor-not-allowed focus-ring-soft"
          >
            {t('settings.recentLogsRefresh')}
          </button>
          <button
            type="button"
            onClick={() => {
              void onCopyRecentLogs();
            }}
            disabled={errorLogsBusy}
            className="text-xs px-2.5 py-1.5 rounded-r-control bg-surface-1 border border-surface-3 text-text-secondary hover:bg-surface-3 disabled:opacity-50 disabled:cursor-not-allowed focus-ring-soft"
          >
            {t('settings.recentLogsCopy')}
          </button>
        </div>
      </div>

      {recentLogsActionMessage && (
        <p className="text-xs text-text-muted break-all">{recentLogsActionMessage}</p>
      )}

      {recentLogs.length === 0 ? (
        <div className="text-xs text-text-muted space-y-1">
          <p>{t('settings.recentLogsEmpty')}</p>
          <p>{t('settings.recentLogsEmptyHint')}</p>
        </div>
      ) : (
        <div className="max-h-56 overflow-y-auto rounded-r-card border border-surface-3 bg-surface-1 divide-y divide-surface-3">
          {recentLogs.map((entry) => (
            <div key={entry.id} className="p-2.5 space-y-1.5">
              <div className="flex items-center gap-2">
                <span
                  className={`chip-tight text-xs uppercase tracking-wide ${errorLevelPillClass(entry.level)}`}
                >
                  {entry.level}
                </span>
                <span className="text-xs text-text-muted">
                  {entry.source === 'error_log'
                    ? t('settings.recentLogsSourceError')
                    : entry.source === 'ai_changelog'
                      ? t('settings.recentLogsSourceChangelog')
                      : t('settings.recentLogsSourceSync')}
                </span>
                <span className="text-xs text-text-muted ms-auto">
                  {formatSyncTimestamp(entry.timestamp)}
                </span>
              </div>
              <p className="text-xs text-text-secondary wrap-break-word">{entry.summary}</p>
              {entry.details && (
                <pre className="text-xs text-text-muted whitespace-pre-wrap wrap-break-word font-mono">
                  {entry.details}
                </pre>
              )}
              {entry.retryOutboxEntryId && (
                <button
                  type="button"
                  onClick={() => {
                    if (entry.retryOutboxEntryId) {
                      void onRetrySyncOutboxEntry(entry.retryOutboxEntryId);
                    }
                  }}
                  disabled={errorLogsBusy}
                  className="text-xs px-2 py-1 rounded-r-control bg-surface-2 border border-surface-3 text-text-secondary hover:bg-surface-3 disabled:opacity-50 disabled:cursor-not-allowed focus-ring-soft"
                >
                  {t('settings.recentLogsRetrySyncEntry')}
                </button>
              )}
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
