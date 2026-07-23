import { useEffect } from 'react';
import type { QueryClient } from '@tanstack/react-query';
import { listen } from '@tauri-apps/api/event';
import { getCurrentWebviewWindow } from '@tauri-apps/api/webviewWindow';

import { reportClientError } from '@/lib/errors/errorLogging';
import { IPC_MUTATION_BROADCAST_EVENT } from '@/lib/ipc/core';
import { acknowledgePendingDeepLink, consumePendingDeepLink } from '@/lib/ipc/runtime';
import type { DeepLinkTarget } from '@/lib/ipc/runtime';
import { invalidateExternalMutationQueries, invalidateQueriesForEntity } from '@/lib/query/queryKeys';
import { startExternalMutationSubscriptionRuntime } from '@/lib/useExternalMutationSubscription.runtime';
import { startMainWindowDeepLinkSubscriptionRuntime } from './useMainWindowDeepLinkSubscription.runtime';

const DATA_CHANGED_EVENT = 'lorvex://data-changed';

interface UseMainWindowSubscriptionsOptions {
  applyDeepLinkTarget: (target: DeepLinkTarget | null) => void;
  queryClient: QueryClient;
}

export function useMainWindowSubscriptions({
  applyDeepLinkTarget,
  queryClient,
}: UseMainWindowSubscriptionsOptions) {
  useEffect(() => {
    // Audit react-race#1: capture own window label so we can skip
    // self-originated broadcasts and avoid the same-microtask
    // invalidate-then-setQueryData race.
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

  useEffect(() => {
    return startMainWindowDeepLinkSubscriptionRuntime({
      acknowledgePendingDeepLink,
      applyDeepLinkTarget,
      consumePendingDeepLink,
      listenDeepLinkOpen: (handler) =>
        listen<DeepLinkTarget>('deep-link://open', (event) => {
          handler(event.payload);
        }),
      reportError: (scope, message, error, details) => reportClientError(scope, message, error, details),
    });
  }, [applyDeepLinkTarget]);
}
