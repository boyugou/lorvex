import { useAssistantSyncController } from './assistant/sync';

export function useAssistantSettingsController(args) {
  const sync = useAssistantSyncController(args);
  return { ready: sync.ready, sync: sync.sync };
}
