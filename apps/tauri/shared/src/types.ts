// Shared TypeScript types for the Lorvex data model.
// Used by both the MCP server and (eventually) the Tauri frontend config layer.
//
// NOTE ON SCHEMA vs IPC TYPES:
// Some interfaces below represent the full SQLite schema shape. Tauri IPC
// commands may return a subset of fields (the Rust struct only serialises what
// the SELECT query produces). Where this distinction matters, the extra
// schema-only fields are marked with doc comments. The Tauri app maintains its
// own IPC-local type definitions in app/src/lib/ipc/ that match the Rust
// structs exactly; these shared types are the *schema* source of truth.

// ── Typed entity identifiers (branded strings) ───────────────────────
//
// TypeScript mirror of the Rust `lorvex-domain/src/ids.rs` typed-id
// newtype family. Each branded type is a `string & { __brand: '…' }`
// intersection — at runtime every value is still a bare UUIDv7
// string (or, for `ListId`, the `'inbox'` sentinel), so JSON / IPC /
// sync envelopes encode unchanged. At compile time the `__brand`
// tag prevents accidentally swapping a `TaskId` into a slot that
// expected a `ListId` (or any other id kind), restoring the same
// trust-boundary discipline the Rust newtypes give on the backend.
//
// Constructing a branded id is a cast (`as TaskId`) performed at
// the trust boundary where the raw `string` is first validated or
// minted — IPC payload decoders, sync envelope parsers, UUID
// generators, and the `'inbox'` sentinel. Once a value has crossed
// that boundary, downstream code threads the branded type through
// directly; the cast is not repeated. Surfaces that read plain
// `string` from a wire-shape interface (see below) and need to
// re-narrow it should validate first (UUID shape, sentinel match)
// and then cast — never cast unvalidated input.
//
// The wire-shape entity interfaces below (`Task`, `TaskList`,
// `Habit`, `CalendarEvent`, …) intentionally keep their identifier
// fields typed as plain `string`. Those interfaces describe what
// arrives over IPC / sync — values that have crossed a trust
// boundary but not yet been re-narrowed. Function signatures,
// repository methods, and component props that have already
// validated (or trust) their inputs are the natural surfaces for
// the branded types.
//
// New id kinds: add the branded alias here AND the corresponding
// `impl_typed_id!` in `lorvex-domain/src/ids.rs`. The two lists
// must move in lockstep.
export type TaskId = string & { readonly __brand: 'TaskId' };
export type ListId = string & { readonly __brand: 'ListId' };
export type EventId = string & { readonly __brand: 'EventId' };
export type TagId = string & { readonly __brand: 'TagId' };
export type HabitId = string & { readonly __brand: 'HabitId' };
export type MemoryKey = string & { readonly __brand: 'MemoryKey' };
export type ReminderId = string & { readonly __brand: 'ReminderId' };
export type ChecklistItemId = string & { readonly __brand: 'ChecklistItemId' };
export type HabitReminderPolicyId = string & { readonly __brand: 'HabitReminderPolicyId' };
export type MemoryRevisionId = string & { readonly __brand: 'MemoryRevisionId' };
export type TaskTagEdgeId = string & { readonly __brand: 'TaskTagEdgeId' };
export type TaskDependencyEdgeId = string & { readonly __brand: 'TaskDependencyEdgeId' };

// ── Types ────────────────────────────────────────────────────────────

/**
 * Canonical task lifecycle states. Use the `TASK_STATUS` const-map for
 * string-literal comparisons instead of raw `'open' | 'completed' | ...`
 * literals — keeps the four allowed values searchable from one place and
 * gives a single point of edit when the lifecycle changes. Mirrors the
 * Rust `lorvex_domain::naming` constants on the backend side.
 */
export const TASK_STATUS = {
  open: 'open',
  completed: 'completed',
  cancelled: 'cancelled',
  someday: 'someday',
} as const;

export type TaskStatus = typeof TASK_STATUS[keyof typeof TASK_STATUS];

