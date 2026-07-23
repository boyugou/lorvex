//! The root [`ClapCommand`] enum — the top-level subcommand tree wiring
//! every CLI verb to its per-domain argument struct.

use clap::Subcommand;
use clap_complete::Shell;

use super::super::command::McpInstallTarget;
use super::shared::*;
use super::*;

#[derive(Subcommand, Debug)]
pub(in crate::cli) enum ClapCommand {
    /// Run first-run setup: create the DB, register the CLI as MCP host, optionally install MCP configs.
    #[command(after_help = "EXAMPLES:\n  \
        lorvex setup\n  \
        lorvex setup --install-mcp-for claude-code\n")]
    Setup {
        /// MCP client to pre-install config for.
        #[arg(long = "install-mcp-for", value_enum)]
        install_mcp_for: Option<McpInstallTarget>,
    },

    /// Health check with structured warnings.
    #[command(after_help = "EXAMPLES:\n  lorvex doctor\n")]
    Doctor,

    /// Quick dashboard summary (open/overdue/focus counts, DB size).
    #[command(after_help = "EXAMPLES:\n  lorvex status\n")]
    Status,

    /// Sync diagnostics.
    #[command(
        subcommand,
        after_help = "EXAMPLES:\n  lorvex sync status\n  lorvex sync outbox\n  lorvex sync outbox -l 25\n"
    )]
    Sync(SyncCmd),

    /// Recent assistant-authored write changelog.
    #[command(
        after_help = "EXAMPLES:\n  lorvex changelog\n  lorvex changelog --entity-type task --operation update -l 20\n"
    )]
    Changelog(ChangelogArgs),

    /// Filtered task listing equivalent to MCP list_tasks.
    #[command(after_help = "EXAMPLES:\n  \
        lorvex tasks\n  \
        lorvex tasks --status all --tag Work --due-from 2026-04-01 --due-to 2026-04-30\n  \
        lorvex tasks --blocked-only --sort-by priority_due\n")]
    Tasks(TasksArgs),

    /// Task dependency graph query equivalent to MCP get_dependency_graph.
    #[command(
        name = "graph",
        after_help = "EXAMPLES:\n  \
        lorvex graph\n  \
        lorvex graph --task-id task-1\n  \
        lorvex graph --list inbox --include-inactive\n"
    )]
    DependencyGraph(DependencyGraphArgs),

    /// Full-text search over tasks.
    #[command(
        after_help = "EXAMPLES:\n  lorvex search deep work\n  lorvex search \"tax filing\" -l 5\n"
    )]
    Search(SearchArgs),

    /// Show all lists.
    #[command(after_help = "EXAMPLES:\n  lorvex lists\n")]
    Lists,

    /// List operations (show, create, update, delete).
    #[command(
        subcommand,
        after_help = "EXAMPLES:\n  \
        lorvex list <list-id>\n  \
        lorvex list health\n  \
        lorvex list create \"Work Queue\" --color \"#00ff00\"\n  \
        lorvex list update list-1 -n \"Later\"\n  \
        lorvex list delete list-1\n"
    )]
    List(ListCmd),

    /// Move tasks into a list.
    #[command(after_help = "EXAMPLES:\n  lorvex move list-1 task-1 task-2\n")]
    Move(MoveArgs),

    /// Show a single task's full detail.
    #[command(after_help = "EXAMPLES:\n  lorvex show task-1\n")]
    Show(ShowArgs),

    /// Tasks due today (priority-sorted).
    #[command(after_help = "EXAMPLES:\n  lorvex today\n  lorvex today -l 5\n")]
    Today(LimitArgs),

    /// Overdue open tasks (priority-sorted).
    #[command(after_help = "EXAMPLES:\n  lorvex overdue -l 3\n")]
    Overdue(LimitArgs),

    /// Upcoming tasks in the next N days.
    #[command(after_help = "EXAMPLES:\n  lorvex upcoming\n  lorvex upcoming -d 14 -l 7\n")]
    Upcoming(UpcomingArgs),

    /// Open tasks that have been deferred at least once.
    #[command(
        after_help = "EXAMPLES:\n  lorvex deferred\n  lorvex deferred --list list-1 -l 25\n"
    )]
    Deferred(DeferredArgs),

    /// Task reminder queries and mutations.
    #[command(
        subcommand,
        after_help = "EXAMPLES:\n  \
        lorvex reminder due\n  \
        lorvex reminder upcoming --hours 48 -l 25\n  \
        lorvex reminder set task-1 --at 2026-05-01T09:00:00Z --at 2026-05-01T17:00:00Z\n  \
        lorvex reminder add task-1 2026-05-01T09:00:00Z\n  \
        lorvex reminder remove task-1 reminder-1\n  \
        lorvex reminder clear task-1\n"
    )]
    Reminder(ReminderCmd),

    /// Focus planning (show / set / add / remove / clear).
    #[command(
        subcommand,
        after_help = "EXAMPLES:\n  \
        lorvex focus\n  \
        lorvex focus --date 2026-05-01\n  \
        lorvex focus set task-a task-b --briefing \"Deep work\" --date 2026-05-01\n  \
        lorvex focus add task-c\n  \
        lorvex focus remove task-a\n  \
        lorvex focus clear\n"
    )]
    Focus(FocusCmd),

    /// Review journal and weekly review snapshots.
    #[command(
        subcommand,
        after_help = "EXAMPLES:\n  \
        lorvex review get --date 2026-06-01\n  \
        lorvex review history --since 2026-06-01 --limit 7\n  \
        lorvex review weekly --completed-limit 10\n  \
        lorvex review brief --completed-limit 25 --someday-limit 10\n  \
        lorvex review add --summary \"Good progress\" --mood 4 --energy 3 --linked-task task-1\n  \
        lorvex review amend 2026-06-01 --summary \"Updated\" --linked-task-set task-2\n"
    )]
    Review(ReviewCmd),

    /// Export the DB to a zip archive.
    #[command(after_help = "EXAMPLES:\n  lorvex export backup.zip\n")]
    Export(PathArgs),

    /// Import an exported zip archive.
    #[command(after_help = "EXAMPLES:\n  lorvex import backup.zip\n")]
    Import(PathArgs),

    /// Capture a new task.
    #[command(after_help = "EXAMPLES:\n  \
        lorvex capture \"Write tests\"\n  \
        lorvex capture \"Write tests\" --list list-1\n")]
    Capture(CaptureArgs),

    /// Update task core fields.
    #[command(after_help = "EXAMPLES:\n  \
        lorvex update task-1 --title \"Review PR carefully\" --priority 1\n  \
        lorvex update task-1 --body \"Notes\" --due-date 2026-04-30 --due-time 09:30\n  \
        lorvex update task-1 --clear-due-date --clear-priority\n")]
    Update(Box<TaskUpdateArgs>),

    /// Append text to a task's body, separated by a blank line.
    ///
    /// mirrors MCP `append_to_task_body`. Distinct from
    /// `update --body` (which replaces) — `append-body` concatenates
    /// onto whatever body is already there.
    #[command(after_help = "EXAMPLES:\n  \
        lorvex append-body task-1 Reviewed the spec\n  \
        lorvex append-body task-1 \"Step 2 done\"\n")]
    AppendBody(TaskFreeTextArgs),

    /// Append AI-only notes to a task with a date prefix.
    ///
    /// writes task AI notes. Each call concatenates
    /// the note onto `ai_notes`, prefixed with today's UTC date and
    /// separated from the prior block with `\n\n---\n`. Distinct from
    /// `update --ai-notes` (which replaces).
    #[command(after_help = "EXAMPLES:\n  \
        lorvex add-ai-notes task-1 \"Considered tradeoff X\"\n  \
        lorvex add-ai-notes task-1 \"Plan revised\"\n")]
    AddAiNotes(TaskFreeTextArgs),

    /// Manage recurrence-exception dates on a recurring task.
    ///
    /// mirrors MCP `add_task_recurrence_exception` /
    /// `remove_task_recurrence_exception`. The exception date must be
    /// an actual occurrence of the task's recurrence rule.
    #[command(
        subcommand,
        after_help = "EXAMPLES:\n  \
        lorvex recurrence-exception add task-1 2026-05-07\n  \
        lorvex recurrence-exception remove task-1 2026-05-07\n"
    )]
    RecurrenceException(RecurrenceExceptionCmd),

    /// Mark one or more tasks complete.
    #[command(
        after_help = "EXAMPLES:\n  lorvex complete task-1\n  lorvex complete task-1 task-2\n"
    )]
    Complete(TaskIdsArgs),

    /// Reopen one or more completed / cancelled tasks.
    #[command(after_help = "EXAMPLES:\n  lorvex reopen task-1\n  lorvex reopen task-1 task-2\n")]
    Reopen(TaskIdsArgs),

    /// Cancel a task (optionally the whole recurring series).
    #[command(after_help = "EXAMPLES:\n  lorvex cancel task-1\n  lorvex cancel task-1 --series\n")]
    Cancel(CancelArgs),

    /// Move tasks through the Trash lifecycle.
    #[command(
        subcommand,
        after_help = "EXAMPLES:\n  \
        lorvex trash move task-1 task-2\n  \
        lorvex trash restore task-1 task-2\n  \
        lorvex trash delete task-1 --dry-run\n  \
        lorvex trash delete task-1 task-2 --dry-run\n"
    )]
    Trash(TrashCmd),

    /// Defer a task to a future date.
    #[command(after_help = "EXAMPLES:\n  \
        lorvex defer task-1 -d 3 --reason \"Heads down\"\n  \
        lorvex defer task-1 -d 1 --structured-reason needs_info\n")]
    Defer(DeferArgs),

    /// Calendar queries and mutations.
    #[command(
        subcommand,
        after_help = "EXAMPLES:\n  \
        lorvex calendar list -l 5\n  \
        lorvex calendar show event-1\n  \
        lorvex calendar today\n  \
        lorvex calendar create \"Design review\" --start-date 2026-04-30 --start-time 09:30 --end-time 10:00\n  \
        lorvex calendar batch-create --events-json '[{\"title\":\"Design review\",\"start_date\":\"2026-04-30\"}]'\n  \
        lorvex calendar update event-1 --location \"Room 4\" --all-day\n  \
        lorvex calendar link event-1 task-1 task-2\n  \
        lorvex calendar provider-link task-1 --provider-kind eventkit --provider-event-key ek-1\n  \
        lorvex calendar add-exception event-1 2026-05-07\n  \
        lorvex calendar export-ics --from 2026-05-01 --to 2026-05-31\n  \
        lorvex calendar delete event-1\n"
    )]
    Calendar(CalendarCmd),

    /// List habits with today's completion status.
    #[command(after_help = "EXAMPLES:\n  lorvex habits\n")]
    Habits,

    /// Habit operations (create / update / delete / complete / stats).
    #[command(
        subcommand,
        after_help = "EXAMPLES:\n  \
        lorvex habit create \"Morning pages\" --icon M --target-count 1\n  \
        lorvex habit update habit-1 --name \"Morning walk\" --frequency-type daily\n  \
        lorvex habit delete habit-1\n  \
        lorvex habit complete habit-1 --date 2026-04-24 --note \"Done after lunch\"\n  \
        lorvex habit uncomplete habit-1 --date 2026-04-24\n  \
        lorvex habit stats habit-1 -d 14\n"
    )]
    Habit(HabitCmd),

    /// AI memory store (list / show / write / delete / history / restore).
    #[command(
        subcommand,
        after_help = "EXAMPLES:\n  \
        lorvex memory list\n  \
        lorvex memory show user_preferences\n  \
        lorvex memory write user_preferences \"Prefers morning planning\"\n  \
        lorvex memory history user_preferences -l 10\n"
    )]
    Memory(MemoryCmd),

    /// Preference operations (list / get / set / delete).
    #[command(
        subcommand,
        after_help = "EXAMPLES:\n  \
        lorvex preference list\n  \
        lorvex preference get default_list_id\n  \
        lorvex preference set weekly_review_day 1\n  \
        lorvex preference delete weekly_review_day\n"
    )]
    Preference(PreferenceCmd),

    /// List all tags with task counts.
    #[command(after_help = "EXAMPLES:\n  lorvex tags\n")]
    Tags,

    /// Tag operations (tasks, rename).
    #[command(
        subcommand,
        after_help = "EXAMPLES:\n  \
        lorvex tag tasks Work\n  \
        lorvex tag tasks \"Deep Work\"\n  \
        lorvex tag rename OldName NewName\n"
    )]
    Tag(TagCmd),

    /// Recent rows from the `error_logs` table (newest first).
    ///
    /// a strict subset of MCP `get_recent_logs` covering
    /// the single source most useful from a shell pipeline. The full
    /// merged-view tool (which combines error_logs, ai_changelog and
    /// sync_outbox with redaction policy) is tracked separately.
    #[command(after_help = "EXAMPLES:\n  \
        lorvex error-logs\n  \
        lorvex error-logs --source sync -l 50\n")]
    ErrorLogs(ErrorLogsArgs),

    /// Read the assistant-onboarding setup status.
    ///
    /// mirrors MCP `get_setup_status`. Returns the same
    /// readiness booleans (lists_ready, default_list_ready,
    /// working_hours_ready, normal_task_creation_ready,
    /// prerequisites_ready, explicit_setup_completed, setup_completed)
    /// plus list/task counts.
    #[command(after_help = "EXAMPLES:\n  lorvex setup-status\n")]
    SetupStatus,

    /// Mark assistant-onboarding as completed with a free-text summary.
    ///
    /// mirrors MCP `complete_setup`. Writes
    /// `setup_completed=true`, `setup_summary`, and `setup_state` in
    /// one transaction; emits one `ai_changelog` row.
    #[command(after_help = "EXAMPLES:\n  \
        lorvex setup-complete \"Configured inbox + working hours\"\n  \
        lorvex setup-complete \"All prerequisites met\"\n")]
    SetupComplete(SetupCompleteArgs),

    /// Dashboard snapshot rendered to stdout.
    #[command(after_help = "EXAMPLES:\n  lorvex tui\n  lorvex tui --watch\n")]
    Tui(TuiArgs),

    // --- workflow / read-aggregation tools ---
    /// Dashboard snapshot mirroring MCP `get_overview` (default) or
    /// `get_overview_compact` (--compact). Use global `--format json`
    /// to emit the canonical JSON payload directly.
    #[command(after_help = "EXAMPLES:\n  \
        lorvex overview\n  \
        lorvex overview --compact\n")]
    Overview(OverviewArgs),

    /// Bounded all-in-one session snapshot mirroring MCP
    /// `get_session_context`. Composes overview + current focus +
    /// today events + recent changelog + guide + habits.
    #[command(after_help = "EXAMPLES:\n  lorvex session-context\n")]
    SessionContext(SessionContextArgs),

    /// Contextual guidance mirror of MCP `get_guide`. Auto-detects the
    /// topic from app state when --topic is omitted.
    #[command(after_help = "EXAMPLES:\n  \
        lorvex guide\n  \
        lorvex guide --topic getting_started\n")]
    Guide(GuideArgs),

    /// Full merged log view mirroring MCP `get_recent_logs`. Combines
    /// `error_logs` + `ai_changelog` + `sync_outbox` with redaction.
    /// Distinct from the existing `error-logs` slice (which only
    /// reads error_logs).
    #[command(after_help = "EXAMPLES:\n  \
        lorvex recent-logs\n  \
        lorvex recent-logs --level error --level warn --include-details\n")]
    RecentLogs(RecentLogsArgs),

    /// Bounded analytics over the trailing window. Mirrors MCP
    /// `analyze_task_patterns`.
    #[command(after_help = "EXAMPLES:\n  \
        lorvex analyze\n  \
        lorvex analyze --window-days 30 --top-n 10\n")]
    Analyze(AnalyzeArgs),

    /// Compute a display sort order for a list. Mirrors MCP
    /// `reorganize_list` — pure sort op (no row mutation), but logs
    /// to ai_changelog for audit.
    #[command(after_help = "EXAMPLES:\n  \
        lorvex reorganize <list-id> --strategy priority\n  \
        lorvex reorganize <list-id> --strategy manual --task-id <t1> --task-id <t2>\n")]
    Reorganize(ReorganizeArgs),

    /// Per-day completion timeline for a habit. Mirrors MCP
    /// `get_habit_completions`.
    #[command(after_help = "EXAMPLES:\n  \
        lorvex habit-completions <habit-id>\n  \
        lorvex habit-completions <habit-id> --days 60\n")]
    HabitCompletions(HabitCompletionsArgs),

    /// Task checklist operations (add / update / toggle / remove /
    /// reorder). Mirrors MCP `*_task_checklist_item` /
    /// `reorder_task_checklist_items`.
    #[command(
        subcommand,
        after_help = "EXAMPLES:\n  \
        lorvex checklist add <task-id> Step 1 done\n  \
        lorvex checklist toggle <item-id> --completed\n  \
        lorvex checklist remove <item-id>\n  \
        lorvex checklist reorder <task-id> <item-1> <item-2>\n"
    )]
    Checklist(ChecklistCmd),

    /// Structured task writes that don't fit `capture` / `update` —
    /// `create` (full shape with ai_notes/depends_on/recurrence at
    /// create time), `set-recurrence`, `permanent-delete`,
    /// `batch-create`, `batch-update`, `batch-cancel-in-list`.
    #[command(
        subcommand,
        after_help = "EXAMPLES:\n  \
        lorvex task create \"Ship feature\" --list <list-id> --priority 1 --due-date 2026-05-01\n  \
        lorvex task set-recurrence <task-id> --freq weekly --byday MO --byday WE\n  \
        lorvex task permanent-delete <task-id>\n  \
        lorvex task batch-create --tasks-json '[{\"title\":\"A\"},{\"title\":\"B\"}]'\n  \
        lorvex task batch-update --updates-json '[{\"id\":\"<task-id>\",\"priority\":1}]'\n  \
        lorvex task batch-cancel-in-list <list-id> --status open --status someday\n"
    )]
    Task(TaskWriteCmd),

    /// Calendar subscription operations (list / add / remove /
    /// refresh / toggle). Mirrors the Tauri Settings →
    /// Subscriptions surface.
    #[command(
        subcommand,
        after_help = "EXAMPLES:\n  \
        lorvex subscription list\n  \
        lorvex subscription add https://example.com/cal.ics --name Work --color \"#00ff00\"\n  \
        lorvex subscription refresh <id>\n  \
        lorvex subscription refresh --all\n  \
        lorvex subscription toggle <id>\n  \
        lorvex subscription remove <id>\n"
    )]
    Subscription(SubscriptionCmd),

    /// MCP server operations (serve / install).
    #[command(
        subcommand,
        after_help = "EXAMPLES:\n  \
        lorvex mcp serve\n  \
        lorvex mcp install --for all\n"
    )]
    Mcp(McpCmd),

    /// Emit a shell completion script to stdout (issue #2307).
    ///
    /// The script is generated from the clap command tree at runtime,
    /// so it always reflects the CLI's current subcommands and flags.
    /// Pipe the output into your shell's completion load path to
    /// install it — typical locations are shown below. The dispatcher
    /// writes to stdout only and exits 0; no DB is opened.
    #[command(after_help = "EXAMPLES:\n  \
        # zsh\n  \
        lorvex completions zsh > \"${fpath[1]}/_lorvex\"\n  \
        # bash\n  \
        lorvex completions bash > /etc/bash_completion.d/lorvex\n  \
        # fish\n  \
        lorvex completions fish > ~/.config/fish/completions/lorvex.fish\n  \
        # powershell\n  \
        lorvex completions powershell > $PROFILE\n")]
    Completions {
        /// Target shell (zsh, bash, fish, powershell, elvish).
        #[arg(value_enum)]
        shell: Shell,
    },
}
