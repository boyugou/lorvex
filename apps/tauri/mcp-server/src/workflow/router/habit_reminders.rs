//! Habit reminder policy CRUD tools.
//!
//! Owns the per-habit reminder slot surface (the "remind me at 7am for
//! exercise" configuration). `delete_habit_reminder_policy` routes
//! through `dispatch_dry_run` so the assistant can preview the prior
//! policy snapshot before committing.

use crate::contract::{
    DeleteHabitReminderPolicyArgs, GetHabitReminderPoliciesArgs, UpsertHabitReminderPolicyArgs,
};
use crate::habits::reminders;

crate::server::tool_macros::mcp_tools! {
    router = workflow_habit_reminders_tool_router;

    read get_habit_reminder_policies(GetHabitReminderPoliciesArgs)
        -> reminders::get_habit_reminder_policies;
        "List all habit reminder policies (reminder slots for habits like exercise, meditation, etc.). Use to check existing reminder configurations before creating new ones, or when the user asks about their reminder schedule. Returns an array of habit reminder policy objects (id, habit_id, habit_name, reminder_time, enabled, timestamps).";

    write upsert_habit_reminder_policy(UpsertHabitReminderPolicyArgs)
        -> reminders::upsert_habit_reminder_policy;
        "Create or update one habit reminder slot. Provide habit_id plus reminder_time in all cases; omit id to create a new slot or provide id to update an existing slot. Returns the upserted habit reminder policy object.";

    raw {
        #[::rmcp::tool(
            description = "Delete a habit reminder policy by ID. Use when the user no longer wants reminders for a habit, or when replacing an existing policy. Pass dry_run=true to preview the prior policy snapshot (habit_name, reminder_time) before committing. Returns {deleted, id, before, dry_run?}."
        )]
        pub(crate) fn delete_habit_reminder_policy(
            &self,
            ::rmcp::handler::server::wrapper::Parameters(args):
                ::rmcp::handler::server::wrapper::Parameters<DeleteHabitReminderPolicyArgs>,
        ) -> Result<String, String> {
            let dry_run = args.dry_run;
            let policy_id = args.id.clone();
            let policy_id_for_extractor = policy_id.clone();
            self.dispatch_dry_run(
                dry_run,
                "delete_habit_reminder_policy",
                lorvex_domain::naming::ENTITY_HABIT_REMINDER_POLICY,
                move |_| format!("delete habit reminder policy {policy_id}"),
                crate::system::handler_support::singleton_id_extractor(policy_id_for_extractor),
                move |conn| reminders::delete_habit_reminder_policy(conn, args),
            )
        }
    }
}
