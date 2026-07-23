import { useEffect, useRef } from 'react';
import { setDeviceState } from '@/lib/ipc/settings';
import { reportClientError } from '@/lib/errors/errorLogging';
import { DEV_UI_VIEW_STATE } from '@/lib/preferences/keys';
import type { View } from '@/lib/types';
import {
  createBrowserUiViewStatePersistenceTimerHost,
  installUiViewStatePersistenceRuntime,
} from './useUiViewStatePersistence.runtime';

/**
 * write the UI's presentation state into `device_state` so
 * the MCP `get_ui_view_state` tool can read it back. Purely local, never
 * synced (device_state is excluded from the sync outbox) and READ-ONLY
 * from the assistant's perspective.
 *
 * ### Batching
 *
 * Navigation + task-selection events can arrive in bursts (e.g. a user
 * arrow-keying through a list fires `setSelectedTaskId` on every step).
 * Flushing each transition through an IPC round-trip would create
 * needless contention on the shared SQLite writer. We debounce to 500 ms
 * — long enough to coalesce keystroke-speed churn, short enough that the
 * assistant always sees a snapshot that reflects the current view after
 * the user pauses.
 *
 * ### Schema
 *
 * The blob matches the shape surfaced by `get_ui_view_state`:
 *
 * ```ts
 * {
 *   last_updated_at: string,        // RFC3339, staleness anchor
 *   active_view: string,            // 'today' | 'upcoming' | 'list:<id>' | ...
 *   selected_task_id: string | null,
 *   search_query: string | null,
 *   list_filter_id: string | null,
 *   tag_filters: string[],
 *   priority_filter: number | null,
 *   focus_mode_active: boolean,
 *   focus_mode_task_id: string | null,
 * }
 * ```
 */
const UI_VIEW_STATE_KEY = DEV_UI_VIEW_STATE;
const DEBOUNCE_MS = 500;
const uiViewStatePersistenceTimerHost = createBrowserUiViewStatePersistenceTimerHost();

interface UiViewStateSnapshotInput {
  view: View;
  selectedTaskId: string | null;
  focusModeActive: boolean;
  focusModeTaskId: string | null;
}

interface UiViewStateSnapshot {
  last_updated_at: string;
  active_view: string;
  selected_task_id: string | null;
  search_query: string | null;
  list_filter_id: string | null;
  tag_filters: string[];
  priority_filter: number | null;
  focus_mode_active: boolean;
  focus_mode_task_id: string | null;
}

/**
 * Project a `View` variant into the string form the MCP tool surfaces.
 * Keep this table in sync with `lib/types.ts::View`.
 */
function deriveActiveView(view: View): string {
  switch (view.type) {
    case 'list':
      return `list:${view.listId}`;
    default:
      return view.type;
  }
}

function deriveListFilterId(view: View): string | null {
  return view.type === 'list' ? view.listId : null;
}

function deriveSearchQuery(view: View): string | null {
  // `all_tasks` is the only view whose discriminant carries a search
  // term the whole view is filtered by; per-view ad-hoc search inputs
  // (kanban, today) are local UI state and intentionally not surfaced.
  if (view.type === 'all_tasks' && typeof view.initialSearch === 'string') {
    const trimmed = view.initialSearch.trim();
    return trimmed.length > 0 ? trimmed : null;
  }
  return null;
}

export function buildUiViewStateSnapshot(
  input: UiViewStateSnapshotInput,
  now: Date = new Date(),
): UiViewStateSnapshot {
  return {
    last_updated_at: now.toISOString(),
    active_view: deriveActiveView(input.view),
    selected_task_id: input.selectedTaskId,
    search_query: deriveSearchQuery(input.view),
    list_filter_id: deriveListFilterId(input.view),
    // Tag / priority filters live inside individual view components
    // today (they're not hoisted into the nav controller). Emit the
    // stable empty/null form here; when those views gain shared state
    // plumbing we can populate them without changing the MCP contract.
    tag_filters: [],
    priority_filter: null,
    focus_mode_active: input.focusModeActive,
    focus_mode_task_id: input.focusModeActive ? input.focusModeTaskId : null,
  };
}

export function useUiViewStatePersistence(input: UiViewStateSnapshotInput): void {
  // Stash the latest input so the pending timer flushes the FRESH
  // snapshot on fire, not a stale closure-captured value.
  const latestRef = useRef(input);
  latestRef.current = input;

  useEffect(() => {
    return installUiViewStatePersistenceRuntime({
      delayMs: DEBOUNCE_MS,
      flush: () => {
        const snapshot = buildUiViewStateSnapshot(latestRef.current);
        void setDeviceState(UI_VIEW_STATE_KEY, snapshot).catch((error) => {
          reportClientError(
            'uiViewState.persist',
            'Failed to persist UI view state snapshot',
            error,
          );
        });
      },
      timerHost: uiViewStatePersistenceTimerHost,
    });
    // Re-derive the snapshot on any input change. Depending on primitive
    // fields directly keeps the effect cheap and avoids a reference
    // dependency on the `view` object identity.
  }, [
    input.view,
    input.selectedTaskId,
    input.focusModeActive,
    input.focusModeTaskId,
  ]);
}
