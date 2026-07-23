import type { CalendarEvent, CalendarEventType } from '@lorvex/shared/types';
import { invoke, invokeIpc } from './core';
import { buildPayload } from './buildPayload';

export type { CalendarEvent, CalendarEventType } from '@lorvex/shared/types';

export const createCalendarEvent = (params: {
  title: string;
  start_date: string;
  start_time?: string | null;
  end_date?: string | null;
  end_time?: string | null;
  all_day?: boolean;
  recurrence?: string | null;
  description?: string | null;
  location?: string | null;
  timezone?: string | null;
  color?: string | null;
  event_type?: CalendarEventType | null;
  person_name?: string | null;
  url?: string | null;
}, signal?: AbortSignal): Promise<CalendarEvent> => {
  if (!params.start_date) {
    return Promise.reject(new Error('start_date is required'));
  }
  // `buildPayload` strips `undefined` keys but preserves `null`; backend
  // Tauri commands deserialize both `null` and missing keys to `None`, so
  // passing `params` straight through is equivalent to the previous
  // per-field re-read. `all_day` defaults to `false` when the caller
  // omits it.
  const payload = buildPayload({ all_day: false }, params);
  return invokeIpc<CalendarEvent>('create_calendar_event', payload, signal);
};

/**
 * Replace-set attendee patch for `updateCalendarEvent`. Mirrors the
 * Tauri wire shape: omit the key to leave existing attendees alone,
 * send `null` to clear every attendee row, send `[...]` to replace
 * the attendee rows with the supplied list (an empty array also
 * clears).
 */
export interface CalendarEventAttendeeInput {
  email: string;
  name?: string | null;
  status?: string | null;
}

export const updateCalendarEvent = (
  id: string,
  updates: {
    title?: string;
    recurrence?: string | null;
    start_date?: string;
    start_time?: string | null;
    end_date?: string | null;
    end_time?: string | null;
    all_day?: boolean;
    description?: string | null;
    location?: string | null;
    timezone?: string | null;
    color?: string | null;
    event_type?: CalendarEventType;
    person_name?: string | null;
    url?: string | null;
    attendees?: CalendarEventAttendeeInput[] | null;
  },
  signal?: AbortSignal,
): Promise<CalendarEvent> => {
  // Nullable protocol: send `null` directly for fields to clear.
  // The backend uses deserialize_nullable (same as MCP) to distinguish
  // absent fields (don't touch) from null (clear to null).
  // buildPayload strips `undefined` but preserves `null`.
  const payload = buildPayload({ id }, updates);
  return invokeIpc<CalendarEvent>('update_calendar_event', { payload }, signal);
};

/** Result of `delete_calendar_event`. Carries the list of tasks
 *  whose calendar links were severed by the cascade plus a short-lived
 *  opaque undo token the UI can present in a toast. */
export interface DeleteCalendarEventResult {
  unlinked_task_ids: string[];
  undo_token: string;
}

export const deleteCalendarEvent = (
  id: string,
  signal?: AbortSignal,
): Promise<DeleteCalendarEventResult> =>
  invokeIpc<DeleteCalendarEventResult>('delete_calendar_event', { id }, signal);

export type RecurringCalendarEventScope = 'allInSeries' | 'thisOnly' | 'thisAndFollowing';

export interface ScopedCalendarEventEditResult {
  original_event: CalendarEvent | null;
  replacement_event: CalendarEvent | null;
  delete_result: DeleteCalendarEventResult | null;
  noop: boolean;
}

export interface ScopedCalendarEventDeleteResult {
  event: CalendarEvent | null;
  delete_result: DeleteCalendarEventResult | null;
  noop: boolean;
}

export const applyScopedCalendarEventEdit = (
  params: {
    id: string;
    occurrence_date: string;
    scope: RecurringCalendarEventScope;
    payload: Parameters<typeof createCalendarEvent>[0];
  },
  signal?: AbortSignal,
): Promise<ScopedCalendarEventEditResult> =>
  invokeIpc<ScopedCalendarEventEditResult>('apply_scoped_calendar_event_edit', { input: params }, signal);

export const deleteScopedCalendarEvent = (
  params: {
    id: string;
    occurrence_date: string;
    scope: RecurringCalendarEventScope;
  },
  signal?: AbortSignal,
): Promise<ScopedCalendarEventDeleteResult> =>
  invokeIpc<ScopedCalendarEventDeleteResult>('delete_scoped_calendar_event', { input: params }, signal);

export const getCalendarEvent = (id: string, signal?: AbortSignal): Promise<CalendarEvent> =>
  invoke<CalendarEvent>('get_calendar_event', { id }, signal);

