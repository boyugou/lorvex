import assert from 'node:assert/strict';
import test from 'node:test';

import {
  getDefaultSyncBackendKind,
} from '../../../app/src/lib/syncBackend/model.ts';
import {
  SYNC_BACKEND_FILESYSTEM_BRIDGE,
} from '../../../app/src/lib/syncBackend/kinds.ts';
import {
  parseStoredSyncBackendConfigsPreference,
  parseStoredSyncBackendConfigsPreferenceState,
  parseStoredSyncBackendKindPreference,
  parseStoredSyncBackendKindPreferenceState,
  parseStoredSyncEnabledPreference,
  resolveStoredSyncBackendSettings,
} from '../../../app/src/lib/syncBackend/preferences.ts';

test('sync backend preference parsers trim persisted backend kind and filesystem root path', () => {
  const backendState = parseStoredSyncBackendKindPreferenceState(
    '" filesystem_bridge "',
    { availableBackendKinds: [SYNC_BACKEND_FILESYSTEM_BRIDGE] },
  );
  const backendConfigs = parseStoredSyncBackendConfigsPreference(
    '{"filesystem_bridge":{"rootPath":"  ~/Lorvex Sync  "}}',
  );

  assert.equal(backendState.configuredBackendKind, SYNC_BACKEND_FILESYSTEM_BRIDGE);
  assert.equal(backendState.effectiveBackendKind, SYNC_BACKEND_FILESYSTEM_BRIDGE);
  assert.equal(
    backendConfigs.filesystem_bridge.rootPath,
    '~/Lorvex Sync',
  );
});

test('sync backend kind parsing falls back for missing, malformed, and unsupported payloads', () => {
  assert.equal(
    parseStoredSyncBackendKindPreference(null, { availableBackendKinds: [SYNC_BACKEND_FILESYSTEM_BRIDGE] }),
    SYNC_BACKEND_FILESYSTEM_BRIDGE,
  );
  assert.equal(
    parseStoredSyncBackendKindPreference('not json', { availableBackendKinds: [SYNC_BACKEND_FILESYSTEM_BRIDGE] }),
    getDefaultSyncBackendKind({ availableBackendKinds: [SYNC_BACKEND_FILESYSTEM_BRIDGE] }),
  );
  assert.equal(
    parseStoredSyncBackendKindPreference('123', { availableBackendKinds: [SYNC_BACKEND_FILESYSTEM_BRIDGE] }),
    getDefaultSyncBackendKind({ availableBackendKinds: [SYNC_BACKEND_FILESYSTEM_BRIDGE] }),
  );
  assert.equal(
    parseStoredSyncBackendKindPreference('"remote_provider"', { availableBackendKinds: [SYNC_BACKEND_FILESYSTEM_BRIDGE] }),
    SYNC_BACKEND_FILESYSTEM_BRIDGE,
  );
  assert.deepEqual(
    parseStoredSyncBackendKindPreferenceState('"remote_provider"', {
      availableBackendKinds: [SYNC_BACKEND_FILESYSTEM_BRIDGE],
    }),
    {
      configuredBackendKind: null,
      effectiveBackendKind: SYNC_BACKEND_FILESYSTEM_BRIDGE,
      malformed: true,
      malformedReason: 'unknown_backend_kind',
    },
  );
  assert.deepEqual(
    parseStoredSyncBackendKindPreferenceState('not json', {
      availableBackendKinds: [SYNC_BACKEND_FILESYSTEM_BRIDGE],
    }),
    {
      configuredBackendKind: null,
      effectiveBackendKind: SYNC_BACKEND_FILESYSTEM_BRIDGE,
      malformed: true,
      malformedReason: 'invalid_json',
    },
  );
  assert.deepEqual(
    parseStoredSyncBackendKindPreferenceState('"totally_custom_backend"', {
      availableBackendKinds: [SYNC_BACKEND_FILESYSTEM_BRIDGE],
    }),
    {
      configuredBackendKind: null,
      effectiveBackendKind: SYNC_BACKEND_FILESYSTEM_BRIDGE,
      malformed: true,
      malformedReason: 'unknown_backend_kind',
    },
  );
});

test('sync enabled and backend config parsers fail closed for malformed preference payloads', () => {
  assert.equal(parseStoredSyncEnabledPreference(null), false);
  assert.equal(parseStoredSyncEnabledPreference('true'), true);
  assert.equal(parseStoredSyncEnabledPreference('"true"'), false);
  assert.equal(parseStoredSyncEnabledPreference('not json'), false);

  assert.deepEqual(
    parseStoredSyncBackendConfigsPreference('not json'),
    {
      filesystem_bridge: { rootPath: '' },
    },
  );
  assert.deepEqual(
    parseStoredSyncBackendConfigsPreference('{"filesystem_bridge":{"rootPath":123}}'),
    {
      filesystem_bridge: { rootPath: '' },
    },
  );
  assert.deepEqual(
    parseStoredSyncBackendConfigsPreference(
      '{"filesystem_bridge":{"rootPath":"~/Lorvex Sync"},"remote_provider":{},"experimental":true}',
    ),
    {
      filesystem_bridge: { rootPath: '' },
    },
  );
  assert.deepEqual(
    parseStoredSyncBackendConfigsPreference(
      '{"filesystem_bridge":{"rootPath":"~/Lorvex Sync","mode":"mirror"}}',
    ),
    {
      filesystem_bridge: { rootPath: '' },
    },
  );
  assert.deepEqual(
    parseStoredSyncBackendConfigsPreference(
      '{"filesystem_bridge":{"rootPath":"~/Lorvex Sync"},"remote_provider":{"scope":"private"}}',
    ),
    {
      filesystem_bridge: { rootPath: '' },
    },
  );
});

test('sync backend config state marks malformed and missing filesystem root path payloads', () => {
  assert.deepEqual(
    parseStoredSyncBackendConfigsPreferenceState('{}'),
    {
      backendConfigs: {
        filesystem_bridge: { rootPath: '' },
      },
      malformed: true,
      missingFilesystemRootPath: true,
    },
  );

  assert.deepEqual(
    parseStoredSyncBackendConfigsPreferenceState('{"filesystem_bridge":{"rootPath":" ~/Lorvex "}}'),
    {
      backendConfigs: {
        filesystem_bridge: { rootPath: '~/Lorvex' },
      },
      malformed: false,
      missingFilesystemRootPath: false,
    },
  );
});

test('sync backend resolution adopts and normalizes the default filesystem path for malformed partial config', () => {
  const resolved = resolveStoredSyncBackendSettings({
    enabledRaw: 'true',
    backendKindRaw: '"filesystem_bridge"',
    backendConfigsRaw: '{}',
    defaultFilesystemBridgeRootPath: '  ~/Lorvex Sync  ',
    syncBackendSupport: {
      availableBackendKinds: [SYNC_BACKEND_FILESYSTEM_BRIDGE],
    },
  });

  assert.deepEqual(resolved, {
    settings: {
      enabled: true,
      configuredBackendKind: SYNC_BACKEND_FILESYSTEM_BRIDGE,
      effectiveBackendKind: SYNC_BACKEND_FILESYSTEM_BRIDGE,
      backendConfigs: {
        filesystem_bridge: { rootPath: '~/Lorvex Sync' },
      },
    },
    shouldPersistNormalized: true,
  });
});