/**
 * Returns `true` if the task has reached a terminal lifecycle state —
 * i.e. user attention is no longer expected. `completed` and `cancelled`
 * both qualify; `someday` is parked but still actionable.
 *
 * 35+ surfaces across the frontend re-implemented the
 * same `status === 'completed' || status === 'cancelled'` ad-hoc OR.
   * Some filters had subtly different ordering, and a future status
   * addition would have had to grep for both spellings. Centralizing
   * the predicate keeps the terminal-set definition in one place.
 */
export function isTerminalStatus(status: TaskStatus | string | null | undefined): boolean {
  return status === TASK_STATUS.completed || status === TASK_STATUS.cancelled;
}

export type Priority = 1 | 2 | 3;
export type TaskLateness = 'past_planned' | 'overdue_unhandled' | 'overdue_acknowledged';
// Canonical sync entity types, split into two narrow tuples — the
// Rust side already carries the same split via `naming::ALL_ENTITY_TYPES`
// (aggregate roots + independent children + content-addressed assets +
// audit stream) and `naming::edge::ALL_EDGE_TYPES` (relation edges).
// The combined set is exposed as `SYNC_ENTITY_TYPES` (aggregates ++
// edges, in declaration order) and mirrors `naming::ALL_SYNCABLE_TYPES`.
//
// Parent-owned collections (current_focus_items, focus_schedule_blocks,
// calendar_event_attendees, daily_review_*_links) are embedded in their
// parent aggregate payloads, not synced independently — they intentionally
// appear in neither tuple.
//
// Rust is the canonical source — it carries the typed `EntityKind` enum
// and the per-kind `entity_table_name` mapping. TS only narrows the
// shape for the IPC boundary; if a new kind is added in `naming/` without
// a mirroring arm here, a peer-emitted envelope decodes to plain `string`
// and silently bypasses the discriminated union.
//
// Drift between these lists and the Rust constants is enforced by
// `scripts/tests/contracts/sync_entity_types_parity.test.mjs` — adding,
// reordering, or removing entries without updating the Rust side (or
// vice-versa) fails CI.
export const SYNC_AGGREGATE_TYPES = [
  // Aggregate roots
  'task',
  'list',
  'habit',
  'tag',
  'calendar_event',
  'preference',
  'memory',
  'memory_revision',
  'daily_review',
  'current_focus',
  'focus_schedule',
  'calendar_subscription',
  // Independent children
  'task_reminder',
  'task_checklist_item',
  'habit_reminder_policy',
  // Audit stream
  'ai_changelog',
] as const;

export const SYNC_EDGE_TYPES = [
  'task_tag',
  'task_dependency',
  'task_calendar_event_link',
  'habit_completion',
] as const;

export const SYNC_ENTITY_TYPES = [
  ...SYNC_AGGREGATE_TYPES,
  ...SYNC_EDGE_TYPES,
] as const;

export type SyncAggregateType = typeof SYNC_AGGREGATE_TYPES[number];
export type SyncEdgeType = typeof SYNC_EDGE_TYPES[number];
export type SyncEntityType = SyncAggregateType | SyncEdgeType;
export type SyncOperation = 'upsert' | 'delete';

export const ASSISTANT_UI_ACTIONS = [
  'enter_focus_mode',
  'exit_focus_mode',
  'focus_task',
  'open_task',
  'switch_view',
  'set_theme',
  'set_appearance_profile',
  'set_language',
] as const;
export type AssistantUiAction = typeof ASSISTANT_UI_ACTIONS[number];

export const ASSISTANT_UI_VIEWS = [
  'today',
  'upcoming',
  'ai_changelog',
  'all_tasks',
  'someday',
  'calendar',
  'eisenhower',
  'kanban',
  'dependencies',
  'memory',
  'review',
  'daily_review',
  'settings',
  'list',
  'habits',
  'recurring',
] as const;
export type AssistantUiView = typeof ASSISTANT_UI_VIEWS[number];

export const THEME_MODES = [
  'paper',
  'light',
  'dark',
  'ember',
  'midnight',
  'liquid',
  'liquid_light',
  'mica',
  'mica_light',
  'adwaita',
  'adwaita_light',
  'system',
] as const;
export type ThemeMode = typeof THEME_MODES[number];

