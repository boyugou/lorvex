import { useEffect } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import { listen } from '@tauri-apps/api/event';
import { getCurrentWebviewWindow } from '@tauri-apps/api/webviewWindow';

import { IPC_MUTATION_BROADCAST_EVENT } from '@/lib/ipc/core';
import { invalidateExternalMutationQueries, invalidateQueriesForEntity } from './query/queryKeys';
import { reportClientError } from './errors/errorLogging';
import { startExternalMutationSubscriptionRuntime } from './useExternalMutationSubscription.runtime';

const DATA_CHANGED_EVENT = 'lorvex://data-changed';

/**
 * Subscribe to external mutation broadcasts (MCP writes, sync) and
 * data-changed events from the Rust backend.
 *
   * Used by overlay windows (popover, focus mode) so all
 * surfaces stay up-to-date when data changes externally. The main window
 * uses `useMainWindowSubscriptions` which adds deep-link handling plus a
 * one-time catch-up invalidation for data that mutated between the
 * previous session closing and this session opening.
 *
 * overlay windows now do a predicate-guarded catch-up
 * invalidation once both `listen()` promises settle. The predicate-
 * based `invalidateExternalMutationQueries` is cheap when the cache
 * is empty (a fresh popover open matches zero queries), and covers
 * the 30-200 ms race where a peer broadcast fires between mount and
 * listener registration. A popover that persists across hide/show
 * retains its QueryClient — without this catch-up it showed stale
 * data from the previous show until the next broadcast or refetch.
 */
export function useExternalMutationSubscription(): void {
  const queryClient = useQueryClient();

  useEffect(() => {
    // Audit react-race#1: capture the current window's label so we can
    // skip self-originated broadcasts (Tauri v2 `emit()` dispatches to
    // the emitting webview too, which was causing each mutation to
    // immediately invalidate its own cache and race `onSuccess`
    // `setQueryData`).
    let ownLabel = '';
    try {
      ownLabel = getCurrentWebviewWindow().label;
    } catch {
      /* non-Tauri test context */
    }

    return startExternalMutationSubscriptionRuntime({
      ownWindowLabel: ownLabel,
      invalidateExternalMutationQueries: () => invalidateExternalMutationQueries(queryClient),
      invalidateQueriesForEntity: (entity) => invalidateQueriesForEntity(queryClient, entity),
      reportError: (scope, message, error) => reportClientError(scope, message, error),
      listenMutationBroadcast: (handler) =>
        listen<{ source_window?: string }>(IPC_MUTATION_BROADCAST_EVENT, (event) => {
          const sourceWindow = event.payload?.source_window;
          handler(sourceWindow === undefined ? {} : { source_window: sourceWindow });
        }),
      listenDataChanged: (handler) =>
        listen<{ entity: string }>(DATA_CHANGED_EVENT, (event) => {
          handler({ entity: event.payload?.entity });
        }),
    });
  }, [queryClient]);
}
