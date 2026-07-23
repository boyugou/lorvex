import { useI18n } from '@/lib/i18n';

import type { SnapshotActionArgs } from '../support';

import { useSnapshotImportAction } from './import';
import { useSnapshotPayloadActions } from './payload';

export function useDataSnapshotActions(args: SnapshotActionArgs) {
  const { t, format } = useI18n();

  const payloadActions = useSnapshotPayloadActions({ ...args, t, format });
  const handleImportSnapshot = useSnapshotImportAction({ ...args, t });

  return {
    ...payloadActions,
    handleImportSnapshot,
  };
}