export const getEventsByDateRange = (from: string, to: string, signal?: AbortSignal): Promise<UnifiedCalendarEvent[]> =>
  invoke('get_events_by_date_range', { from, to }, signal);

/** Canonical `CalendarEvent` fields plus `kind` and `editable` from the unified query. */
export interface UnifiedCalendarEvent extends Omit<CalendarEvent, 'event_type'> {
  /** `"canonical"` for app-owned events, `"provider"` for external provider events. */
  kind: 'canonical' | 'provider';
  /** Whether the event can be edited/deleted in the UI. */
  editable: boolean;
  /** Canonical events use the shared enum; provider events can preserve upstream categories. */
  event_type: string;
  /**
   * Provider-event attendees serialized as a JSON string, sourced
   * directly from the upstream iCal feed (`provider_calendar_events.
   * attendees_json`). Coexists with the canonical `attendees` field
   * on `CalendarEvent` because the two flows source from different
   * tables: canonical app-owned events materialize attendees into
   * the `calendar_event_attendees` sub-table (and surface them
   * structured via `attendees`), whereas provider events are
   * passthrough — the assistant and UI parse the raw upstream JSON
   * verbatim here so an iCal extension key the schema doesn't model
   * survives the round trip. `null` for canonical events; for those
   * use the `attendees` field instead.
   */
  attendees_json: string | null;
}

/** Query both canonical and provider calendar events for a date range. */
export const getCalendarEventsUnified = (from: string, to: string, signal?: AbortSignal): Promise<UnifiedCalendarEvent[]> =>
  invoke('get_calendar_events_unified', { from, to }, signal);

// Task ↔ Calendar Event Links
export interface TaskCalendarEventLink {
  task_id: string;
  calendar_event_id: string;
  created_at: string;
  updated_at: string;
}

export const linkTaskToEvent = (taskId: string, eventId: string, signal?: AbortSignal): Promise<TaskCalendarEventLink> =>
  invokeIpc<TaskCalendarEventLink>('link_task_to_event', { task_id: taskId, event_id: eventId }, signal);

export const unlinkTaskFromEvent = (taskId: string, eventId: string, signal?: AbortSignal): Promise<TaskCalendarEventLink[]> =>
  invokeIpc<TaskCalendarEventLink[]>('unlink_task_from_event', { task_id: taskId, event_id: eventId }, signal);

export const getLinkedEventsForTask = (taskId: string, signal?: AbortSignal): Promise<TaskCalendarEventLink[]> =>
  invoke('get_linked_events_for_task', { task_id: taskId }, signal);

// Task ↔ Provider Calendar Event Links (local-only, no sync)
export interface TaskProviderEventLink {
  task_id: string;
  provider_kind: string;
  provider_scope: string;
  provider_event_key: string;
  created_at: string;
  updated_at: string;
}

export interface ProviderEventLinkWithResolution {
  task_id: string;
  provider_kind: string;
  provider_scope: string;
  provider_event_key: string;
  created_at: string;
  updated_at: string;
  event_title: string | null;
  event_start_date: string | null;
  event_start_time: string | null;
  resolution_state: 'resolved' | 'pending' | 'stale' | 'unavailable' | 'missing';
}

export const linkTaskToProviderEvent = (
  taskId: string,
  providerKind: string,
  providerScope: string,
  providerEventKey: string,
  signal?: AbortSignal,
): Promise<TaskProviderEventLink> =>
  invokeIpc<TaskProviderEventLink>('link_task_to_provider_event', {
    task_id: taskId,
    provider_kind: providerKind,
    provider_scope: providerScope,
    provider_event_key: providerEventKey,
  }, signal);

export const unlinkTaskFromProviderEvent = (
  taskId: string,
  providerKind: string,
  providerScope: string,
  providerEventKey: string,
  signal?: AbortSignal,
): Promise<TaskProviderEventLink[]> =>
  invokeIpc<TaskProviderEventLink[]>('unlink_task_from_provider_event', {
    task_id: taskId,
    provider_kind: providerKind,
    provider_scope: providerScope,
    provider_event_key: providerEventKey,
  }, signal);

export const getProviderEventLinksForTask = (
  taskId: string,
  signal?: AbortSignal,
): Promise<ProviderEventLinkWithResolution[]> =>
  invoke('get_provider_event_links_for_task', { task_id: taskId }, signal);

export const addEventException = (eventId: string, date: string, signal?: AbortSignal): Promise<CalendarEvent> =>
  invokeIpc<CalendarEvent>('add_event_exception', { event_id: eventId, date }, signal);

export const exportCalendarIcs = (from: string, to: string, signal?: AbortSignal): Promise<string> =>
  invoke('export_calendar_ics', { from, to }, signal);

