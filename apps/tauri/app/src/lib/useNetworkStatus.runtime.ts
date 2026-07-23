interface NetworkConnectionTarget {
  addEventListener?: (type: 'change', listener: () => void) => void;
  removeEventListener?: (type: 'change', listener: () => void) => void;
}

export type NetworkStatusEvent =
  | { type: 'online' }
  | { type: 'offline' }
  // navigator.connection change events don't carry a boolean themselves;
  // the listener re-reads `navigator.onLine` and dispatches a sync with
  // the current value. We accept the resolved boolean directly so the
  // reducer stays a pure function of its input.
  | { type: 'sync'; online: boolean };

export interface NetworkStatusState {
  readonly online: boolean;
}

interface NetworkStatusRuntimeDeps {
  addWindowListener: ((type: 'online' | 'offline', listener: () => void) => () => void) | null;
  connection?: NetworkConnectionTarget | undefined;
  dispatch: (event: NetworkStatusEvent) => void;
  readOnline: () => boolean;
}

export function readNormalizedOnlineStatus(rawValue: unknown): boolean {
  return typeof rawValue === 'boolean' ? rawValue : true;
}

export function reduceNetworkStatus(
  state: NetworkStatusState,
  event: NetworkStatusEvent,
): NetworkStatusState {
  switch (event.type) {
    case 'online':
      // Idempotent re-fires preserve identity so React skips the render.
      return state.online ? state : { online: true };
    case 'offline':
      return state.online ? { online: false } : state;
    case 'sync':
      return state.online === event.online ? state : { online: event.online };
  }
}

export function installNetworkStatusRuntime(
  deps: NetworkStatusRuntimeDeps,
): () => void {
  const handleOnline = () => deps.dispatch({ type: 'online' });
  const handleOffline = () => deps.dispatch({ type: 'offline' });
  const handleConnectionChange = () => deps.dispatch({
    type: 'sync',
    online: deps.readOnline(),
  });

  const removeOnline = deps.addWindowListener
    ? deps.addWindowListener('online', handleOnline)
    : () => {};
  const removeOffline = deps.addWindowListener
    ? deps.addWindowListener('offline', handleOffline)
    : () => {};
  const removeConnection = installConnectionChangeListener(
    deps.connection,
    handleConnectionChange,
  );

  handleConnectionChange();

  return () => {
    removeConnection();
    removeOffline();
    removeOnline();
  };
}

export function readBrowserNetworkOnlineStatus(): boolean {
  try {
    return readNormalizedOnlineStatus(globalThis.navigator?.onLine);
  } catch {
    return true;
  }
}

export function createBrowserNetworkStatusRuntimeDeps(
  dispatch: (event: NetworkStatusEvent) => void,
): NetworkStatusRuntimeDeps {
  return {
    addWindowListener: createBrowserWindowListenerHost(),
    connection: readBrowserConnectionTarget(),
    dispatch,
    readOnline: readBrowserNetworkOnlineStatus,
  };
}

function createBrowserWindowListenerHost(): NetworkStatusRuntimeDeps['addWindowListener'] {
  try {
    const target = globalThis.window;
    if (
      typeof target?.addEventListener !== 'function'
      || typeof target?.removeEventListener !== 'function'
    ) {
      return null;
    }

    return (type, listener) => {
      target.addEventListener(type, listener);
      return () => target.removeEventListener(type, listener);
    };
  } catch {
    return null;
  }
}

function readBrowserConnectionTarget(): NetworkConnectionTarget | undefined {
  try {
    return (globalThis.navigator as Navigator & {
      connection?: NetworkConnectionTarget;
    } | undefined)?.connection;
  } catch {
    return undefined;
  }
}

function installConnectionChangeListener(
  connection: NetworkConnectionTarget | undefined,
  listener: () => void,
): () => void {
  if (!connection) {
    return () => {};
  }

  if (
    typeof connection.addEventListener === 'function'
    && typeof connection.removeEventListener === 'function'
  ) {
    connection.addEventListener('change', listener);
    return () => connection.removeEventListener?.('change', listener);
  }

  return () => {};
}