export const APPEARANCE_PROFILES = [
  'clarity',
  'studio',
  'focus_compact',
  'liquid_glass',
] as const;
export type AppearanceProfile = typeof APPEARANCE_PROFILES[number];

export const SUPPORTED_LOCALES = [
  'en', 'zh', 'zh-Hant', 'es', 'fr', 'de', 'ja', 'ko', 'pt', 'ru', 'hi',
  'ar', 'id', 'it', 'nl', 'tr', 'pl', 'uk', 'vi', 'th', 'ms',
  'bn', 'te', 'mr', 'ta', 'ml', 'el', 'ro', 'ur', 'fa', 'he',
] as const;
export const ASSISTANT_UI_LANGUAGES = ['system', ...SUPPORTED_LOCALES] as const;
export type AssistantUiLanguage = typeof ASSISTANT_UI_LANGUAGES[number];

export interface Task {
  id: string;
  title: string;
  body: string | null;
  raw_input: string | null;
  ai_notes: string | null;
  status: TaskStatus;
  list_id: string;
  tags: string[] | null;        // derived from task_tags join table at read time
  checklist_items: TaskChecklistItem[] | null; // derived from task_checklist_items child table at read time
  priority: Priority | null;
  due_date: string | null;      // YYYY-MM-DD
  due_time: string | null;      // HH:MM
  estimated_minutes: number | null;
  recurrence: string | null;    // RRULE-aligned JSON, e.g. {"FREQ":"WEEKLY","INTERVAL":1,"BYDAY":["MO","WE"]}
  recurrence_exceptions: string | null; // JSON array of YYYY-MM-DD dates excluded from the recurrence pattern
  depends_on: string[] | null;  // derived from task_dependencies edge table at read time
  spawned_from: string | null;  // parent task ID for recurring successors
  recurrence_group_id: string | null; // shared UUID linking all instances in a recurrence series
  canonical_occurrence_date: string | null; // stable RRULE cadence anchor, independent of due_date
  recurrence_instance_key: string | null; // opaque key identifying this specific occurrence — used by cross-device dedup when two devices spawn the same offline successor
  /** HLC version for sync LWW merge.
   *
   * `version` is internal sync plumbing — exposed on a subset of TS
   * types (Task, TaskChecklistItem, SyncOutboxEntry) but intentionally
   * NOT on Tag/TaskList/CurrentFocus/FocusSchedule/Habit/CalendarEvent
   * because their Tauri IPC projections omit it. Treat all uses of
   * `.version` on TS types as schema-level metadata. A UI that needs
   * cross-entity HLC comparison should fetch via a dedicated
   * diagnostics query, not rely on the primary IPC shape. */
  version: string;
  created_at: string;           // ISO 8601
  updated_at: string;
  completed_at: string | null;
  last_deferred_at: string | null;
  last_defer_reason: DeferReason | null;
  lateness_state?: TaskLateness | null; // derived relative to the current anchored local day
  planned_date: string | null;   // YYYY-MM-DD planned execution date
  defer_count: number;
  /** soft-delete / Trash. `null` means the task is active.
   *  Non-null ISO timestamp means the task is in the Trash — the backend
   *  hides it from every user-facing read path, so UI code only sees
   *  this field in the dedicated Trash view. The 30-day retention is
   *  enforced by `empty_trash` and a boot-time auto-purge. */
  archived_at?: string | null;
}

export interface TaskChecklistItem {
  id: string;
  task_id: string;
  position: number;
  text: string;
  completed_at: string | null;
  version: string;
  created_at: string;
  updated_at: string;
}

export const DEFER_REASON_NOT_TODAY = 'not_today' as const;

const ALL_DEFER_REASONS = [
  DEFER_REASON_NOT_TODAY,
  'blocked',
  'low_energy',
  'needs_breakdown',
  'needs_info',
] as const;

export type DeferReason = typeof ALL_DEFER_REASONS[number];

export interface TaskList {
  id: string;
  name: string;
  color: string | null;
  icon: string | null;
  description: string | null;
  ai_notes: string | null;
  created_at: string;
  updated_at: string;
}

