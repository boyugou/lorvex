import {
  buildSyncBackendConfig,
  listAvailableSyncBackends,
  resolveSyncBackend,
  resolveStoredSyncBackendSettings,
} from '../../../../lib/syncBackend';

export function useAssistantSyncController({ syncBackendSupport }) {
  const storedSettings = resolveStoredSyncBackendSettings();
  const availableSyncBackendKinds = listAvailableSyncBackends(syncBackendSupport);
  const effectiveSyncBackendKind = resolveSyncBackend({
    requestedBackendKindRaw: 'filesystem_bridge',
    ...syncBackendSupport,
  }).effectiveBackendKind;
  const backend = buildSyncBackendConfig({
    backendKind: effectiveSyncBackendKind,
    backendConfigs: {
      filesystem_bridge: { rootPath: '/tmp' },
      remote_provider: {},
    },
  });
  void storedSettings;
  void backend;
  return { ready: true, sync: { availableSyncBackendKinds } };
}
