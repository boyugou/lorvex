import { runRemoteProviderSync } from '../../../../lib/ipc';
import { runSyncBackendNow } from '../../../../lib/syncBackend';

export function useAssistantSyncController() {
  const runSyncNow = async () => {
    await runSyncBackendNow({
      backend: { kind: 'remote_provider', config: {} },
      maxEvents: 50,
    });
    await runRemoteProviderSync(50);
  };
  void runSyncNow;
  return { ready: true, sync: {} };
}
