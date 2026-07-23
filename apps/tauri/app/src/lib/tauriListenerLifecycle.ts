export type TauriUnlistenFn = () => void;

export interface AsyncTauriListenerScope {
  add(
    unlistenPromise: Promise<TauriUnlistenFn>,
    onRegistrationError: (error: unknown) => void,
  ): void;
  dispose(): void;
}

function safelyUnlisten(unlisten: TauriUnlistenFn): void {
  try {
    unlisten();
  } catch {
    // Tauri unlisten callbacks are idempotent from the caller's point of view.
  }
}

export function createAsyncTauriListenerScope(): AsyncTauriListenerScope {
  let disposed = false;
  const unlisteners = new Set<TauriUnlistenFn>();

  const release = (unlisten: TauriUnlistenFn) => {
    unlisteners.delete(unlisten);
    safelyUnlisten(unlisten);
  };

  return {
    add(unlistenPromise, onRegistrationError) {
      void unlistenPromise
        .then((unlisten) => {
          if (disposed) {
            safelyUnlisten(unlisten);
            return;
          }
          unlisteners.add(unlisten);
        })
        .catch(onRegistrationError);
    },
    dispose() {
      if (disposed) return;
      disposed = true;
      for (const unlisten of [...unlisteners]) {
        release(unlisten);
      }
    },
  };
}
