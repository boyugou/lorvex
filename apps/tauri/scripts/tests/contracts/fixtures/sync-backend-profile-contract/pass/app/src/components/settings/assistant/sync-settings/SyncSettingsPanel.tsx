interface AssistantSyncSettingsModel {
  availableSyncBackendDescriptors: Array<{ kind: string }>;
}

interface SyncSettingsPanelProps {
  sync: AssistantSyncSettingsModel;
}

export function SyncSettingsPanel({ sync }: SyncSettingsPanelProps) {
  const { availableSyncBackendDescriptors } = sync;

  return (
    <>
      {availableSyncBackendDescriptors.map((descriptor) => <button key={descriptor.kind} type="button" />)}
    </>
  );
}
