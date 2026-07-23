import assert from 'node:assert/strict';
import test from 'node:test';

import {
  resolveStoredSyncBackendSettings,
} from '../../../app/src/lib/syncBackend/preferences.ts';

test('resolveStoredSyncBackendSettings adopts the default filesystem root path only when backend config is missing', () => {
  assert.deepEqual(
    resolveStoredSyncBackendSettings({
      enabledRaw: null,
      backendKindRaw: null,
      backendConfigsRaw: null,
      defaultFilesystemBridgeRootPath: '  ~/Lorvex Sync  ',
      syncBackendSupport: { availableBackendKinds: ['filesystem_bridge'] },
    }),
    {
      settings: {
        enabled: false,
        configuredBackendKind: null,
        effectiveBackendKind: 'filesystem_bridge',
        backendConfigs: {
          filesystem_bridge: { rootPath: '~/Lorvex Sync' },
        },
      },
      shouldPersistNormalized: true,
    },
  );
  assert.deepEqual(
    resolveStoredSyncBackendSettings({
      enabledRaw: 'true',
      backendKindRaw: '"filesystem_bridge"',
      backendConfigsRaw: '{"filesystem_bridge":{"rootPath":"  /tmp/lorvex-sync  "}}',
      defaultFilesystemBridgeRootPath: '  ~/Lorvex Sync  ',
      syncBackendSupport: { availableBackendKinds: ['filesystem_bridge'] },
    }),
    {
      settings: {
        enabled: true,
        configuredBackendKind: 'filesystem_bridge',
        effectiveBackendKind: 'filesystem_bridge',
        backendConfigs: {
          filesystem_bridge: { rootPath: '/tmp/lorvex-sync' },
        },
      },
      shouldPersistNormalized: false,
    },
  );
});
