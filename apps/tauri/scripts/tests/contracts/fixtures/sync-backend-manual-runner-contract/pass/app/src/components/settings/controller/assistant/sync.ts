import { runSyncBackendNow } from '../../../../lib/syncBackend';

export function useAssistantSyncController() {
  const runSyncNow = async () => {
    await runSyncBackendNow({
      backend: { kind: 'filesystem_bridge', config: { rootPath: '/tmp' } },
      maxEvents: 50,
    });
  };
  void runSyncNow;
  return { ready: true, sync: {} };
}
