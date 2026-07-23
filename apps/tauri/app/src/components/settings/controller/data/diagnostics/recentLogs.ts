import { useMemo } from 'react';
import { SYNC_OUTBOX_MAX_RETRIES } from '@/lib/ipc/sync';
import type { RecentLogItem } from '@/components/settings/data/types';
import { levelForChangelogOperation } from '@/components/settings/settingsUtils';
import type { UseRecentLogsArgs } from './types';

export function buildRecentLogs({
  changelogEntries,
  errorLogs,
  recentSyncEvents,
}: UseRecentLogsArgs): RecentLogItem[] {
  const merged: RecentLogItem[] = [];

  for (const entry of errorLogs) {
    merged.push({
      id: `error:${entry.id}`,
      timestamp: entry.created_at,
      source: 'error_log',
      level: entry.level,
      summary: entry.message,
      details: entry.details ?? null,
      retryOutboxEntryId: null,
    });
  }

  for (const entry of changelogEntries) {
    merged.push({
      id: `changelog:${entry.id}`,
      timestamp: entry.timestamp,
      source: 'ai_changelog',
      level: levelForChangelogOperation(entry.operation),
      summary: entry.summary,
      details: entry.mcp_tool ? `tool=${entry.mcp_tool}` : null,
      retryOutboxEntryId: null,
    });
  }

  for (const entry of recentSyncEvents) {
    const canRetry = entry.synced_at === null && entry.retry_count >= SYNC_OUTBOX_MAX_RETRIES;
    merged.push({
      id: `sync:${entry.id}`,
      timestamp: entry.created_at,
      source: 'sync_outbox',
      level: entry.retry_count > 0 ? 'warn' : 'info',
      summary: `${entry.operation} ${entry.entity_type}:${entry.entity_id}`,
      details: entry.synced_at
        ? `synced_at=${entry.synced_at}`
        : (entry.retry_count > 0 ? `retry_count=${entry.retry_count}` : null),
      retryOutboxEntryId: canRetry ? entry.id : null,
    });
  }

  return merged
    .sort((left, right) => right.timestamp.localeCompare(left.timestamp))
    .slice(0, 240);
}

export function useRecentLogs(args: UseRecentLogsArgs) {
  const { changelogEntries, errorLogs, recentSyncEvents } = args;
  return useMemo(
    () => buildRecentLogs({ changelogEntries, errorLogs, recentSyncEvents }),
    [changelogEntries, errorLogs, recentSyncEvents],
  );
}
