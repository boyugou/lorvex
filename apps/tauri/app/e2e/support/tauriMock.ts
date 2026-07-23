import type { Page } from '@playwright/test';

export const E2E_FIXTURE_NOW = '2026-04-29T20:00:00.000Z';
const E2E_FIXTURE_TODAY_YMD = '2026-04-29';

const DEFAULT_OVERVIEW = {
  stats: {
    open_count: 3,
    overdue_count: 1,
    today_pool_count: 2,
    upcoming_week_count: 4,
    completed_today: 1,
    completed_this_week: 5,
    completed_last_week: 7,
    someday_count: 1,
    completion_streak: 3,
    streak_active_today: true,
  },
  lists: [
    {
      id: 'list-inbox',
      name: 'Inbox',
      color: null,
      icon: null,
      description: null,
      archived_at: null,
      created_at: E2E_FIXTURE_NOW,
      updated_at: E2E_FIXTURE_NOW,
      open_count: 2,
    },
  ],
  current_focus: null,
  top_by_priority: [],
  recently_completed: [],
};

const DEFAULT_LISTS = DEFAULT_OVERVIEW.lists;
const DEFAULT_TAGS = [
  { display_name: 'planning', color: '#3b82f6' },
  { display_name: 'personal', color: '#10b981' },
  { display_name: 'today', color: '#f59e0b' },
];
const DEFAULT_TASKS = [
  {
    id: 'task-visual-1',
    title: 'Review multilingual launch checklist and calendar labels',
    body: 'Dense task row for visual i18n coverage.',
    raw_input: null,
    ai_notes: null,
    status: 'open',
    list_id: 'list-inbox',
    tags: ['planning', 'today'],
    checklist_items: null,
    priority: 1,
    due_date: E2E_FIXTURE_TODAY_YMD,
    due_time: '09:30',
    estimated_minutes: 45,
    recurrence: null,
    recurrence_exceptions: null,
    depends_on: null,
    spawned_from: null,
    recurrence_group_id: null,
    canonical_occurrence_date: null,
    recurrence_instance_key: null,
    version: '2026-04-29T20:00:00.000Z-visual-1',
    created_at: E2E_FIXTURE_NOW,
    updated_at: E2E_FIXTURE_NOW,
    completed_at: null,
    last_deferred_at: null,
    last_defer_reason: null,
    lateness_state: null,
    planned_date: E2E_FIXTURE_TODAY_YMD,
    defer_count: 0,
    archived_at: null,
  },
  {
    id: 'task-visual-2',
    title: 'Prepare settings copy audit with a deliberately long title',
    body: null,
    raw_input: null,
    ai_notes: 'Keep labels compact in translated settings panels.',
    status: 'open',
    list_id: 'list-inbox',
    tags: ['planning'],
    checklist_items: null,
    priority: 2,
    due_date: null,
    due_time: null,
    estimated_minutes: 30,
    recurrence: null,
    recurrence_exceptions: null,
    depends_on: null,
    spawned_from: null,
    recurrence_group_id: null,
    canonical_occurrence_date: null,
    recurrence_instance_key: null,
    version: '2026-04-29T20:00:00.000Z-visual-2',
    created_at: E2E_FIXTURE_NOW,
    updated_at: E2E_FIXTURE_NOW,
    completed_at: null,
    last_deferred_at: null,
    last_defer_reason: null,
    lateness_state: null,
    planned_date: null,
    defer_count: 1,
    archived_at: null,
  },
  {
    id: 'task-visual-3',
    title: 'Archive stale localized screenshot notes',
    body: null,
    raw_input: null,
    ai_notes: null,
    status: 'completed',
    list_id: 'list-inbox',
    tags: ['personal'],
    checklist_items: null,
    priority: 3,
    due_date: '2026-04-28',
    due_time: null,
    estimated_minutes: 15,
    recurrence: null,
    recurrence_exceptions: null,
    depends_on: null,
    spawned_from: null,
    recurrence_group_id: null,
    canonical_occurrence_date: null,
    recurrence_instance_key: null,
    version: '2026-04-29T20:00:00.000Z-visual-3',
    created_at: E2E_FIXTURE_NOW,
    updated_at: E2E_FIXTURE_NOW,
    completed_at: E2E_FIXTURE_NOW,
    last_deferred_at: null,
    last_defer_reason: null,
    lateness_state: null,
    planned_date: null,
    defer_count: 0,
    archived_at: null,
  },
];

type TauriMockOverview = typeof DEFAULT_OVERVIEW;
type TauriMockList = typeof DEFAULT_LISTS[number];
type TauriMockTag = typeof DEFAULT_TAGS[number];
type TauriMockTask = typeof DEFAULT_TASKS[number];

