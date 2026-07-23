import { useI18n } from '@/lib/i18n';
import { useSyncProgress } from '@/lib/sync/useSyncProgress';

interface SyncProgressStatusProps {
  syncRunning: boolean;
  seedSyncRunning: boolean;
}

export function SyncProgressStatus({
  syncRunning,
  seedSyncRunning,
}: SyncProgressStatusProps) {
  const { t, formatNumber } = useI18n();
  const syncProgress = useSyncProgress();
  const showProgressBar =
    (syncRunning || seedSyncRunning) && syncProgress.cycleId !== null;

  if (!showProgressBar) {
    return null;
  }

  const progressPercent = syncProgress.determinate
    ? Math.min(100, Math.max(0, Math.round((syncProgress.current / syncProgress.total) * 100)))
    : null;
  const progressPhaseLabel =
    syncProgress.phase === 'push'
      ? t('settings.syncProgressPhasePush')
      : syncProgress.phase === 'pull'
        ? t('settings.syncProgressPhasePull')
        : syncProgress.phase === 'apply'
          ? t('settings.syncProgressPhaseApply')
          : t('settings.syncRunning');

  return (
    <div
      className="space-y-1.5"
      role="status"
      aria-live="polite"
      aria-atomic="true"
    >
      <div
        className="h-1.5 w-full overflow-hidden rounded-full bg-surface-3"
        role="progressbar"
        aria-valuemin={0}
        aria-valuemax={progressPercent === null ? undefined : 100}
        aria-valuenow={progressPercent === null ? undefined : progressPercent}
        aria-label={progressPhaseLabel}
      >
        {progressPercent === null ? (
          <div className="h-full w-1/3 animate-pulse rounded-full bg-accent/60" />
        ) : (
          <div
            className="progress-fill h-full rounded-full bg-accent transition-transform duration-200 ease-out"
            style={{ transform: `scaleX(${progressPercent / 100})` }}
          />
        )}
      </div>
      <div className="flex items-center justify-between text-xs text-text-muted">
        <span>{progressPhaseLabel}</span>
        {syncProgress.determinate && (
          <span className="tabular-nums">
            {formatNumber(syncProgress.current)} / {formatNumber(syncProgress.total)}
            {progressPercent !== null ? ` · ${progressPercent}%` : ''}
          </span>
        )}
      </div>
    </div>
  );
}
