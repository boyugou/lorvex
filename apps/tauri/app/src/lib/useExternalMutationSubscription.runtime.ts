import {
  createEntityInvalidationCoalescer,
  shouldIgnoreMutationBroadcast,
} from './useExternalMutationSubscription.logic';
import { createAsyncTauriListenerScope, type TauriUnlistenFn } from './tauriListenerLifecycle';

export type RuntimeUnlisten = () => void;

interface ExternalMutationSubscriptionRuntimeDeps {
  ownWindowLabel: string;
  invalidateExternalMutationQueries: () => void;
  invalidateQueriesForEntity: (entity: string) => void;
  reportError: (scope: string, message: string, error: unknown) => void;
  listenMutationBroadcast: (
    handler: (payload: { source_window?: string }) => void,
  ) => Promise<RuntimeUnlisten>;
  listenDataChanged: (
    handler: (payload: { entity?: string }) => void,
  ) => Promise<RuntimeUnlisten>;
  createCoalescer?: (
    invalidateEntity: (entity: string) => void,
  ) => { schedule(entity: string): void; clear(): void };
}

export function startExternalMutationSubscriptionRuntime(
  deps: ExternalMutationSubscriptionRuntimeDeps,
): RuntimeUnlisten {
  const {
    ownWindowLabel,
    invalidateExternalMutationQueries,
    invalidateQueriesForEntity,
    reportError,
    listenMutationBroadcast,
    listenDataChanged,
    createCoalescer = (invalidateEntity) =>
      createEntityInvalidationCoalescer(invalidateEntity, 50),
  } = deps;

  let cancelled = false;
  let mutationSettled = false;
  let dataChangedSettled = false;
  let catchupRan = false;
  const listeners = createAsyncTauriListenerScope();

  const coalescer = createCoalescer((entity) => {
    if (cancelled) return;
    invalidateQueriesForEntity(entity);
  });

  const runCatchupOnce = () => {
    if (cancelled || catchupRan || !mutationSettled || !dataChangedSettled) return;
    catchupRan = true;
    invalidateExternalMutationQueries();
  };

  const markMutationSettled = () => {
    mutationSettled = true;
    runCatchupOnce();
  };
  const markDataChangedSettled = () => {
    dataChangedSettled = true;
    runCatchupOnce();
  };

  const mutationListener = listenMutationBroadcast((payload) => {
    if (cancelled) return;
    if (shouldIgnoreMutationBroadcast(ownWindowLabel, payload.source_window)) return;
    invalidateExternalMutationQueries();
  })
    .then((fn): TauriUnlistenFn => {
      mutationSettled = true;
      runCatchupOnce();
      return fn;
    })
    .catch((error) => {
      reportError(
        'external.listen.mutationBroadcast',
        'Failed to subscribe to mutation broadcasts',
        error,
      );
      markMutationSettled();
      return () => {};
    });
  listeners.add(mutationListener, () => {});

  const dataChangedListener = listenDataChanged((payload) => {
    if (cancelled) return;
    const entity = payload.entity;
    if (entity) {
      coalescer.schedule(entity);
    }
  })
    .then((fn): TauriUnlistenFn => {
      dataChangedSettled = true;
      runCatchupOnce();
      return fn;
    })
    .catch((error) => {
      reportError(
        'external.listen.dataChanged',
        'Failed to subscribe to data-changed events',
        error,
      );
      markDataChangedSettled();
      return () => {};
    });
  listeners.add(dataChangedListener, () => {});

  return () => {
    cancelled = true;
    listeners.dispose();
    coalescer.clear();
  };
}