interface TauriMockCurrentFocus {
  date: string;
  task_ids: string[];
  briefing: string | null;
  timezone: string | null;
  tasks: Array<Record<string, unknown>>;
}

interface TauriMockFixtures {
  overview?: TauriMockOverview;
  lists?: TauriMockList[];
  tags?: TauriMockTag[];
  tasks?: TauriMockTask[];
  currentFocus?: TauriMockCurrentFocus | null;
}

export async function installTauriMock(
  page: Page,
  localeCode = 'en',
  fixtures: TauriMockFixtures = {},
): Promise<void> {
  const lists = fixtures.lists ?? DEFAULT_LISTS;
  const overview = fixtures.overview ?? {
    ...DEFAULT_OVERVIEW,
    lists,
  };
  const tags = fixtures.tags ?? DEFAULT_TAGS;
  const tasks = fixtures.tasks ?? DEFAULT_TASKS;
  const currentFocus = fixtures.currentFocus ?? null;

  await page.addInitScript(
    ({ locale, overview, lists, tags, tasks, currentFocus, fixtureNow, fixtureTodayYmd }) => {
      const windowRecord = window as typeof window & {
        __TAURI_INTERNALS__?: {
          invoke: (cmd: string, payload?: Record<string, unknown>) => Promise<unknown>;
          transformCallback: (callback?: (payload: unknown) => unknown) => number;
          metadata?: {
            currentWindow?: { label?: string };
            currentWebview?: { windowLabel?: string; label?: string };
          };
        };
        __TAURI_EVENT_PLUGIN_INTERNALS__?: {
          unregisterListener: (event: string, eventId: number) => void;
        };
        __LORVEX_E2E__?: {
          emitTauriEvent: (event: string, payload?: unknown) => void;
          quickCaptureCalls: Array<Record<string, unknown> | undefined>;
          tauriEventListenerCount: (event: string) => number;
        };
      };

      const callbackRegistry = new Map<number, ((payload: unknown) => unknown) | undefined>();
      const tauriEventListeners = new Map<string, number[]>();
      let callbackIdSeq = 1;

      const emitTauriEvent = (event: string, payload?: unknown) => {
        const handlers = tauriEventListeners.get(event) ?? [];
        handlers.forEach((handlerId) => {
          callbackRegistry.get(handlerId)?.({
            event,
            id: handlerId,
            payload: payload ?? null,
          });
        });
      };

      windowRecord.__LORVEX_E2E__ = {
        emitTauriEvent,
        quickCaptureCalls: [],
        tauriEventListenerCount: (event) => tauriEventListeners.get(event)?.length ?? 0,
      };
      windowRecord.__TAURI_EVENT_PLUGIN_INTERNALS__ = {
        unregisterListener: (event, eventId) => {
          const handlers = tauriEventListeners.get(event);
          if (!handlers) return;
          tauriEventListeners.set(event, handlers.filter((id) => id !== eventId));
        },
      };
      windowRecord.__TAURI_INTERNALS__ = {
        metadata: {
          currentWindow: { label: 'main' },
          currentWebview: { windowLabel: 'main', label: 'main' },
        },
      };
      const setupStatus = {
        list_count: lists.length,
        default_list_id: lists[0]?.id ?? null,
        lists_ready: lists.length > 0,
        default_list_ready: lists.length > 0,
        working_hours_ready: true,
        normal_task_creation_ready: lists.length > 0,
        prerequisites_ready: lists.length > 0,
        explicit_setup_completed: true,
        setup_completed: true,
      };

      try {
        if (lists[0]?.id) {
          window.localStorage.setItem('lorvex:quickCapture:lastListId', JSON.stringify(lists[0].id));
        } else {
          window.localStorage.removeItem('lorvex:quickCapture:lastListId');
        }
      } catch {
        // localStorage can be unavailable in unusual browser contexts.
      }

      const defaultResponseForCommand = (
        command: string,
        payload?: Record<string, unknown>,
      ): unknown => {
        switch (command) {
          case 'get_preference':
            return payload?.key === 'language' ? JSON.stringify(locale) : null;
          case 'get_preferences':
            return [];
          case 'get_device_state':
            return null;
          case 'set_device_state':
            return null;
          case 'is_setup_complete':
            return true;
          case 'get_setup_status':
            return setupStatus;
          case 'get_today_bootstrap':
            return {
              overview,
              lists,
              preferences: {},
              timezone: 'America/Los_Angeles',
              today_ymd: fixtureTodayYmd,
              setup_status: setupStatus,
              current_focus: currentFocus,
            };
          case 'get_overview':
            return overview;
          case 'get_all_lists':
            return lists;
          case 'get_all_tags':
            return tags;
          case 'get_all_tasks':
          case 'get_today_pool_tasks':
          case 'get_tasks_by_date_range':
            return tasks;
          case 'get_overdue_tasks':
            return tasks.filter((task) => task.due_date && task.due_date < fixtureTodayYmd);
          case 'get_upcoming_tasks':
            return tasks.filter((task) => task.due_date && task.due_date >= fixtureTodayYmd);
          case 'list_saved_queries':
            return [];
          case 'load_saved_query':
            return null;
          case 'get_default_filesystem_bridge_root_path':
            return '~/LorvexSync';
          case 'get_pending_outbox_entries':
          case 'get_recent_outbox_entries':
            return [];
          case 'get_sync_status':
            return {
              sync_backend_kind_raw: null,
              sync_backend_kind: null,
              sync_backend_kind_effective: 'filesystem_bridge',
              sync_backend_kind_malformed: false,
              sync_backend_kind_malformed_reason: null,
              pending_count: 0,
              retrying_count: 0,
              failed_count: 0,
              oldest_pending_at: null,
              newest_pending_at: null,
              apply_cycle_count: 0,
              apply_cycle_last_started_at: null,
              apply_cycle_last_completed_at: null,
              apply_cycle_last_duration_ms: null,
              apply_cycle_last_received: 0,
              apply_cycle_last_processed: 0,
              apply_cycle_last_applied: 0,
              apply_cycle_last_skipped_duplicate: 0,
              apply_cycle_last_skipped_stale: 0,
              apply_cycle_last_skipped_deferred: 0,
              apply_cycle_last_skipped_malformed: 0,
              apply_cycle_last_error: null,
              apply_cycles_retained_received: 0,
              apply_cycles_retained_processed: 0,
              apply_cycles_retained_applied: 0,
              apply_cycles_retained_skipped_duplicate: 0,
              apply_cycles_retained_skipped_stale: 0,
              apply_cycles_retained_skipped_deferred: 0,
              apply_cycles_retained_skipped_malformed: 0,
              pending_inbox_count: 0,
              pending_inbox_oldest_at: null,
              pending_inbox_oldest_at_malformed: false,
              pending_inbox_oldest_at_malformed_reason: null,
              tombstone_count: 0,
              tombstone_oldest_deleted_at: null,
              tombstone_oldest_deleted_at_malformed: false,
              tombstone_oldest_deleted_at_malformed_reason: null,
              tombstone_newest_deleted_at: null,
              tombstone_newest_deleted_at_malformed: false,
              tombstone_newest_deleted_at_malformed_reason: null,
              conflict_log_count: 0,
              conflict_log_last_resolved_at: null,
              conflict_log_last_resolved_at_malformed: false,
              conflict_log_last_resolved_at_malformed_reason: null,
              ical_subscription_total_count: 0,
              ical_subscription_failing_count: 0,
              ical_subscription_never_refreshed_count: 0,
              ical_subscription_stale_count: 0,
              reseed_required: false,
              reseed_required_malformed: false,
              reseed_required_malformed_reason: null,
              last_synced_at: null,
              last_synced_at_malformed: false,
              last_synced_at_malformed_reason: null,
              last_success_at: null,
              last_success_at_malformed: false,
              last_success_at_malformed_reason: null,
              last_pull_at: null,
              last_pull_at_malformed: false,
              last_pull_at_malformed_reason: null,
              filesystem_bridge_last_pull_cursor: null,
              filesystem_bridge_last_pull_updated_at: null,
              filesystem_bridge_last_pull_device_id: null,
              filesystem_bridge_last_pull_event_id: null,
              filesystem_bridge_last_pull_cursor_malformed: false,
              filesystem_bridge_last_pull_cursor_malformed_reason: null,
              filesystem_bridge_lookback_known_id_skipped_last_run: 0,
              filesystem_bridge_lookback_known_id_skipped_last_run_malformed: false,
              filesystem_bridge_lookback_known_id_skipped_last_run_malformed_reason: null,
              filesystem_bridge_lookback_known_id_skipped_last_run_at: null,
              filesystem_bridge_lookback_known_id_skipped_last_run_at_malformed: false,
              filesystem_bridge_lookback_known_id_skipped_last_run_at_malformed_reason: null,
              device_id: 'e2e-device',
              last_error: null,
            };
          case 'quick_capture':
            const quickCapturePayload =
              payload?.request && typeof payload.request === 'object'
                ? (payload.request as Record<string, unknown>)
                : payload;
            windowRecord.__LORVEX_E2E__?.quickCaptureCalls.push(quickCapturePayload);
            return {
              id: 'task-captured',
              title:
                typeof quickCapturePayload?.title === 'string'
                  ? quickCapturePayload.title
                  : 'Captured task',
              body: quickCapturePayload?.body ?? null,
              status: 'open',
              due_date: quickCapturePayload?.dueDate ?? quickCapturePayload?.due_date ?? null,
              due_time: null,
              priority: quickCapturePayload?.priority ?? null,
              estimated_minutes:
                quickCapturePayload?.estimatedMinutes ??
                quickCapturePayload?.estimated_minutes ??
                null,
              list_id: quickCapturePayload?.listId ?? quickCapturePayload?.list_id ?? 'list-inbox',
              parent_task_id: null,
              created_at: fixtureNow,
              updated_at: fixtureNow,
              source_type: 'manual',
              source_id: null,
              deleted_at: null,
              deferred_until: null,
              defer_count: 0,
              tags: quickCapturePayload?.tags ?? null,
            };
          default:
            return null;
        }
      };

      Object.assign(windowRecord.__TAURI_INTERNALS__, {
        invoke: async (cmd: string, payload?: Record<string, unknown>) => {
          switch (cmd) {
            case 'plugin:event|listen': {
              const event = typeof payload?.event === 'string' ? payload.event : '';
              const handler = typeof payload?.handler === 'number' ? payload.handler : null;
              if (!event || handler == null) return null;
              tauriEventListeners.set(event, [
                ...(tauriEventListeners.get(event) ?? []),
                handler,
              ]);
              return handler;
            }
            case 'plugin:event|emit': {
              if (typeof payload?.event === 'string') {
                emitTauriEvent(payload.event, payload.payload);
              }
              return null;
            }
            case 'plugin:event|unlisten': {
              if (typeof payload?.event === 'string' && typeof payload?.eventId === 'number') {
                windowRecord.__TAURI_EVENT_PLUGIN_INTERNALS__?.unregisterListener(
                  payload.event,
                  payload.eventId,
                );
              }
              return null;
            }
            case 'get_someday_tasks':
            case 'get_due_reminders':
            case 'get_upcoming_reminders':
            case 'get_habit_reminder_policies':
            case 'get_due_habit_reminders':
            case 'get_todays_habits':
            case 'get_habits_with_stats':
            case 'get_error_logs':
            case 'get_events_by_date_range':
            case 'get_calendar_events_unified':
            case 'list_calendar_subscriptions':
              return [];
            case 'get_current_focus':
              return currentFocus;
            case 'get_focus_schedule':
            case 'consume_pending_deep_link':
            case 'get_mcp_server_status':
            case 'run_data_retention_cleanup':
            case 'acknowledge_pending_deep_link':
            case 'set_tray_icon_visibility':
            case 'set_badge_count':
            case 'hide_popover_window':
            case 'append_error_log':
              return defaultResponseForCommand(cmd, payload);
            default:
              return defaultResponseForCommand(cmd, payload);
          }
        },
        transformCallback: (callback?: (payload: unknown) => unknown) => {
          const id = callbackIdSeq;
          callbackIdSeq += 1;
          callbackRegistry.set(id, callback);
          return id;
        },
      });
    },
    {
      locale: localeCode,
      overview,
      lists,
      tags,
      tasks,
      currentFocus,
      fixtureNow: E2E_FIXTURE_NOW,
      fixtureTodayYmd: E2E_FIXTURE_TODAY_YMD,
    },
  );
}

export async function emitTauriEvent(
  page: Page,
  event: string,
  payload?: unknown,
): Promise<void> {
  await page.waitForFunction((eventName) => {
    const w = window as typeof window & {
      __LORVEX_E2E__?: { tauriEventListenerCount: (event: string) => number };
    };
    return (w.__LORVEX_E2E__?.tauriEventListenerCount(eventName) ?? 0) > 0;
  }, event);
  await page.evaluate(
    ({ eventName, eventPayload }) => {
      const w = window as typeof window & {
        __LORVEX_E2E__?: { emitTauriEvent: (event: string, payload?: unknown) => void };
      };
      w.__LORVEX_E2E__?.emitTauriEvent(eventName, eventPayload);
    },
    { eventName: event, eventPayload: payload },
  );
}

export const E2E_FIXTURES = {
  overview: DEFAULT_OVERVIEW,
  lists: DEFAULT_LISTS,
  tasks: DEFAULT_TASKS,
};
