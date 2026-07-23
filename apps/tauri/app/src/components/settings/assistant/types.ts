import type { McpServerStatus } from '@/lib/ipc/settings';
import type { SyncOutboxEntry, SyncStatus } from '@/lib/ipc/sync';
import type {
  RunSyncBackendNowResult,
  SyncBackendConfigs,
  SyncBackendDescriptor,
} from '@/lib/syncBackend/model';
import type { SyncBackendKind } from '@/lib/syncBackend/kinds';
import type { SyncErrorEnvelope } from '@/lib/syncBackend/errorKind';

export type AssistantSnippetKey = 'claudeDesktop' | 'claudeCode' | 'codex' | 'setupPrompt';

export interface McpAssistantSnippets {
  claudeDesktop: string;
  claudeCode: string;
  codex: string;
  setupPrompt: string;
  usesCwd: boolean;
}

interface SyncStateBadge {
  label: string;
  className: string;
}

export interface AssistantSyncSettingsModel {
  draftSyncBackendKind: SyncBackendKind | null;
  runtimeConfiguredSyncBackendKind: SyncBackendKind | null;
  runtimeEffectiveSyncBackendKind: SyncBackendKind | null;
  availableSyncBackendDescriptors: SyncBackendDescriptor[];
  syncBackendConfigs: SyncBackendConfigs;
  syncEnabled: boolean;
  defaultFilesystemBridgeRootPath: string;
  syncBackendSaveState: 'idle' | 'saving' | 'saved' | 'error';
  syncRunning: boolean;
  lastSyncRunResult: RunSyncBackendNowResult | null;
  syncLastRunAt: string | null;
  syncStateBadge: SyncStateBadge | null;
  syncStatus: SyncStatus | null;
  syncPendingPreview: SyncOutboxEntry[];
  syncStatusError: string | null;
  /** envelope from the most recent "Sync Now" failure, so
   *  the card can surface a Retry / Open Settings / Open docs button
   *  inline (users who miss the toast still see the remediation on next
   *  visit). Cleared on the next successful run. */
  lastSyncErrorEnvelope: SyncErrorEnvelope | null;
  formatSyncTimestamp: (value: string | null) => string;
  onRefreshSyncStatus: () => Promise<void>;
  onSelectSyncBackend: (backendKind: SyncBackendKind) => void;
  onSyncEnabledChange: (enabled: boolean) => void;
  onFilesystemBridgeRootPathChange: (value: string) => void;
  onUseDefaultFilesystemBridgeRootPath: () => void;
  onRetrySaveSyncBackend: () => void;
  onRunSyncNow: () => Promise<void>;
  onSeedFullSync: () => Promise<void>;
  seedSyncRunning: boolean;
}

export interface AssistantMcpSetupModel {
  mcpServerStatus: McpServerStatus | null;
  mcpStatusError: string | null;
  mcpAssistantSnippets: McpAssistantSnippets | null;
  copiedSnippet: AssistantSnippetKey | null;
  onCopySnippet: (key: AssistantSnippetKey, text: string) => Promise<void>;
}

export interface AssistantSettingsViewModel {
  ready: boolean;
  sync: AssistantSyncSettingsModel;
  mcp: AssistantMcpSetupModel;
}
