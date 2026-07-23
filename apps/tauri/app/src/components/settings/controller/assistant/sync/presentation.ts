import type { TranslationKey } from '@/lib/i18n';

interface SyncStateStatus {
  failed_count: number;
  pending_count: number;
  pending_inbox_count: number;
  reseed_required: boolean;
  retrying_count: number;
  last_error?: string | null;
}

interface SyncStatusLineArgs {
  hasAvailableSyncBackends: boolean;
  syncEnabled: boolean;
  syncRunning: boolean;
  seedSyncRunning: boolean;
  syncLastRunAt: string | null;
  syncStatus: SyncStateStatus | null;
}

export function buildSyncStateBadge(
  syncStatus: SyncStateStatus | null,
  t: (key: TranslationKey) => string,
): { label: string; className: string } | null {
  if (!syncStatus) return null;
  if (syncStatus.reseed_required) {
    return { label: t('settings.syncReseedRequired'), className: 'chip-danger' };
  }
  if (syncStatus.failed_count > 0) {
    return { label: t('settings.syncNeedsAttention'), className: 'chip-danger' };
  }
  if (syncStatus.pending_count === 0 && syncStatus.pending_inbox_count === 0) {
    return { label: t('settings.syncUpToDate'), className: 'chip-success' };
  }
  if (syncStatus.retrying_count > 0) {
    return { label: t('settings.syncRetrying'), className: 'chip-warning' };
  }
  return { label: t('settings.syncPending'), className: 'bg-accent/15 text-accent' };
}

export function buildSyncStatusLine(
  {
    hasAvailableSyncBackends,
    syncEnabled,
    syncRunning,
    seedSyncRunning,
    syncLastRunAt,
    syncStatus,
  }: SyncStatusLineArgs,
  t: (key: TranslationKey) => string,
): { text: string; className: string; ariaLive: 'polite' | 'assertive' } {
  if (!hasAvailableSyncBackends) {
    return {
      text: t('settings.syncNotAvailableOnDevice'),
      className: 'text-text-muted',
      ariaLive: 'polite',
    };
  }
  if (!syncEnabled) {
    return {
      text: t('settings.syncNeverSynced'),
      className: 'text-text-muted',
      ariaLive: 'polite',
    };
  }
  if (syncRunning || seedSyncRunning) {
    return {
      text: t('settings.syncRunning'),
      className: 'text-accent',
      ariaLive: 'polite',
    };
  }
  if (syncStatus?.reseed_required) {
    return {
      text: t('settings.syncReseedRequired'),
      className: 'text-danger',
      ariaLive: 'assertive',
    };
  }
  if (syncStatus?.last_error) {
    return {
      text: t('settings.syncHasError'),
      className: 'text-danger',
      ariaLive: 'assertive',
    };
  }
  if (syncStatus && ((syncStatus.pending_count > 0) || (syncStatus.pending_inbox_count > 0))) {
    return {
      text: t('settings.syncPendingBrief'),
      className: 'text-text-muted',
      ariaLive: 'polite',
    };
  }
  if (syncLastRunAt) {
    return {
      text: t('settings.syncUpToDate'),
      className: 'text-success',
      ariaLive: 'polite',
    };
  }
  return {
    text: t('settings.syncNeverSynced'),
    className: 'text-text-muted',
    ariaLive: 'polite',
  };
}