export interface SyncOutboxEntry {
  /** INTEGER AUTOINCREMENT in SQLite; the Tauri IPC serialises as string. */
  id: string;
  entity_type: SyncEntityType;
  entity_id: string;
  operation: SyncOperation;
  /** Schema-only: present in the SQLite table but NOT returned by the Tauri
   *  `get_pending_outbox_entries` / `get_recent_outbox_entries` IPC commands. */
  version?: string;
  /** Schema-only: present in the SQLite table but NOT returned by the Tauri IPC commands. */
  payload_schema_version?: number;
  payload: string;
  device_id: string;
  created_at: string;
  synced_at: string | null;
  retry_count: number;
  last_retry_at: string | null;
}

export type HabitFrequencyType = 'daily' | 'weekly' | 'monthly' | 'times_per_week';

export interface Habit {
  id: string;
  name: string;
  icon: string | null;
  color: string | null;
  cue: string | null;
  frequency_type: HabitFrequencyType;
  /** `weekly` weekday set, Monday-first (0=Mon … 6=Sun). Empty for every
   *  non-weekly cadence and for weekly-every-day. */
  weekdays: number[];
  /** Completions required per week for a `times_per_week` cadence. */
  per_period_target: number;
  /** Reminder day-of-month for a `monthly` cadence (1–31), or null. */
  day_of_month: number | null;
  target_count: number;
  archived: boolean;
  created_at: string;
  updated_at: string;
}

export interface HabitCompletion {
  habit_id: string;
  completed_date: string;            // YYYY-MM-DD
  value: number;
  note: string | null;
  created_at: string;
  updated_at: string;
}

/** The minimal shape rendered in today-view habit rows and quick-
 *  adjust UI. Today's count + current streak + progress kind is all
 *  the rendering needs; extends `Habit` for the identity fields. */
export interface HabitSummary {
  id: string;
  name: string;
  icon: string | null;
  color: string | null;
  cue: string | null;
  frequency_type: HabitFrequencyType;
  /** `weekly` weekday set, Monday-first (0=Mon … 6=Sun). */
  weekdays: number[];
  /** Completions required per week for a `times_per_week` cadence. */
  per_period_target: number;
  /** Reminder day-of-month for a `monthly` cadence (1–31), or null. */
  day_of_month: number | null;
  target_count: number;
  progress_kind: 'binary' | 'accumulative';
  completions_today: number;
  current_streak: number;
}

/** Full stats for the Habits view — `Habit` plus computed fields. */
export interface HabitWithStats extends Habit {
  progress_kind: 'binary' | 'accumulative';
  current_streak: number;
  best_streak: number;
  total_completions: number;
  completions_last_30: number;
  completion_rate_30d: number;
  completions_today: number;
  /** Completion dates within the last 90 days, ISO YYYY-MM-DD strings. */
  recent_completion_dates: string[];
}

export interface ScheduleBlock {
  task_id: string | null;
  start_time: string;           // HH:MM
  end_time: string;             // HH:MM
  block_type: 'task' | 'buffer' | 'event';
  event_id: string | null;
  title: string | null;
}

// ── Calendar ────────────────────────────────────────────────────────

// Canonical set mirrors the Rust `CanonicalCalendarEventType` enum
// (`lorvex-domain/src/calendar.rs`). The Rust serde definition rejects
// non-canonical tags at deserialize time (see
// `lorvex-domain/src/calendar/tests.rs::canonical_calendar_event_type_serde_deserialize_rejects_unknown`)
// and every persistence layer routes through `validate` before write,
// so the wire payload is guaranteed to land on one of these four
// variants — there is no `'unknown'` catch-all to handle in the UI.
export type CalendarEventType = 'event' | 'birthday' | 'anniversary' | 'memorial';

/**
 * Attendee row projected onto a calendar event. Mirrors the three
 * columns the schema owns on `calendar_event_attendees` (`email`,
 * `name`, `status`). Forward-compat extras a newer peer emitted live
 * on `calendar_event_attendee_shadow` and ride along through the sync
 * envelope, but the read-side projections (MCP JSON, Tauri IPC) only
 * surface the known keys.
 */
