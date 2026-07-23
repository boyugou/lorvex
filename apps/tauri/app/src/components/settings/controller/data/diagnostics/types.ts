import type {
  Dispatch,
  RefObject,
  SetStateAction,
} from 'react';

import type { TranslationKey } from '@/lib/i18n';
import type { ErrorLogEntry } from '@/lib/ipc/settings';
import type { SyncOutboxEntry } from '@/lib/ipc/sync';
import type { ChangelogEntry } from '@/lib/ipc/tasks/models';
import type { DiagnosticsFilters } from '@/components/settings/data/diagnostics.logic';
import type { RecentLogItem, RefreshErrorLogsResult } from '@/components/settings/data/types';

export interface DataDiagnosticsControls {
  errorLogs: ErrorLogEntry[];
  errorLogsBusy: boolean;
  errorLogsActionMessage: string | null;
  recentLogsActionMessage: string | null;
  recentLogs: RecentLogItem[];
  setErrorLogsActionMessage: (message: string | null) => void;
  setRecentLogsActionMessage: (message: string | null) => void;
  refreshErrorLogs: (silent?: boolean, announce?: boolean) => Promise<RefreshErrorLogsResult | null>;
  logDataSettingsError: (source: string, message: string, error: unknown) => void;
  handleRefreshErrorLogs: (announce?: boolean) => Promise<void>;
  handleCopyErrorLogs: () => Promise<void>;
  handleClearErrorLogs: () => Promise<void>;
  handleCopyRecentLogs: () => Promise<void>;
  handleRetrySyncOutboxEntry: (id: string) => Promise<void>;
  setDiagnosticsFilters: (filters: DiagnosticsFilters) => void;
}

export interface UseDataDiagnosticsControlsArgs {
  settingsMountedRef: RefObject<boolean>;
}

export interface UseDataDiagnosticsRefreshArgs {
  settingsMountedRef: RefObject<boolean>;
  t: (key: TranslationKey) => string;
}

export interface UseRecentLogsArgs {
  changelogEntries: ChangelogEntry[];
  errorLogs: ErrorLogEntry[];
  recentSyncEvents: SyncOutboxEntry[];
}

export interface UseDataDiagnosticsActionsArgs {
  errorLogs: ErrorLogEntry[];
  errorLogsBusy: boolean;
  logDataSettingsError: (source: string, message: string, error: unknown) => void;
  recentLogs: RecentLogItem[];
  refreshErrorLogs: (silent?: boolean, announce?: boolean) => Promise<RefreshErrorLogsResult | null>;
  setErrorLogsActionMessage: Dispatch<SetStateAction<string | null>>;
  setRecentLogsActionMessage: Dispatch<SetStateAction<string | null>>;
  setErrorLogsBusy: Dispatch<SetStateAction<boolean>>;
  settingsMountedRef: RefObject<boolean>;
  t: (key: TranslationKey) => string;
}
