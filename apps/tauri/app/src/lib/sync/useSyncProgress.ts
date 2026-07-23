import { useEffect, useState } from 'react';
import { listen, type UnlistenFn } from '@tauri-apps/api/event';

import { reportClientError } from '../errors/errorLogging';
import {
  IDLE_SYNC_PROGRESS_STATE,
  startSyncProgressSubscription,
  type SyncProgressPayload,
  type SyncProgressState,
} from './useSyncProgress.logic';

/**
 * React hook that subscribes to the sync-progress event channel and
 * returns the latest state for rendering in the Settings → Sync
 * panel. Subscribes once per mount, tears down on unmount. Errors
 * during `listen()` registration are reported through the standard
 * client error sink — they must not crash the panel.
 */
export function useSyncProgress(): SyncProgressState {
  const [state, setState] = useState<SyncProgressState>(IDLE_SYNC_PROGRESS_STATE);

  useEffect(() => {
    const stop = startSyncProgressSubscription({
      listen: (event, handler) =>
        listen<SyncProgressPayload>(event, handler as (event: { payload: SyncProgressPayload }) => void)
          .then((fn) => fn as UnlistenFn),
      setState,
      reportError: (error) => {
        reportClientError(
          'sync.progress.listen',
          'Failed to subscribe to sync progress events',
          error,
        );
      },
    });

    return stop;
  }, []);

  return state;
}
