import type { RefObject } from 'react';

import type { SyncBackendSupportContext } from '@/lib/syncBackend/model';
import type { AssistantSyncSettingsModel } from '@/components/settings/assistant/types';

export type SyncBackendSaveState = 'idle' | 'saving' | 'saved' | 'error';

export interface AssistantSyncControllerState {
  ready: boolean;
  sync: AssistantSyncSettingsModel;
}

export interface UseAssistantSyncControllerArgs {
  syncBackendSupport: SyncBackendSupportContext;
  settingsMountedRef: RefObject<boolean>;
  formatSyncTimestamp: (value: string | null) => string;
  logAssistantSettingsError: (source: string, message: string, error: unknown) => void;
}
