import { buildSyncBackendConfig, runSyncBackend } from './syncBackend';

export async function tick(): Promise<void> {
  // const resolved = resolveSyncBackend('filesystem_bridge');
  const backend = buildSyncBackendConfig({
    backendKind: 'filesystem_bridge',
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
}
