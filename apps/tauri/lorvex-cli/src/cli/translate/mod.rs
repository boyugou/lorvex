//! Translation from the clap parse tree into the two-level
//! [`super::Command`] dispatch enum. The dispatch fn lives here; each
//! per-domain submodule owns the matching `translate_*` helper.

use super::args::ClapCommand;
use super::command::{Command, HabitsCommand, ListsCommand, OutputFormat, TagsCommand};

mod calendar;
mod capture;
mod checklist;
mod dependency;
mod focus;
mod free_text;
mod habit;
mod lifecycle;
mod list;
mod memory;
mod preference;
mod recurrence;
mod reminder;
mod review;
mod subscription;
mod sync;
mod system;
mod tag;
mod task_write;
mod tasks;
mod trash;
mod update;
mod workflow;

pub(super) fn translate(cmd: ClapCommand) -> Command {
    match cmd {
        // ── system / setup / diagnostics ───────────────
        ClapCommand::Setup { install_mcp_for } => system::translate_setup(install_mcp_for),
        ClapCommand::Doctor => system::translate_doctor(),
        ClapCommand::Status => system::translate_status(),
        ClapCommand::Changelog(args) => system::translate_changelog(args),
        ClapCommand::Export(args) => system::translate_export(args),
        ClapCommand::Import(args) => system::translate_import(args),
        ClapCommand::SetupStatus => system::translate_setup_status(),
        ClapCommand::SetupComplete(args) => system::translate_setup_complete(args),
        ClapCommand::Tui(args) => system::translate_tui(&args),
        ClapCommand::Mcp(mcp) => system::translate_mcp(&mcp),
        ClapCommand::Completions { shell } => system::translate_completions(shell),
        ClapCommand::ErrorLogs(args) => system::translate_error_logs(args),

        // ── sync ───────────────────────────────────────
        ClapCommand::Sync(sync) => sync::translate_sync(&sync),

        // ── task queries (read side) ───────────────────
        ClapCommand::Tasks(args) => tasks::translate_tasks(args),
        ClapCommand::DependencyGraph(args) => dependency::translate_dependency_graph(args),
        ClapCommand::Search(args) => tasks::translate_search(args),
        ClapCommand::Show(args) => tasks::translate_show(args),
        ClapCommand::Today(args) => tasks::translate_today(&args),
        ClapCommand::Overdue(args) => tasks::translate_overdue(&args),
        ClapCommand::Upcoming(args) => tasks::translate_upcoming(&args),
        ClapCommand::Deferred(args) => tasks::translate_deferred(args),
        ClapCommand::Move(args) => tasks::translate_move(args),

        // ── task mutations ─────────────────────────────
        ClapCommand::Capture(args) => capture::translate_capture(args),
        ClapCommand::Update(args) => update::translate_update(args),
        ClapCommand::AppendBody(args) => free_text::translate_append_body(args),
        ClapCommand::AddAiNotes(args) => free_text::translate_add_ai_notes(args),
        ClapCommand::RecurrenceException(rex) => recurrence::translate_recurrence_exception(rex),
        ClapCommand::Complete(args) => lifecycle::translate_complete(args),
        ClapCommand::Reopen(args) => lifecycle::translate_reopen(args),
        ClapCommand::Cancel(args) => lifecycle::translate_cancel(args),
        ClapCommand::Defer(args) => lifecycle::translate_defer(args),
        ClapCommand::Trash(trash) => trash::translate_trash(trash),
        ClapCommand::Checklist(checklist_cmd) => checklist::translate_checklist(checklist_cmd),
        ClapCommand::Task(task_cmd) => task_write::translate_task(task_cmd),

        // ── lists / habits / tags index pages ──────────
        // Tiny default-list arms inline here; the multi-arm
        // sub-commands (`lorvex list <verb>`, `lorvex habit <verb>`,
        // `lorvex tag <verb>`) route through their per-domain helpers.
        ClapCommand::Lists => Command::Lists(ListsCommand::List {
            format: OutputFormat::default(),
        }),
        ClapCommand::List(list_cmd) => list::translate_list(list_cmd),
        ClapCommand::Habits => Command::Habits(HabitsCommand::List {
            format: OutputFormat::default(),
        }),
        ClapCommand::Habit(habit) => habit::translate_habit(habit),
        ClapCommand::Tags => Command::Tags(TagsCommand::List {
            format: OutputFormat::default(),
        }),
        ClapCommand::Tag(tag) => tag::translate_tag(tag),

        // ── domain submodules ──────────────────────────
        ClapCommand::Reminder(reminder) => reminder::translate_reminder(reminder),
        ClapCommand::Focus(focus_cmd) => focus::translate_focus(focus_cmd),
        ClapCommand::Review(review_cmd) => review::translate_review(review_cmd),
        ClapCommand::Calendar(cal) => calendar::translate_calendar(cal),
        ClapCommand::Memory(mem) => memory::translate_memory(mem),
        ClapCommand::Preference(preference) => preference::translate_preference(preference),

        // ── workflow / read-aggregation mirrors ────────
        ClapCommand::Overview(args) => workflow::translate_overview(&args),
        ClapCommand::SessionContext(args) => workflow::translate_session_context(&args),
        ClapCommand::Guide(args) => workflow::translate_guide(&args),
        ClapCommand::RecentLogs(args) => workflow::translate_recent_logs(args),
        ClapCommand::Analyze(args) => workflow::translate_analyze(&args),
        ClapCommand::Reorganize(args) => workflow::translate_reorganize(args),
        ClapCommand::HabitCompletions(args) => workflow::translate_habit_completions(args),

        // ── calendar subscriptions ─────────────────────
        ClapCommand::Subscription(sub) => subscription::translate_subscription(sub),
    }
}
