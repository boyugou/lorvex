use crate::contract::GuideTopic;
use crate::preferences::{APPEARANCE_PROFILES, ASSISTANT_UI_LANGUAGES, THEME_MODES};
use crate::system::guidance_support::{guide_suggested_actions, GuideState};
use serde_json::{json, Value};

pub(crate) const fn guide_topic_to_str(topic: GuideTopic) -> &'static str {
    match topic {
        GuideTopic::Overview => "overview",
        GuideTopic::GettingStarted => "getting_started",
        GuideTopic::TaskManagement => "task_management",
        GuideTopic::CurrentFocus => "current_focus",
        GuideTopic::Lists => "lists",
        GuideTopic::FocusMode => "focus_mode",
        GuideTopic::WeeklyReview => "weekly_review",
        GuideTopic::Preferences => "preferences",
        GuideTopic::DataAndExport => "data_and_export",
    }
}

pub(crate) fn build_guide(topic: GuideTopic, state: &GuideState) -> Value {
    match topic {
        GuideTopic::GettingStarted => json!({
            "summary": "Welcome! Lorvex setup is product state, not user work. First establish the planning prerequisites, then start capturing real tasks into real lists.",
            "steps": [
                "Tell me about your work rhythm and typical availability so I can set working_hours cleanly.",
                "Create or confirm your real lists, then resolve default_list_id so normal quick capture has a real home.",
                "After setup prerequisites are ready, start telling me about tasks, ideas, and deadlines - I will capture them into real lists.",
                "Use complete_setup once setup state is genuinely ready; do not treat setup steps as ordinary tasks.",
            ],
            "tips": [
                "You can dump messy thoughts - I will parse them into structured tasks",
                "Tell me about deadlines naturally: \"meeting with Sarah next Tuesday at 3pm\" - I can create either tasks or calendar events",
                "I can import your existing tasks if you export them to a CSV or JSON file",
            ],
            "available_tools_summary": {
                "task_management": "Task lifecycle, updates, completion, recurrence, and AI notes.",
                "calendar_events": "Create, update, delete, and query calendar events.",
                "lists": "Create, update, inspect, reorder, and delete lists.",
                "current_focus": "Set/get/clear the current focus, propose and save focus schedules.",
                "preferences": "Configure working style, language, dashboard layout, and app UI control.",
                "context": "Get overview/review insights, diagnostics, changelog, logs, export data, and route feedback to GitHub issues.",
                "memory": "Store, retrieve, and delete assistant memory across sessions.",
                "habits": "Create, update, complete, list habits, and get streak/completion stats.",
                "reviews": "Add, get, list, and amend daily reviews with habit tracking.",
                "sync": "Get sync status and inspect pending sync events.",
                "onboarding": "Contextual guidance and next-step recommendations.",
                "import": "Import data from supported export snapshots.",
            }
        }),
        GuideTopic::Overview => json!({
            "summary": "Lorvex is fully set up and active.",
            "current_state": state.to_value(),
            "what_i_can_do": [
                "Create and manage tasks with rich metadata (due dates, planned dates, estimates, importance, tags)",
                "Create and manage fixed-time calendar events (meetings, appointments, travel blocks)",
                "Organize tasks into lists with icons and colors",
                "Set the current focus with AI briefings and propose focus schedules",
                "Priority expresses importance, not urgency. Time pressure should mostly come from due dates, planned dates, overdue state, and focus choices.",
                "Run weekly reviews analyzing progress, stalled lists, and frequently deferred tasks",
                "Remember your preferences, patterns, and context across sessions",
                "Track habits with streaks, completion rates, and daily check-ins",
                "Subscribe to external calendar feeds (.ics URLs) for Google Calendar, Outlook, etc.",
                "Export all your data for backup or migration",
            ],
            "suggested_actions": guide_suggested_actions(state),
        }),
        GuideTopic::TaskManagement => json!({
            "summary": "Tasks are the core unit. Each task has a title, optional body, due date, planned date, duration estimate, importance-first priority, tags, and AI notes.",
            "key_concepts": [
                "Status flow: open -> completed/cancelled/someday (deferral pushes planned_date forward, status stays open)",
                "Tasks are created directly as open - the conversation with the AI is the review layer",
                "Someday is a legitimate state for non-active commitments you do not want in the active workload yet.",
                "Duration estimates materially improve planning. Fill estimated_minutes when you have a confident rough time cost, but leave it blank when you do not.",
                "Priority should answer importance. Urgency should mostly come from due dates, planned dates, overdue state, and focus decisions.",
                "Tags are flexible labels. I use them for categorization across lists.",
                "AI notes are my private annotations - reasoning about why I scheduled something a certain way",
            ],
            "example_prompts": [
                "\"Add a task to buy groceries this weekend, should take about 45 minutes\"",
                "\"I need to finish the quarterly report by Friday, it is a big one - maybe 3 hours\"",
                "\"Someday I want to learn Spanish\"",
                "\"What is my most urgent task right now?\"",
            ],
        }),
        GuideTopic::CurrentFocus => json!({
            "summary": "Every day, I can set your current focus - a curated list of tasks for you to work on today, with an AI briefing explaining my reasoning.",
            "how_it_works": [
                "I analyze your open tasks, due dates, energy patterns, and working hours",
                "I select tasks that fit into your available working hours between calendar events",
                "I write a briefing explaining why these tasks were chosen",
                "The app shows these in the Focus section on your dashboard",
                "Focus Mode lets you work through them one at a time with a timer",
            ],
            "tips": [
                "Ask me to \"plan my day\" or \"what should I focus on today?\"",
                "I can adjust the plan mid-day if priorities change",
                "Tell me \"give me a light day\" if you want fewer tasks",
            ],
        }),
        GuideTopic::Lists => json!({
            "summary": "Lists organize tasks into areas or categories. Each list has a name, optional icon and color.",
            "concepts": [
                "Lists are areas or categories — \"Work\", \"Personal\", \"Side List\", \"Health\"",
                "Normal active tasks should land in a real list. Use default_list_id or explicit list_id so capture has a concrete home.",
                "I can create lists for you based on what you tell me about your life",
                "Stalled lists (no activity in 7+ days) surface in weekly reviews",
            ],
        }),
        GuideTopic::FocusMode => json!({
            "summary": "Focus Mode is a distraction-free floating window for working through your current focus one task at a time.",
            "features": [
                "Shows one task at a time with title, notes area, and elapsed timer",
                "Three actions: Done (complete), Not Today (defer), Next (skip to next task)",
                "Compact task counter shows progress (e.g. 2/5)",
                "Next-up preview shows what is coming after the current task",
                "Resizable window with minimal chrome - can be narrow or wide",
                "Keyboard shortcuts: Cmd+Enter (done), Cmd+Shift+Enter (defer), Cmd+] (next), Esc (exit)",
                "Keyboard shortcut to toggle: Cmd/Ctrl+Shift+F",
            ],
        }),
        GuideTopic::WeeklyReview => json!({
            "summary": "A structured review of your week - what got done, what stalled, what needs attention.",
            "sections": [
                "Completed this week - celebrate progress",
                "Overdue tasks - things that slipped past their deadlines",
                "Stalled lists - lists with no activity in 7+ days",
                "Frequently deferred - tasks deferred 3+ times (maybe they should be dropped or rethought)",
                "Someday items - legitimate non-active commitments that might be ready to promote to active tasks",
            ],
            "tip": "Ask me to \"run a weekly review\" or \"how was my week?\" and I will walk you through it conversationally.",
        }),
        GuideTopic::Preferences => json!({
            "summary": "I manage most configuration through preferences. You do not need to dig through settings menus.",
            "key_preferences": [
                "working_hours - when you are available to work",
                "dashboard_layout - what sections appear on your dashboard and in what order. Value is JSON: {\"sections\":[{\"type\":\"<type>\",\"limit\":<n>},...],\"updated_by\":\"ai\"}. Available section types: ai_briefing (AI daily briefing), focus (current focus tasks from current focus), schedule (time-blocked schedule timeline), overdue_alert (overdue task warning), recently_completed (done tasks), upcoming_week (tasks due in next 7 days), someday_peek (someday/maybe items), habits (daily habit check-in), stats (weekly statistics). Each section accepts an optional limit (integer) to cap displayed items.",
                format!("language - app display language ({})", ASSISTANT_UI_LANGUAGES.join("/")),
                format!("theme - curated appearance modes ({})", THEME_MODES.join("/")),
                format!(
                    "appearance_profile - curated style profile ({})",
                    APPEARANCE_PROFILES.join("/")
                ),
                "weekly_review_day - weekday string for when to prompt for weekly reviews (sunday through saturday)",
                "default_task_language - when set (e.g. 'en', 'zh'), always create task titles and bodies in this language regardless of the user's conversation language",
                "record_raw_input - when set to 'false', do not store the user's raw conversational input in the raw_input field when creating tasks (privacy preference)",
                "quiet_hours_start / quiet_hours_end - HH:MM times to suppress all notifications (e.g. 22:00 to 07:00)",
                "notification_sound_enabled - set to 'false' to silence notification sounds",
                "notification_muted_lists - JSON array of list IDs to exclude from notifications",
                "estimated_minutes - set a per-task rough duration estimate when confidence is reasonably high; this improves scheduling and review quality.",
                "default_list_id - the real default list for quick captures when the user does not specify a list",
                "sidebar_visible_modules - JSON array of module IDs to show in sidebar (e.g. [\"today\",\"upcoming\",\"calendar\"])",
            ],
            "tip": "Just tell me your preferences in natural language. \"I work 10am to 7pm\" or \"I want fewer tasks in my current focus\" - I will configure it.",
        }),
        GuideTopic::DataAndExport => json!({
            "summary": "All your data is stored locally in SQLite. Nothing leaves your machine unless you explicitly export.",
            "details": [
                "Database path is platform-specific (Lorvex/db.sqlite under your system data directory).",
                "macOS: ~/Library/Application Support/Lorvex/db.sqlite",
                "Windows: %APPDATA%\\\\Lorvex\\\\db.sqlite",
                "Linux: ${XDG_DATA_HOME:-~/.local/share}/Lorvex/db.sqlite",
                "Export: I can export everything as a versioned Lorvex ZIP archive for backup or migration",
                "Import: I can import from a previous Lorvex ZIP export",
                "The archive format is versioned for forward compatibility",
            ],
        }),
    }
}
