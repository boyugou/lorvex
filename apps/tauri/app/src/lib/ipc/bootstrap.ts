import { invoke } from './core';

import type { ListWithCount, Overview, CurrentFocusWithTasks } from './tasks/models';
import type { SetupStatus } from './settings';

/**
 * Coalesced first-paint payload for the main window.
 *
 * Before this existed, the main window shell fired 15+ sequential
 * `invoke()` calls on mount — one per panel — producing a visible
 * two-wave IPC waterfall on slower machines. `get_today_bootstrap`
 * collapses every read the first frame depends on into a single
 * round-trip, pinned inside a `BEGIN DEFERRED` snapshot so each
 * field observes the same point-in-time database state.
 *
 * The individual IPC commands (`get_overview`, `get_all_lists`,
 * `get_preference`, `get_setup_status`, `get_current_focus`) are
 * unchanged — the bootstrap is additive. Any view that mounts
 * outside the main-window path or triggers a targeted refetch keeps
 * hitting the original endpoints.
 */
export interface TodayBootstrap {
  overview: Overview;
  lists: ListWithCount[];
  /**
   * Preference snapshot. Keys are the literal preference names (e.g.
   * `timezone`, `sidebar_visible_modules`); values are the stored
   * JSON-encoded strings (same shape `getPreference` returns).
   * Missing preferences are absent from the object. Callers decode
   * the JSON client-side through `parsePreferenceJson`, identical to
   * the single-key path.
   */
  preferences: Record<string, string>;
  /**
   * Fully-resolved IANA timezone name. Pre-computed server-side so
   * `DayContextProvider` can hydrate synchronously without waiting
   * on its own timezone-preference query.
   */
  timezone: string;
  /**
   * Today's YYYY-MM-DD in the resolved timezone. Pre-computed so
   * surfaces that key on `todayYmd` don't re-derive it client-side
   * on mount.
   */
  today_ymd: string;
  setup_status: SetupStatus;
  current_focus: CurrentFocusWithTasks | null;
}

export const getTodayBootstrap = (signal?: AbortSignal): Promise<TodayBootstrap> =>
  invoke('get_today_bootstrap', undefined, signal);
