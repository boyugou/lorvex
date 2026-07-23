interface AppWindowErrorEventLike {
  colno?: number | undefined;
  error?: unknown;
  filename?: string | undefined;
  lineno?: number | undefined;
  message?: string | undefined;
}

interface AppPromiseRejectionEventLike {
  reason: unknown;
}

interface AppWindowEventTargetLike {
  addEventListener: (
    type: 'error' | 'unhandledrejection',
    listener: EventListener,
  ) => void;
  removeEventListener: (
    type: 'error' | 'unhandledrejection',
    listener: EventListener,
  ) => void;
}

interface AppRuntimeDeps {
  installQuitFlushListener: () => () => void;
  reportClientError: (
    source: string,
    message: string,
    error?: unknown,
    details?: string | undefined,
  ) => void;
  windowTarget: AppWindowEventTargetLike;
}

interface AppRuntime {
  cleanup: () => void;
}

export function buildWindowErrorReport(
  event: AppWindowErrorEventLike,
): { details?: string | undefined; message: string; source: 'frontend.window' } | null {
  if (event.message?.includes('ResizeObserver loop')) return null;
  const details = [
    event.filename ? `file=${event.filename}` : null,
    event.lineno ? `line=${event.lineno}` : null,
    event.colno ? `col=${event.colno}` : null,
    event.error ? `error=${String(event.error)}` : null,
  ].filter(Boolean).join(' ');
  return {
    source: 'frontend.window',
    message: event.message || 'Unhandled window error',
    details: details || undefined,
  };
}

export function buildUnhandledRejectionReport(
  event: AppPromiseRejectionEventLike,
): { details?: string | undefined; message: string; source: 'frontend.promise' } {
  const reason = event.reason;
  if (reason instanceof Error) {
    return {
      source: 'frontend.promise',
      message: reason.message || 'Unhandled promise rejection',
      details: reason.stack || undefined,
    };
  }
  return {
    source: 'frontend.promise',
    message: `Unhandled promise rejection: ${String(reason)}`,
  };
}

export function installAppRuntime(deps: AppRuntimeDeps): AppRuntime {
  let disposed = false;
  const onError: EventListener = (event) => {
    const report = buildWindowErrorReport(event as AppWindowErrorEventLike);
    if (!report) return;
    deps.reportClientError(report.source, report.message, undefined, report.details);
  };
  const onUnhandledRejection: EventListener = (event) => {
    // narrow via a structural runtime guard rather
    // than a `as unknown as` double-cast. The `'unhandledrejection'`
    // event runtime is `PromiseRejectionEvent` (which carries
    // `reason: unknown`), but `EventListener`'s parameter is the
    // base `Event` type. A direct cast tells TypeScript to stop
    // checking; the guard fails closed if a future reshape ever
    // strips the `reason` field, surfacing as a missed-error log
    // rather than a silent runtime error.
    if (typeof event !== 'object' || event === null || !('reason' in event)) return;
    const report = buildUnhandledRejectionReport(event as AppPromiseRejectionEventLike);
    deps.reportClientError(report.source, report.message, undefined, report.details);
  };

  deps.windowTarget.addEventListener('error', onError);
  deps.windowTarget.addEventListener('unhandledrejection', onUnhandledRejection);
  const teardownQuitFlush = deps.installQuitFlushListener();

  return {
    cleanup: () => {
      if (disposed) return;
      disposed = true;
      deps.windowTarget.removeEventListener('error', onError);
      deps.windowTarget.removeEventListener('unhandledrejection', onUnhandledRejection);
      teardownQuitFlush();
    },
  };
}