export interface CalendarEventAttendee {
  email: string;
  name?: string | null;
  status?: string | null;
}

export interface CalendarEvent {
  id: string;
  title: string;
  description: string | null;
  recurrence: string | null;          // RRULE-aligned JSON
  recurrence_exceptions: string | null; // JSON: string[] of YYYY-MM-DD
  start_date: string;                 // YYYY-MM-DD
  start_time: string | null;          // HH:MM
  end_date: string | null;            // YYYY-MM-DD
  end_time: string | null;            // HH:MM
  all_day: boolean;
  location: string | null;
  url: string | null;
  timezone: string | null;
  color: string | null;
  event_type: CalendarEventType;
  person_name: string | null;
  created_at: string;
  updated_at: string;
  /** Merged attendee array. `null` (or omitted) means "no attendees" —
   *  same convention the MCP server's `enrich_event_with_attendees`
   *  uses. Optional because schema-shape reads that bypass the
   *  enrich step (raw outbox payloads, store-row builders before the
   *  IPC overlay) produce a struct without this key. */
  attendees?: CalendarEventAttendee[] | null;
}

// ── Tags ────────────────────────────────────────────────────────────

export interface Tag {
  id: string;
  display_name: string;
  lookup_key: string;
  color: string | null;
  created_at: string;
  updated_at: string;
}

// ── Task Reminders ──────────────────────────────────────────────────

export interface TaskReminder {
  id: string;
  task_id: string;
  reminder_at: string;                // ISO 8601
  dismissed_at: string | null;
  cancelled_at: string | null;
  created_at: string;
  /** Device-local delivery state. Only present when queried via due/upcoming endpoints. */
  delivery_state?: string;
}

// ── Daily Reviews ───────────────────────────────────────────────────

export interface DailyReview {
  date: string;                       // YYYY-MM-DD
  summary: string;
  mood: number | null;                // 1-5
  energy_level: number | null;        // 1-5
  wins: string | null;
  blockers: string | null;
  learnings: string | null;
  ai_synthesis: string | null;
  timezone: string | null;
  created_at: string;
  updated_at: string;
  // derived arrays attached by the Tauri backend and
  // MCP enrichment paths. Optional because direct row reads (e.g.
  // a fresh fetch that skips enrichment) don't include them.
  linked_task_ids?: string[];
  linked_list_ids?: string[];
}

// ── Habit Reminders ─────────────────────────────────────────────────

export interface HabitReminderPolicy {
  id: string;
  habit_id: string;
  reminder_time: string;              // HH:MM
  enabled: boolean;
  created_at: string;
  updated_at: string;
  /** Joined at query time by the Tauri IPC layer (not a stored column).
   * frontend previously shadowed this shared type with a
   *  local extension — surface the field here instead so every
   *  consumer sees the same shape. Optional because not every read
   *  path joins habits (e.g. raw sync payload reads). */
  habit_name?: string;
}

// ── Recurrence (strongly typed JSON) ────────────────────────────────

type RecurrenceFrequency = 'DAILY' | 'WEEKLY' | 'MONTHLY' | 'YEARLY';
type RecurrenceWeekdayCode = 'SU' | 'MO' | 'TU' | 'WE' | 'TH' | 'FR' | 'SA';
type RecurrenceDay =
  | RecurrenceWeekdayCode
  | `${number}${RecurrenceWeekdayCode}`
  | `+${number}${RecurrenceWeekdayCode}`
  | `-${number}${RecurrenceWeekdayCode}`;

export interface RecurrenceRule {
  FREQ: RecurrenceFrequency;
  INTERVAL?: number;
  BYDAY?: RecurrenceDay[];
  BYMONTH?: number[];
  BYMONTHDAY?: number[];
  BYSETPOS?: number[];
  WKST?: RecurrenceWeekdayCode;
  COUNT?: number;
  UNTIL?: string;                     // YYYY-MM-DD
}

// ── Provider Calendar Events (local-only, not synced) ───────────────

export interface TaskProviderEventLink {
  task_id: string;
  provider_kind: string;
  provider_scope: string;
  provider_event_key: string;
  created_at: string;
  updated_at: string;
}
