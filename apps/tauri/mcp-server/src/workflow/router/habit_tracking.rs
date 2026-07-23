//! Habit definition + completion tracking tools.
//!
//! Owns the habit lifecycle (create/update/delete) plus completion writes
//! (complete/uncomplete/batch) and read-side computed stats. Every write
//! routes through `idempotency::run_with_cache` so retries don't
//! double-increment streak counts; `delete_habit` additionally routes
//! through `dispatch_dry_run` so the cascade impact (completions destroyed,
//! reminder policies destroyed) is previewable.

use crate::contract::{
    frequency_type_to_str, BatchCompleteHabitArgs, CompleteHabitArgs, CreateHabitArgs,
    DeleteHabitArgs, GetHabitCompletionsArgs, GetHabitStatsArgs, GetHabitsSummaryArgs,
    UncompleteHabitArgs, UpdateHabitArgs,
};
use crate::habits;
use crate::server::LorvexMcpServer;
use rmcp::{handler::server::wrapper::Parameters, tool, tool_router};

#[tool_router(router = workflow_habit_tracking_tool_router, vis = "pub(crate)")]
impl LorvexMcpServer {
    #[tool(
        name = "create_habit",
        description = "Create a new habit to track. Supports daily, weekly, or custom frequency, plus optional cue field when the user knows the trigger. Returns the created habit. Use when the user expresses a desire to build a new routine or track a recurring behavior (exercise, reading, meditation, etc.)."
    )]
    pub(crate) fn create_habit(
        &self,
        Parameters(args): Parameters<CreateHabitArgs>,
    ) -> Result<String, String> {
        // gate the write through the
        // payload-checksum-verified idempotency cache. A retried
        // failed the lookup_key UNIQUE index but the audit row
        // for the failed attempt still landed) and a duplicate
        // changelog entry.
        self.with_conn_typed(|conn| {
            let request_repr = crate::runtime::idempotency::canonical_request_repr(&args)?;
            crate::runtime::idempotency::run_with_cache(
                conn,
                "create_habit",
                &request_repr,
                args.idempotency_key.as_deref(),
                |conn| {
                    habits::create_habit(
                        conn,
                        habits::CreateHabitParams {
                            name: &args.name,
                            icon: args.icon.as_deref(),
                            color: args.color.as_deref(),
                            cue: args.cue.as_deref(),
                            frequency_type: args.frequency_type.map(frequency_type_to_str),
                            weekdays: args.weekdays.as_deref(),
                            per_period_target: args.per_period_target,
                            day_of_month: args.day_of_month,
                            target_count: args.target_count,
                        },
                    )
                },
            )
        })
    }

    #[tool(
        name = "update_habit",
        description = "Update an existing habit's properties. Use null to clear optional fields like icon, color, or cue. Set frequency_type (with weekdays / per_period_target / day_of_month as needed) to replace the cadence. Use when adjusting a habit's frequency, changing its visual identity, refining its trigger metadata, or archiving it. Returns the full updated habit object."
    )]
    pub(crate) fn update_habit(
        &self,
        Parameters(args): Parameters<UpdateHabitArgs>,
    ) -> Result<String, String> {
        // idempotency cache for update_habit.
        self.with_conn_typed(|conn| {
            let request_repr = crate::runtime::idempotency::canonical_request_repr(&args)?;
            crate::runtime::idempotency::run_with_cache(
                conn,
                "update_habit",
                &request_repr,
                args.idempotency_key.as_deref(),
                |conn| {
                    habits::update_habit(
                        conn,
                        habits::UpdateHabitParams {
                            id: &args.id,
                            name: args.name.as_deref(),
                            icon: args.icon.as_deref(),
                            color: args.color.as_deref(),
                            cue: args.cue.as_deref(),
                            frequency_type: args.frequency_type.map(frequency_type_to_str),
                            weekdays: args.weekdays.as_deref(),
                            per_period_target: args.per_period_target,
                            day_of_month: args.day_of_month,
                            target_count: args.target_count,
                            archived: args.archived,
                        },
                    )
                },
            )
        })
    }

    #[tool(
        name = "delete_habit",
        description = "Permanently delete a habit definition plus its completions and reminder policies. Use this only for true removal; update_habit archived=true is the non-destructive hide/archive path. Pass dry_run=true to preview the cascade counts (completions_destroyed, reminder_policies_destroyed) before actually destroying streak history. Returns {deleted, id, name, completions_destroyed, reminder_policies_destroyed, previous, dry_run?} — surface completions_destroyed to the user so long-term streak loss isn't silent."
    )]
    pub(crate) fn delete_habit(
        &self,
        Parameters(args): Parameters<DeleteHabitArgs>,
    ) -> Result<String, String> {
        // #3607 — derive-driven UUID-shape validation at the trust
        // boundary. The router-level wiring is the right home because
        // the inner `habits::delete_habit` already takes a typed
        // `HabitId` newtype.
        use crate::contract_validate::ContractValidate;
        args.validate_shape().map_err(|e| e.to_string())?;
        // idempotency cache for delete_habit. Wired
        // inside the dispatch_dry_run closure so a real-mode retry
        // short-circuits to the cached cascade-count response without
        // re-running the destructive cascade twice. Dry-run mode
        // rolls back, so the cache record from a dry run never
        // persists.
        let dry_run = args.dry_run;
        // route through `canonical_request_repr` to align with every
        // sibling habit tool (`create_habit`, `update_habit`,
        // `complete_habit`, `uncomplete_habit`, `batch_complete_habit`).
        // produced two real drifts: (a) a future field reorder on
        // `DeleteHabitArgs` silently invalidated every cached entry; and
        // (b) the canonical helper strips `dry_run` from the checksum so
        // a preview-then-commit shares an idempotency-key cache slot,
        // but the bare `to_string` kept it — so the assistant's
        // standard "preview with `dry_run:true`, then run with
        // `dry_run:false`" flow under one idempotency key surfaced
        // `ChecksumMismatch` instead of running the real call.
        let request_repr =
            crate::runtime::idempotency::canonical_request_repr(&args).map_err(String::from)?;
        let habit_id = args.id;
        let idempotency_key = args.idempotency_key;
        let habit_id_for_closure = lorvex_domain::HabitId::from_trusted(habit_id.clone());
        let habit_id_for_summary = habit_id;
        self.dispatch_dry_run(
            dry_run,
            "delete_habit",
            lorvex_domain::naming::ENTITY_HABIT,
            move |_| format!("delete habit {habit_id_for_summary}"),
            crate::system::handler_support::extract_top_level_id,
            move |conn| {
                crate::runtime::idempotency::run_with_cache(
                    conn,
                    "delete_habit",
                    &request_repr,
                    idempotency_key.as_deref(),
                    |conn| habits::delete_habit(conn, &habit_id_for_closure),
                )
            },
        )
    }

    #[tool(
        name = "complete_habit",
        description = "Record a habit completion for a given date (defaults to today). Each call increments the completion count by 1. For habits with target_count > 1 (e.g. 'drink water 3×/day'), call this once per completion until completions_today >= target_count. Use uncomplete_habit to remove all completions for that date. Returns the habit completion record (habit_id, completed_date, value, note, timestamps)."
    )]
    pub(crate) fn complete_habit(
        &self,
        Parameters(args): Parameters<CompleteHabitArgs>,
    ) -> Result<String, String> {
        // #3607 — derive-driven UUID-shape validation + note length
        // cap at the trust boundary, before idempotency cache lookup.
        use crate::contract_validate::ContractValidate;
        args.validate_shape().map_err(|e| e.to_string())?;
        // idempotency cache. A retried
        // increment, doubling streak counts on transient retry.
        self.with_conn_typed(|conn| {
            let request_repr = crate::runtime::idempotency::canonical_request_repr(&args)?;
            crate::runtime::idempotency::run_with_cache(
                conn,
                "complete_habit",
                &request_repr,
                args.idempotency_key.as_deref(),
                |conn| {
                    let habit_id = lorvex_domain::HabitId::from_trusted(args.id.clone());
                    habits::complete_habit(
                        conn,
                        &habit_id,
                        args.date.as_deref(),
                        args.note.as_deref(),
                    )
                },
            )
        })
    }

    #[tool(
        name = "uncomplete_habit",
        description = "Remove ALL completions for a habit on a given date (defaults to today). For habits with target_count > 1, this resets the entire day's count to zero, not just one increment. Use when the user reports they didn't complete a habit, or to correct a mistake. Returns {deleted, habit_id, habit_name, completed_date}."
    )]
    pub(crate) fn uncomplete_habit(
        &self,
        Parameters(args): Parameters<UncompleteHabitArgs>,
    ) -> Result<String, String> {
        // idempotency cache.
        self.with_conn_typed(|conn| {
            let request_repr = crate::runtime::idempotency::canonical_request_repr(&args)?;
            crate::runtime::idempotency::run_with_cache(
                conn,
                "uncomplete_habit",
                &request_repr,
                args.idempotency_key.as_deref(),
                |conn| {
                    let habit_id = lorvex_domain::HabitId::from_trusted(args.id.clone());
                    habits::uncomplete_habit(conn, &habit_id, args.date.as_deref())
                },
            )
        })
    }

    #[tool(
        name = "batch_complete_habit",
        description = "Record one completion increment for multiple habits in one call. Atomic: any per-habit failure rolls the entire batch back (#3006-H7). Use this for multi-habit check-ins; habits with higher target_count can still be incremented again with another call. Returns {results, count} on success, where `count == len(habit_ids)`."
    )]
    pub(crate) fn batch_complete_habit(
        &self,
        Parameters(args): Parameters<BatchCompleteHabitArgs>,
    ) -> Result<String, String> {
        // idempotency cache. A retried batch on a
        // the batch — the rollback contract only protects against
        // partial failures within a single call.
        self.with_conn_typed(|conn| {
            let request_repr = crate::runtime::idempotency::canonical_request_repr(&args)?;
            crate::runtime::idempotency::run_with_cache(
                conn,
                "batch_complete_habit",
                &request_repr,
                args.idempotency_key.as_deref(),
                |conn| habits::batch_complete_habit(conn, &args.habit_ids, args.date.as_deref()),
            )
        })
    }

    #[tool(
        name = "get_habit_stats",
        description = "Read computed statistics for one habit. Includes streaks, totals, 30-day completion rate, and today's completion count, and returns the habit object with those derived stats attached."
    )]
    pub(crate) fn get_habit_stats(
        &self,
        Parameters(args): Parameters<GetHabitStatsArgs>,
    ) -> Result<String, String> {
        self.with_read_conn_typed(|conn| {
            let habit_id = lorvex_domain::HabitId::from_trusted(args.id.clone());
            habits::get_habit_stats(conn, &habit_id)
        })
    }

    #[tool(
        name = "get_habit_completions",
        description = "Get recent completion history for a habit. Returns completions for the last N days (default 30, max 365). Use to analyze adherence patterns over time, identify missed days, or when the user asks about their completion history for a specific habit."
    )]
    pub(crate) fn get_habit_completions(
        &self,
        Parameters(args): Parameters<GetHabitCompletionsArgs>,
    ) -> Result<String, String> {
        self.with_read_conn_typed(|conn| {
            let habit_id = lorvex_domain::HabitId::from_trusted(args.id.clone());
            habits::get_habit_completions(conn, &habit_id, args.days)
        })
    }

    #[tool(
        name = "get_habits_summary",
        description = "Return all habits with computed stats in one bounded read. Includes streaks, completion totals, 30-day completion rate, and today's progress for habit review and check-in surfaces."
    )]
    pub(crate) fn get_habits_summary(
        &self,
        Parameters(args): Parameters<GetHabitsSummaryArgs>,
    ) -> Result<String, String> {
        self.with_read_conn_typed(|conn| {
            habits::get_habits_summary(conn, args.include_archived.unwrap_or(false))
        })
    }
}
