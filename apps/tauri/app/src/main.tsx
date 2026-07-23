import React from 'react';
import ReactDOM from 'react-dom/client';
import { MutationCache, QueryCache, QueryClient, QueryClientProvider } from '@tanstack/react-query';
import App from './App';
import { DayContextProvider } from './lib/DayContextProvider';
import { I18nProvider } from './lib/i18n';
import { ThemeProvider } from './lib/theme';
import { getDesktopPlatform, getMobilePlatform } from './lib/platform/platform';
import { handleDiskFullIpcError } from './lib/recovery/diskFull';
import { reportClientError } from './lib/errors/errorLogging';
import { installMainDocumentRuntime } from './main.runtime';
import { installTrustedTypesPolicy } from './lib/security/trustedTypes';
import './index.css';

// install the Trusted Types default policy before any
// React render, so even a third-party module loaded synchronously by
// `import './index.css'` or downstream chunks cannot reach a raw
// `innerHTML` sink. The call is a no-op on macOS WKWebView (which
// ignores the API) and harmless on every other webview.
installTrustedTypesPolicy();

// mirror `document.visibilityState` onto a root data
// attribute so CSS can pause decorative animations when the window is
// hidden. Every `animate-pulse` / `animate-spin` keeps the compositor
// awake at ~60fps even for backgrounded windows — burning GPU for
// pixels nobody sees. The CSS rule in index.css scopes to decorative
// surfaces (opts out of loading spinners authored with `animate-spin`
// that signal intent to the user). Runs for every window kind
// including overlays (focus panel), which pause while
// minimized too.
// Audit leak-guard against duplicate install. Vite HMR and
// devtools ⌘R can re-execute this module, stacking extra listeners.
// A one-time `window` flag makes the install idempotent.
installMainDocumentRuntime({
  desktopPlatform: getDesktopPlatform(),
  documentTarget: document,
  mobilePlatform: getMobilePlatform(),
  windowTarget: window,
});

const queryClient = new QueryClient({
  // Global failure observability: a silent refetch error today only raises
  // a toast in the component that owns the query; once the toast fades the
  // failure is untraceable. Route every query-cache error through
  // reportClientError so Settings -> Diagnostics retains a record.
  queryCache: new QueryCache({
    onError: (error, query) => {
      // surface the "Storage is full" actionable toast up front
      // so the user sees an actionable banner instead of the query's
      // generic error state. Returns true when handled — we still
      // report the error for diagnostics so maintainers have the raw
      // backend detail in error_logs.
      handleDiskFullIpcError(error);
      const keyHead = typeof query.queryKey[0] === 'string' ? query.queryKey[0] : 'query';
      reportClientError(`frontend.query.${keyHead}`, 'TanStack Query error', error);
    },
  }),
  mutationCache: new MutationCache({
    onError: (error) => {
      // Mirrors the query path: mutations are the primary write
      // surface where DiskFull first fires; we want the toast on the
      // write attempt, not just the next refetch.
      handleDiskFullIpcError(error);
    },
  }),
  defaultOptions: {
    queries: {
      // No global polling — refetch on window focus + after mutations.
      // Individual views opt-in to polling where needed (e.g., reminders).
      // Global 2s polling caused race conditions with mutations and
      // unnecessary load (5+ requests/second with many views open).
      //
      // `staleTime` tuned to match STALE_DEFAULT in lib/query/timing.ts
      // (30s). The previous 5s default forced a refetch on every
      // window-focus cycle for queries that didn't opt into a longer
      // window, which visibly stalled the overlay<->main-window
      // switch for users with 1000+ tasks. Per-query overrides via
      // `useQuery({ staleTime: STALE_SHORT })` still take precedence
      // for views that actually want faster freshness.
      staleTime: 30_000,
      // TanStack's default `gcTime` is 5 minutes, so a
      // cache entry for AllTasksView / CalendarView / WeeklyReview
      // stays resident for 5 min after the last consumer unmounts.
      // With 50+ query keys and large task sets the cache climbs into
      // several MBs for users with long sessions, especially on 8 GB
      // machines where the WebView can get swapped out by the OS.
      // Shrink the default to 60s — enough that a quick
      // tab-out/tab-back doesn't refetch, but navigating away from a
      // view releases memory promptly. Queries that legitimately want
      // longer retention (preferences, device-state) opt in per-hook
      // via `{ gcTime: STALE_LONG }`.
      gcTime: 60_000,
      refetchOnWindowFocus: true,
      // TanStack's default `retry: 3` with exponential
      // backoff (1s, 2s, 4s) is tuned for flaky network requests, not
      // Tauri IPC. Our IPC commands return typed errors deterministically
      // — retrying a Validation / NotFound / Internal error three times
      // just wastes 7s, produces 3 extra error_logs entries per failure,
      // and stalls the UI before it can show an empty state. The only
      // genuinely transient class is SQLITE_BUSY under concurrent
      // writer contention, and that's handled inline by the store
      // layer's busy_timeout plus future-scoped retry logic —
      // it doesn't reach the TanStack layer.
      //
      // Explicit `false` (not 0) so per-query opt-in still works:
      // `useQuery({ retry: 2 })` on a specific flaky surface stays
      // legal. Permanent-failure views show their empty state
      // immediately, and the one error_logs entry that surfaces is
      // the authoritative record.
      retry: false,
    },
    mutations: {
      // Same reasoning for mutations — an MCP call that returned
      // Validation won't succeed on retry, but TanStack's default is
      // already 0 for mutations. Pin explicitly so accidental
      // per-mutation overrides don't drift into the query default.
      retry: false,
    },
  },
});

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <QueryClientProvider client={queryClient}>
      <DayContextProvider>
        <ThemeProvider>
          <I18nProvider>
            <App />
          </I18nProvider>
        </ThemeProvider>
      </DayContextProvider>
    </QueryClientProvider>
  </React.StrictMode>,
);
