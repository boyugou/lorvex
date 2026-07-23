import { getVersion } from '@tauri-apps/api/app';
import { checkForUpdate as checkForUpdateIpc } from '@/lib/ipc/runtime';
import { HOUR_MS } from '@/lib/time/durations';
import {
  checkForUpdateCachedRuntime,
  createBrowserCheckForUpdateCachedRuntimeDeps,
} from './checkForUpdateCached.runtime';

/**
 * Cached + de-duped wrapper around the update-check IPC.
 *
 * the raw IPC was invoked from every sidebar mount
 * with no offline guard, no dedup, no TTL, and no jitter. A
 * window-restore flow that toggled the sidebar could fire N fetches
 * per session; offline users paid the full connect timeout on the
 * Tauri command thread; and every heavy-multi-window user hit the
 * GitHub releases CDN in lockstep at app launch.
 *
 * Contract:
 * - Returns `null` (same as the IPC's "no update" sentinel) if the
 *   browser reports offline. The caller's existing error handling
 *   already treats null as "no banner"; no new branch needed.
 * - Caches the latest successful result for 6 hours, keyed by the
 *   current app version so a build swap invalidates the cache.
 * - A single module-level `Promise` coalesces concurrent callers
 *   (sidebar mount + "Check for Updates" menu item) into one
 *   network hit.
 */

const STORAGE_KEY = 'lorvex.update_check_cache.v1';
const TTL_MS = 6 * HOUR_MS;

let inflight: Promise<string | null> | null = null;

/**
 * Return the available update version (or `null` when up-to-date
 * or offline). Uses an in-process dedup promise plus a 6-hour
 * browser-cache TTL so repeated mounts don't hammer the updater endpoint.
 */
export async function checkForUpdateCached(): Promise<string | null> {
  return checkForUpdateCachedRuntime(createBrowserCheckForUpdateCachedRuntimeDeps({
    appVersionFallback: 'unknown',
    cacheKey: STORAGE_KEY,
    now: () => Date.now(),
    ttlMs: TTL_MS,
    getVersion,
    checkForUpdate: checkForUpdateIpc,
    setInflight: (nextInflight) => {
      inflight = nextInflight;
    },
    getInflight: () => inflight,
  }));
}
