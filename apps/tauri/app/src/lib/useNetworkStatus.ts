import { useEffect, useState } from 'react';

import {
  createBrowserNetworkStatusRuntimeDeps,
  installNetworkStatusRuntime,
  readBrowserNetworkOnlineStatus,
  reduceNetworkStatus,
} from './useNetworkStatus.runtime';

// the sync loop can silently back off when connectivity
// drops, leaving the UI with no hint that "your last sync is 20 min old
// because Wi-Fi dropped, not because sync is broken." This hook surfaces
// that online/offline signal so the sidebar and Sync Now button can render
// an explicit "Offline" state instead.
//
// Scope: this is a pure UI signal. It does NOT reconfigure the sync
// scheduler — the offline-aware retry pattern lives in the backend
//. When connectivity returns, individual surfaces may
// choose to trigger an immediate sync; this hook just reports state.
//
// IOS-L (reachability surface): in addition to the React
// signal each `useNetworkStatus` consumer reads, the first install on
// the page mirrors the boolean onto a `data-online` attribute on
// `<html>` so global CSS rules (e.g. dim the navigation bar when
// offline, hide the touch pull-to-refresh affordance until reachable)
// can react without each surface re-subscribing. This mirrors the
// pattern already used for `data-mobile-os` / `data-visibility`.

// ---------------------------------------------------------------------------
// React hook
// ---------------------------------------------------------------------------

interface NetworkStatus {
  readonly online: boolean;
}

function mirrorOnlineAttr(online: boolean): void {
  try {
    const root = globalThis.document?.documentElement;
    if (!root) return;
    root.setAttribute('data-online', online ? 'true' : 'false');
  } catch {
    // Headless / SSR / strict-mode no-op — the React state is the
    // canonical signal, the data attribute is a CSS convenience.
  }
}

export function useNetworkStatus(): NetworkStatus {
  const [online, setOnline] = useState<boolean>(readBrowserNetworkOnlineStatus);

  useEffect(() => {
    mirrorOnlineAttr(online);
    return installNetworkStatusRuntime(
      createBrowserNetworkStatusRuntimeDeps((event) => {
        setOnline((current) => {
          const next = reduceNetworkStatus({ online: current }, event).online;
          if (next !== current) mirrorOnlineAttr(next);
          return next;
        });
      }),
    );
    // The effect runs once on mount; re-running on `online` change would
    // tear down/reinstall the listeners on every flip. We intentionally
    // mirror inside the dispatch path instead.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  return { online };
}
