import { getNavigatorConnection, type NavigatorConnectionLike } from './network';

type BackgroundSyncWindowEvent = 'focus' | 'pageshow' | 'resume' | 'online' | 'offline';
type TimeoutHandle = ReturnType<typeof globalThis.setTimeout>;

export interface BackgroundSyncPendingWait {
  handle: TimeoutHandle;
  resolve: () => void;
}

interface BackgroundSyncBrowserHostDeps {
  windowTarget?: Pick<Window, 'addEventListener' | 'removeEventListener'> | undefined;
  documentTarget?: Pick<Document, 'addEventListener' | 'removeEventListener' | 'visibilityState'> | undefined;
  navigatorState?: Pick<Navigator, 'onLine'> | undefined;
  connectionTarget?: NavigatorConnectionLike | null | undefined;
  timerHost: Pick<typeof globalThis, 'setTimeout' | 'clearTimeout'>;
}

interface BackgroundSyncBrowserHost {
  isOnline(): boolean;
  isVisible(): boolean;
  setTimeout(callback: () => void, delayMs: number): () => void;
  wait(
    delayMs: number,
    isCancelled: () => boolean,
    pendingWaits: Set<BackgroundSyncPendingWait>,
  ): Promise<void>;
  clearPendingWaits(pendingWaits: Set<BackgroundSyncPendingWait>): void;
  addWindowListener(type: BackgroundSyncWindowEvent, listener: () => void): () => void;
  addVisibilityListener(listener: () => void): () => void;
  addConnectionChangeListener(listener: () => void): () => void;
}

export function createBackgroundSyncBrowserHost(
  deps: BackgroundSyncBrowserHostDeps,
): BackgroundSyncBrowserHost {
  const {
    windowTarget,
    documentTarget,
    navigatorState,
    connectionTarget,
    timerHost,
  } = deps;

  return {
    isOnline(): boolean {
      return typeof navigatorState?.onLine === 'boolean' ? navigatorState.onLine : true;
    },

    isVisible(): boolean {
      return documentTarget?.visibilityState !== 'hidden';
    },

    setTimeout(callback: () => void, delayMs: number): () => void {
      const handle = timerHost.setTimeout(callback, delayMs);
      return () => {
        timerHost.clearTimeout(handle as TimeoutHandle);
      };
    },

    wait(
      delayMs: number,
      isCancelled: () => boolean,
      pendingWaits: Set<BackgroundSyncPendingWait>,
    ): Promise<void> {
      return new Promise<void>((resolve) => {
        if (isCancelled()) {
          resolve();
          return;
        }
        let settled = false;
        let record: BackgroundSyncPendingWait | null = null;
        const resolveWait = () => {
          if (settled) return;
          settled = true;
          if (record !== null) {
            pendingWaits.delete(record);
          }
          resolve();
        };
        const handle = timerHost.setTimeout(resolveWait, delayMs);
        record = { handle: handle as TimeoutHandle, resolve: resolveWait };
        pendingWaits.add(record);
      });
    },

    clearPendingWaits(pendingWaits: Set<BackgroundSyncPendingWait>): void {
      for (const wait of Array.from(pendingWaits)) {
        timerHost.clearTimeout(wait.handle);
        wait.resolve();
      }
      pendingWaits.clear();
    },

    addWindowListener(type: BackgroundSyncWindowEvent, listener: () => void): () => void {
      if (!windowTarget) {
        return () => {};
      }
      windowTarget.addEventListener(type, listener);
      return () => {
        windowTarget.removeEventListener(type, listener);
      };
    },

    addVisibilityListener(listener: () => void): () => void {
      if (!documentTarget) {
        return () => {};
      }
      documentTarget.addEventListener('visibilitychange', listener);
      return () => {
        documentTarget.removeEventListener('visibilitychange', listener);
      };
    },

    addConnectionChangeListener(listener: () => void): () => void {
      if (
        typeof connectionTarget?.addEventListener !== 'function'
        || typeof connectionTarget?.removeEventListener !== 'function'
      ) {
        return () => {};
      }
      connectionTarget.addEventListener('change', listener);
      return () => {
        connectionTarget.removeEventListener?.('change', listener);
      };
    },
  };
}

export function createBrowserBackgroundSyncBrowserHost(): BackgroundSyncBrowserHost {
  return createBackgroundSyncBrowserHost({
    windowTarget: typeof window === 'undefined' ? undefined : window,
    documentTarget: typeof document === 'undefined' ? undefined : document,
    navigatorState: typeof navigator === 'undefined' ? undefined : navigator,
    connectionTarget: getNavigatorConnection(),
    timerHost: globalThis,
  });
}