// ── Calendar Subscriptions (.ics feeds) ──────────────────────────────

type CalendarSubscriptionSyncHealth = 'disabled' | 'pending' | 'healthy' | 'stale' | 'failing';

export interface CalendarSubscription {
  id: string;
  name: string;
  url: string;
  color: string | null;
  enabled: boolean;
  last_fetched_at: string | null;
  error_message: string | null;
  created_at: string;
  updated_at: string;
  /**
   * per-subscription exponential-backoff surface.
   * `next_retry_at` — earliest RFC3339 UTC timestamp at which the
   * background scheduler will retry this feed (null when no cooldown).
   * `consecutive_failures` — number of consecutive failed refreshes;
   * the UI shows "Retry now" when this is > 0.
   * `last_retry_after_hint` — the most recent HTTP Retry-After value
   * (in seconds, as a text string) surfaced by the feed, if any.
   */
  next_retry_at: string | null;
  consecutive_failures: number;
  last_retry_after_hint: string | null;
  sync_health: CalendarSubscriptionSyncHealth;
}

export interface SubscriptionSyncResult {
  subscription_id: string;
  subscription_name: string;
  events_imported: number;
  events_updated: number;
  events_removed: number;
  error: string | null;
}

export interface RemoveCalendarSubscriptionResult {
  deleted: string;
}

export interface ToggleCalendarSubscriptionResult {
  id: string;
  enabled: boolean;
}

export interface UpdateCalendarSubscriptionColorResult {
  id: string;
  color: string | null;
}

export const listCalendarSubscriptions = (signal?: AbortSignal): Promise<CalendarSubscription[]> =>
  invoke('list_calendar_subscriptions', undefined, signal);

export const addCalendarSubscription = (name: string, url: string, color?: string, signal?: AbortSignal): Promise<CalendarSubscription> =>
  invokeIpc('add_calendar_subscription', { name, url, color }, signal);

export const removeCalendarSubscription = (id: string, signal?: AbortSignal): Promise<RemoveCalendarSubscriptionResult> =>
  invokeIpc('remove_calendar_subscription', { id }, signal);

export const toggleCalendarSubscription = (id: string, enabled: boolean, signal?: AbortSignal): Promise<ToggleCalendarSubscriptionResult> =>
  invokeIpc('toggle_calendar_subscription', { id, enabled }, signal);

export const updateCalendarSubscriptionColor = (id: string, color: string | null, signal?: AbortSignal): Promise<UpdateCalendarSubscriptionColorResult> =>
  invokeIpc('update_calendar_subscription_color', { id, color }, signal);

export const syncCalendarSubscription = (id: string, signal?: AbortSignal): Promise<SubscriptionSyncResult> =>
  invokeIpc('sync_calendar_subscription', { id }, signal);

/**
 * user-facing "Retry now" action — clears the per-feed
 * backoff gate and runs a fresh sync immediately. Use from the
 * Settings panel when the user explicitly asks to probe a feed; the
 * background scheduler continues to respect `next_retry_at` on its
 * own cadence.
 */
export const retryCalendarSubscriptionNow = (id: string, signal?: AbortSignal): Promise<SubscriptionSyncResult> =>
  invokeIpc('retry_calendar_subscription_now', { id }, signal);

export const syncAllCalendarSubscriptions = (signal?: AbortSignal): Promise<SubscriptionSyncResult[]> =>
  invokeIpc('sync_all_calendar_subscriptions', undefined, signal);

// ── Linux ICS (local .ics file scanning) ──────────────────────────

export interface LinuxCalendarSyncResult {
  events_imported: number;
  events_updated: number;
  events_removed: number;
  files_scanned: number;
  available: boolean;
  error: string | null;
}

export const syncLinuxCalendars = (signal?: AbortSignal): Promise<LinuxCalendarSyncResult> =>
  invokeIpc('sync_linux_calendars', undefined, signal);

// ── Windows Appointments (native Windows calendar) ────────────────

export interface WindowsCalendarSyncResult {
  events_imported: number;
  events_updated: number;
  events_removed: number;
  calendars_scanned: number;
  available: boolean;
  error: string | null;
}

export const syncWindowsCalendars = (signal?: AbortSignal): Promise<WindowsCalendarSyncResult> =>
  invokeIpc('sync_windows_calendars', undefined, signal);

export type NativeCalendarProviderSource = 'linux_ics' | 'windows_appointments';

export interface ClearNativeCalendarEventsResult {
  deleted: number;
}

export const clearNativeCalendarEvents = (
  source: NativeCalendarProviderSource,
  signal?: AbortSignal,
): Promise<ClearNativeCalendarEventsResult> =>
  invokeIpc('clear_native_calendar_events', { source }, signal);
