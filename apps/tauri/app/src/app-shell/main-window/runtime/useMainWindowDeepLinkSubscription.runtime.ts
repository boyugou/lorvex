import type { DeepLinkTarget } from '@/lib/ipc/runtime';
import { isPlainRecord } from '@/lib/objectGuards';
import { createAsyncTauriListenerScope } from '@/lib/tauriListenerLifecycle';

type DeepLinkUnlisten = () => void;

interface MainWindowDeepLinkSubscriptionRuntimeDeps {
  applyDeepLinkTarget: (target: DeepLinkTarget | null) => void;
  listenDeepLinkOpen: (handler: (payload: unknown) => void) => Promise<DeepLinkUnlisten>;
  consumePendingDeepLink: () => Promise<unknown>;
  acknowledgePendingDeepLink: (payload: DeepLinkTarget) => Promise<unknown>;
  reportError: (scope: string, message: string, error: unknown, details?: string) => void;
  maxPendingDrain?: number;
}

const DEEP_LINK_ROUTES = [
  'today',
  'task',
  'quick_capture',
  'search',
  'add_task',
  'complete_task',
] as const;

function isStringRecord(value: unknown): value is Record<string, string> {
  if (!isPlainRecord(value)) return false;
  return Object.values(value).every((entry) => typeof entry === 'string');
}

function isDeepLinkTarget(payload: unknown): payload is DeepLinkTarget {
  if (!isPlainRecord(payload)) {
    return false;
  }
  const candidate = payload;
  if (typeof candidate.route !== 'string') return false;
  if (!(DEEP_LINK_ROUTES as readonly string[]).includes(candidate.route)) return false;
  if (typeof candidate.task_id !== 'string' && candidate.task_id !== null) return false;
  if (candidate.params !== undefined && !isStringRecord(candidate.params)) return false;
  return true;
}

function describeInvalidDeepLinkPayload(payload: unknown): string {
  if (payload === null) return 'null';
  if (Array.isArray(payload)) return 'array';
  return typeof payload;
}

export function startMainWindowDeepLinkSubscriptionRuntime(
  deps: MainWindowDeepLinkSubscriptionRuntimeDeps,
): DeepLinkUnlisten {
  const {
    acknowledgePendingDeepLink,
    applyDeepLinkTarget,
    consumePendingDeepLink,
    listenDeepLinkOpen,
    maxPendingDrain = 20,
    reportError,
  } = deps;

  let cancelled = false;
  const listeners = createAsyncTauriListenerScope();

  const reportInvalidPayload = (payload: unknown) => {
    reportError(
      'app.deepLink.invalidPayload',
      'Ignored malformed deep-link payload',
      new Error('Invalid deep-link payload'),
      describeInvalidDeepLinkPayload(payload),
    );
  };

  const applyOpenPayload = (payload: unknown) => {
    if (cancelled) return;
    if (payload === null || payload === undefined) {
      applyDeepLinkTarget(null);
      return;
    }
    if (!isDeepLinkTarget(payload)) {
      reportInvalidPayload(payload);
      return;
    }
    const target = payload;
    applyDeepLinkTarget(target);

    const details = `${target.route}:${target.task_id ?? ''}`;
    void acknowledgePendingDeepLink(target).catch((error) => {
      reportError('app.deepLink.ack', 'Failed to acknowledge deep link', error, details);
    });
  };

  const drainPendingDeepLinks = async () => {
    let count = 0;
    while (!cancelled && count < maxPendingDrain) {
      let pending: unknown;
      try {
        pending = await consumePendingDeepLink();
      } catch (error) {
        reportError('app.deepLink.pendingDrain', 'Failed to consume pending deep link', error);
        return;
      }
      if (cancelled || !pending) return;
      if (!isDeepLinkTarget(pending)) {
        reportInvalidPayload(pending);
        count += 1;
        continue;
      }
      applyDeepLinkTarget(pending);
      count += 1;
    }
  };

  const setupDeepLinkListener = async () => {
    const listenerPromise = listenDeepLinkOpen(applyOpenPayload);
    // listeners.add wires the registration-failure path: if the
    // promise rejects, `reportError` runs there. We wait for the
    // listener to land before draining queued links so a deep-link
    // arriving during that window can be picked up by the listener
    // instead of getting consumed twice. The bare `catch` below is
    // NOT a silent swallow — the rejection has already been
    // routed to `reportError` via listeners.add by the time it
    // reaches here, and re-reporting would duplicate the entry.
    listeners.add(listenerPromise, (error) => {
      reportError('app.deepLink.listen', 'Failed to subscribe to deep-link events', error);
    });
    try {
      await listenerPromise;
    } catch {
      // already reported via listeners.add above
    }
    if (!cancelled) {
      await drainPendingDeepLinks();
    }
  };

  void setupDeepLinkListener();

  return () => {
    cancelled = true;
    listeners.dispose();
  };
}
