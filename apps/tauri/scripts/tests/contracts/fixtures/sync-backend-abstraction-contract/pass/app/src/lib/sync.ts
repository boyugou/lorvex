import { buildSyncBackendConfig, resolveSyncBackend, runSyncBackend } from './syncBackend';

export async function tick(): Promise<void> {
  const resolved = resolveSyncBackend('filesystem_bridge');
  const backend = buildSyncBackendConfig({
    backendKind: resolved.effectiveBackendKind,
    backendConfigs: {
      filesystem_bridge: { rootPath: '/tmp' },
      remote_provider: {},
    },
  });
  await runSyncBackend({
    backend,
    maxConsecutiveRepulls: 2,
    isCancelled: () => false,
  });
  void resolved;
}
