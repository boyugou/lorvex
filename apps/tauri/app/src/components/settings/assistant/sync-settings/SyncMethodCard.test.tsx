import { renderToStaticMarkup } from 'react-dom/server';
import { beforeEach, describe, expect, it, vi } from 'vitest';

import type { AssistantSyncSettingsModel } from '../types';

const syncMethodCardRenderState = vi.hoisted(() => ({
  stateCallIndex: 0,
}));

vi.mock('react', async (importOriginal) => {
  const actual = await importOriginal<typeof import('react')>();
  return {
    ...actual,
    useState: vi.fn((initialValue: unknown) => {
      syncMethodCardRenderState.stateCallIndex += 1;
      if (syncMethodCardRenderState.stateCallIndex === 1) {
        return [true, vi.fn()];
      }
      const value = typeof initialValue === 'function'
        ? (initialValue as () => unknown)()
        : initialValue;
      return [value, vi.fn()];
    }),
  };
});

vi.mock('@/lib/i18n', () => ({
  useI18n: () => ({
    format: (key: string) => key,
    formatNumber: (value: number) => String(value),
    t: (key: string) => ({
      'settings.advanced': 'Advanced',
      'settings.sync': 'Sync',
      'settings.syncBackendConfigured': 'Configured',
      'settings.syncBackendEffective': 'Effective',
      'settings.syncBackendStatusDefault': 'Default',
      'settings.syncBackendStatusSelected': 'Selected',
      'settings.syncMethod': 'Sync method',
      'settings.syncMethodSharedFolder': 'Shared folder',
      'settings.syncMethodSharedFolderDesc': 'Shared folder sync',
      'settings.syncRefresh': 'Refresh',
      'settings.syncSharedFolderPath': 'Shared folder path',
      'settings.syncSharedFolderPathPlaceholder': '~/LorvexSync',
      'settings.syncUnknown': 'Unknown',
      'settings.syncUseDefaultPath': 'Use default path',
    })[key] ?? key,
  }),
}));

vi.mock('@/lib/useNetworkStatus', () => ({
  useNetworkStatus: () => ({ online: true }),
}));

vi.mock('@/lib/sync/useSyncProgress', () => ({
  useSyncProgress: () => ({
    current: 0,
    cycleId: null,
    determinate: false,
    phase: null,
    total: 0,
  }),
}));

vi.mock('@/lib/ipc/sync', () => ({
  cancelSync: vi.fn(),
}));

import { SyncMethodCard } from './SyncMethodCard';

function createSyncModel(): AssistantSyncSettingsModel {
  return {
    availableSyncBackendDescriptors: [
      {
        configEditorKind: 'filesystem_root_path',
        diagnosticsKind: 'filesystem_bridge',
        kind: 'filesystem_bridge',
      },
    ],
    defaultFilesystemBridgeRootPath: '~/LorvexSync',
    draftSyncBackendKind: 'filesystem_bridge',
    formatSyncTimestamp: (value) => value ?? 'Never',
    lastSyncErrorEnvelope: null,
    lastSyncRunResult: null,
    onFilesystemBridgeRootPathChange: vi.fn(),
    onRefreshSyncStatus: vi.fn(),
    onRetrySaveSyncBackend: vi.fn(),
    onRunSyncNow: vi.fn(),
    onSeedFullSync: vi.fn(),
    onSelectSyncBackend: vi.fn(),
    onSyncEnabledChange: vi.fn(),
    onUseDefaultFilesystemBridgeRootPath: vi.fn(),
    runtimeConfiguredSyncBackendKind: 'filesystem_bridge',
    runtimeEffectiveSyncBackendKind: 'filesystem_bridge',
    seedSyncRunning: false,
    syncBackendConfigs: {
      filesystem_bridge: {
        rootPath: '~/CustomLorvexSync',
      },
    },
    syncBackendSaveState: 'idle',
    syncEnabled: true,
    syncLastRunAt: null,
    syncPendingPreview: [],
    syncRunning: false,
    syncStateBadge: null,
    syncStatus: null,
    syncStatusError: null,
  };
}

describe('SyncMethodCard filesystem path field accessibility', () => {
  beforeEach(() => {
    syncMethodCardRenderState.stateCallIndex = 0;
  });

  it('associates the visible shared-folder path label with the input', () => {
    const html = renderToStaticMarkup(<SyncMethodCard sync={createSyncModel()} />);

    const labelFor = html.match(/<label\b[^>]*for="([^"]+)"[^>]*>Shared folder path<\/label>/)?.[1];
    expect(labelFor).toBeTruthy();
    expect(html).toContain(`<input id="${labelFor}"`);
    expect(html).toContain('placeholder="~/LorvexSync"');
  });
});
