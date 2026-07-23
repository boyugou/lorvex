import {
  buildSyncBackendConfig,
  listAvailableSyncBackends,
} from '../../../../lib/syncBackend';

export function useAssistantSyncController({ syncBackendSupport }) {
  const availableSyncBackendKinds = listAvailableSyncBackends(syncBackendSupport);
  const backend = buildSyncBackendConfig({
    backendKind: 'filesystem_bridge',
    backendConfigs: {
      filesystem_bridge: { rootPath: '/tmp' },
      remote_provider: {},
    },
  });
  // const effectiveSyncBackendKind = resolveSyncBackend({ requestedBackendKindRaw: 'filesystem_bridge', ...syncBackendSupport }).effectiveBackendKind;
  void availableSyncBackendKinds;
  void backend;
  return { ready: true, sync: { availableSyncBackendKinds } };
}
