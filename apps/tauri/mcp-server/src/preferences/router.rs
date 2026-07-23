use crate::contract::{
    CompleteSetupArgs, ControlAppUiArgs, DeletePreferenceArgs, GetPreferenceArgs, SetPreferenceArgs,
};
use crate::preferences;
use crate::preferences::ui;
use crate::system::setup;

crate::server::tool_macros::mcp_tools! {
    router = preferences_tool_router;

    write set_preference(SetPreferenceArgs) -> preferences::set_preference;
        "Set a user preference value as a normal JSON value. For string preferences, pass a plain string value such as \"list-id\" or \"midnight\", not a JSON-encoded string literal. Common keys: working_hours ({start,end} e.g. {\"start\":\"09:00\",\"end\":\"17:00\"}), dashboard_layout (see get_guide preferences topic for section types), language (en/zh/...), theme (system/light/dark), appearance_profile (clarity/studio/focus_compact/liquid_glass), weekly_review_day (weekday string: sunday/monday/tuesday/wednesday/thursday/friday/saturday), default_list_id (plain string list id).";

    write control_app_ui(ControlAppUiArgs) -> ui::control_app_ui;
        "Queue an assistant UI command in preferences for the running app to consume. Actions: enter_focus_mode|exit_focus_mode|focus_task|open_task|switch_view|set_theme|set_appearance_profile|set_language. Allowlisted arguments include view, theme, appearance_profile, and language.";

    read get_preference(GetPreferenceArgs) -> preferences::get_preference;
        "Read a single user preference by key. Returns null if not set. Use get_all_preferences to discover all configured keys.";

    raw {
        #[::rmcp::tool(
            description = "Delete a user preference, restoring its computed default. Use this to reset a preference to its default value rather than setting it to null. Pass dry_run=true to preview the prior value (and confirm the forbidden-key gate passes) before committing. Returns {deleted, key, previous, undo_token?, dry_run?}."
        )]
        pub(crate) fn delete_preference(
            &self,
            ::rmcp::handler::server::wrapper::Parameters(args):
                ::rmcp::handler::server::wrapper::Parameters<DeletePreferenceArgs>,
        ) -> Result<String, String> {
            let dry_run = args.dry_run;
            let key = args.key.clone();
            let key_for_extractor = key.clone();
            self.dispatch_dry_run(
                dry_run,
                "delete_preference",
                lorvex_domain::naming::ENTITY_PREFERENCE,
                move |_| format!("delete preference '{key}'"),
                crate::system::handler_support::singleton_id_extractor(key_for_extractor),
                move |conn| preferences::delete_preference(conn, args),
            )
        }
    }

    read_noargs get_all_preferences -> preferences::get_all_preferences;
        "Returns all user preferences as a key-to-value map. Use at session start to understand the user's configured preferences, or before suggesting preference changes to avoid overwriting existing settings.";

    read_noargs get_setup_status -> setup::get_setup_status;
        "Inspect Lorvex setup state. Returns whether setup is complete, whether completion was explicit, and whether the core prerequisites are actually ready: lists exist, default_list_id resolves to a real list, and working_hours are configured. Use this when first-run setup may still be incomplete.";

    write complete_setup(CompleteSetupArgs) -> setup::complete_setup;
        "Mark product setup as explicitly complete after core prerequisites such as lists, default_list_id resolution, and working_hours are in place. This records setup state; it does not create or complete ordinary user tasks.";
}
