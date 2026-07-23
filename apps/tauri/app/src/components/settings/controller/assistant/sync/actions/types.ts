import type { Dispatch, RefObject, SetStateAction } from 'react';

import type { useI18n, TranslationKey } from '@/lib/i18n';
import { getPendingOutboxEntries, getSyncStatus } from '@/lib/ipc/sync';
import { runSyncBackendNow } from '@/lib/syncBackend/runtime';
import type {
  SyncBackendConfigs,
  SyncBackendSupportContext,
} from '@/lib/syncBackend/model';
import type { SyncBackendKind } from '@/lib/syncBackend/kinds';
import type { SyncErrorEnvelope } from '@/lib/syncBackend/errorKind';
import type { SyncBackendSaveState } from '../types';

export type AssistantSyncStatus = Awaited<ReturnType<typeof getSyncStatus>>;
export type AssistantSyncPendingPreview = Awaited<ReturnType<typeof getPendingOutboxEntries>>;
export type AssistantSyncRunResult = Awaited<ReturnType<typeof runSyncBackendNow>>;

export interface UseAssistantSyncActionsArgs {
  syncBackendSupport: SyncBackendSupportContext;
  logAssistantSettingsError: (source: string, message: string, error: unknown) => void;
  setLastSyncRunResult: Dispatch<SetStateAction<AssistantSyncRunResult | null>>;
  setSyncBackendSaveState: Dispatch<SetStateAction<SyncBackendSaveState>>;
  setSyncLastRunAt: Dispatch<SetStateAction<string | null>>;
  setSyncPendingPreview: Dispatch<SetStateAction<AssistantSyncPendingPreview>>;
  setSeedSyncRunning: Dispatch<SetStateAction<boolean>>;
  setSyncRunning: Dispatch<SetStateAction<boolean>>;
  setSyncStatus: Dispatch<SetStateAction<AssistantSyncStatus | null>>;
  setSyncStatusError: Dispatch<SetStateAction<string | null>>;
  /** envelope from the most recent failing "Sync Now".
   *  Cleared on success; consumed by SyncMethodCard to render an
   *  inline Retry / Open Settings / Open docs button mirroring the
   *  actionable toast. */
  setLastSyncErrorEnvelope: Dispatch<SetStateAction<SyncErrorEnvelope | null>>;
  setConfiguredSyncBackendKind: Dispatch<SetStateAction<SyncBackendKind | null>>;
  setSyncBackendConfigs: Dispatch<SetStateAction<SyncBackendConfigs>>;
  settingsMountedRef: RefObject<boolean>;
  seedSyncRunning: boolean;
  syncEnabled: boolean;
  syncRunning: boolean;
  syncBackendSaveState: SyncBackendSaveState;
  syncBackendConfigs: SyncBackendConfigs;
  configuredSyncBackendKind: SyncBackendKind | null;
  runtimeEffectiveSyncBackendKind: SyncBackendKind | null;
  syncBackendDraftPendingRef: RefObject<SyncBackendKind | null>;
  t: (key: TranslationKey) => string;
  format: ReturnType<typeof useI18n>['format'];
}
