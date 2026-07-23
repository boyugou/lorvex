//! Current focus + focus schedule tools.
//!
//! Owns the daily-focus surface: set/get/append/clear/remove tasks on the
//! current focus plan, plus propose/save/read the time-blocked Focus
//! Schedule for that plan.

use crate::contract::{
    AddToCurrentFocusArgs, ClearCurrentFocusArgs, GetCurrentFocusArgs, GetSavedFocusScheduleArgs,
    ProposeDailyScheduleArgs, RemoveFromCurrentFocusArgs, SaveFocusScheduleArgs,
    SetCurrentFocusArgs,
};
use crate::focus::current;
use crate::focus::schedule;
use tokio_util::sync::CancellationToken;

crate::server::tool_macros::mcp_tools! {
    router = workflow_focus_tool_router;

    write set_current_focus(SetCurrentFocusArgs) -> current::set_current_focus;
        "Replace today's focus plan with a new ordered task list and briefing. This overwrites the existing focus plan in one shot and returns the full focus plan with embedded task objects.";

    read get_current_focus(GetCurrentFocusArgs) -> current::get_current_focus;
        "Returns today's focus plan (or for a specific date), including full task objects. Use when the user asks what they should focus on today, before proposing changes to today's schedule, or to check if a focus plan exists before creating one. Returns the focus plan with embedded task objects, or null if none exists.";

    write add_to_current_focus(AddToCurrentFocusArgs) -> current::add_to_current_focus;
        "Append task(s) to today's focus plan without replacing the existing order. Duplicates are skipped, and a missing focus plan is created on demand. Returns the full updated focus plan with embedded task objects.";

    raw {
        #[::rmcp::tool(
            description = "Generate a time-blocked Focus Schedule for today's focus tasks. Arranges only focus tasks into working hours around calendar events. Requires a focus plan to be set first (use set_current_focus). Does NOT independently select tasks — it only schedules what is already in today's focus. The optional date parameter defaults to today. Returns {date, working_hours, total_minutes_available, calendar_events_count, slots, blocks, unscheduled}."
        )]
        pub(crate) async fn propose_daily_schedule(
            &self,
            ::rmcp::handler::server::wrapper::Parameters(args):
                ::rmcp::handler::server::wrapper::Parameters<ProposeDailyScheduleArgs>,
            ct: CancellationToken,
        ) -> Result<String, String> {
            // #2133: multi-step calendar/tasks join plus scheduling loop;
            // propagate cancellation through to short-circuit mid-plan.
            //
            // #2177: scheduling loop holds the writer for long enough to
            // stall parallel reads on shared tokio workers. Route
            // through `spawn_blocking` so the reactor thread stays hot.
            self.with_conn_typed_async(move |conn| {
                schedule::propose_daily_schedule(conn, args, &ct)
            })
            .await
        }
    }

    write save_focus_schedule(SaveFocusScheduleArgs) -> schedule::save_focus_schedule;
        "Save and apply a time-blocked Focus Schedule. Use after propose_daily_schedule to persist the schedule for dashboard display and automatically sync its task blocks to today's focus. This directly applies the schedule — no separate accept step needed. Returns the saved schedule with blocks and task_ids_applied.";

    read get_saved_focus_schedule(GetSavedFocusScheduleArgs)
        -> schedule::get_saved_focus_schedule;
        "Read the saved focus schedule for a specific date (defaults to today). Returns the schedule with its time-blocked task assignments, or null if no schedule exists. Use this to check whether a schedule was already created before proposing a new one.";

    write clear_current_focus(ClearCurrentFocusArgs) -> current::clear_current_focus;
        "Remove the focus plan for a given date (defaults to today). Use when the user wants to start their focus from scratch, or at end-of-day cleanup. Returns {cleared, date}.";

    write remove_from_current_focus(RemoveFromCurrentFocusArgs)
        -> current::remove_from_current_focus;
        "Remove a specific task from today's focus. Use when a task becomes irrelevant mid-day, is completed and should be dropped from the focus plan, or during focus adjustment. If the removed task was the last one, the focus plan is cleared entirely. Returns the updated focus.";
}
