export interface SnapshotStatus {
  tone: 'info' | 'success' | 'error';
  message: string;
}

export interface RefreshErrorLogsResult {
  errorCount: number;
  recentCount: number;
}

export interface RecentLogItem {
  id: string;
  timestamp: string;
  source: 'error_log' | 'ai_changelog' | 'sync_outbox';
  level: string;
  summary: string;
  details: string | null;
  retryOutboxEntryId: string | null;
}
