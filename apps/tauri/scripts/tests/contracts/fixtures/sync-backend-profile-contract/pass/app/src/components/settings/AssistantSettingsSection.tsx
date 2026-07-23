import type { SyncBackendDescriptor } from '../../lib/syncBackend';

interface Props {
  availableSyncBackendDescriptors: SyncBackendDescriptor[];
}

export function AssistantSettingsSection({ availableSyncBackendDescriptors }: Props) {
  return (
    <div>
      {availableSyncBackendDescriptors.map((descriptor) => (
        <div key={descriptor.kind}>{descriptor.configEditorKind === 'filesystem_root_path' ? 'dir' : 'none'}</div>
      ))}
    </div>
  );
}
