import { useAssistantSettingsController } from './settings/controller/useAssistantSettingsController';

export default function SettingsView() {
  const assistantSettings = useAssistantSettingsController({
    syncBackendSupport: {
      availableBackendKinds: ['remote_provider', 'filesystem_bridge'],
    },
  });
  void assistantSettings;
  return null;
}
