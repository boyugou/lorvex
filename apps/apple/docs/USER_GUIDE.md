# Lorvex User Guide

## Welcome to Lorvex

Lorvex is an AI-first task manager built for the Apple platform. Rather than
replacing your thinking, it serves as a structured memory that AI clients can
read and write through the Model Context Protocol (MCP). Your tasks, focus
plans, calendar events, habits, and reviews live in Lorvex-managed local
storage; an external AI client such as Claude connects to the Lorvex MCP
host and acts as your intelligent co-pilot — capturing, organizing, and
reviewing work on your behalf. The native SwiftUI app surfaces the same data
for glancing, confirming, and acting when you want to stay hands-on.

---

## Setup

### First Launch

1. Build or install `Lorvex.app` and open it.
2. On first launch the app creates managed local storage so you can start
   working immediately.

### Storage

Lorvex keeps your data in a single managed local SQLite database. Every surface
— the app, widgets, App Intents, notifications, and the MCP helper — uses this
same managed store, and cross-device sync is handled entirely by iCloud
(CloudKit). There is no storage picker or external-file option.

To move your data between installs or keep a backup, use **Settings → Data →
Export** to write a file and **Settings → Data → Import** to bring it back.
Export/import is the supported way to carry your data to another machine — live
SQLite files must not be shared through a sync folder.

### MCP Client Configuration

After building or packaging the app, run the following script to generate an
MCP client config for Claude or any other MCP-capable client:

```bash
python3 script/generate_mcp_client_config.py \
  --app-bundle /Applications/Lorvex.app
```

The script writes a JSON file you can paste into your Claude or Codex MCP
configuration. The bundled helper ships as
`Contents/Helpers/LorvexMCPHost.app`, a minimal app bundle rather than a bare
executable (so the App Sandbox can initialize a container for it); the
config points at its inner binary,
`Contents/Helpers/LorvexMCPHost.app/Contents/MacOS/LorvexMCPHost`, so the AI
client launches it over stdio the same way. The JSON also includes a
`lorvex` metadata block declaring the Apple-only Swift-native MCP host
strategy and the official `modelcontextprotocol/swift-sdk`.

Local packaging via `./script/package_local.sh` also emits
`dist/lorvex-apple-mcp-client.json` automatically.

Every install — packaged or built from source — opens only the single
Lorvex-managed App Group store, so the generated config carries no database
override. A dev/source build may point the MCP host at a fixture database with
`LORVEX_APPLE_DB_PATH` (see `docs/setup/ASSISTANT_MCP_SETUP.md`); this is a
development affordance only and is never part of a shipping config.

### Permissions

Lorvex may request the following permissions on first use:

| Permission | When requested | Purpose |
|---|---|---|
| **Calendar** | Opening the Calendar workspace or exporting events | Read Apple Calendar events; write Lorvex planning blocks back to system calendar |
| **Notifications** | Scheduling a task reminder | Deliver task reminder alerts |

Grant each permission in **System Settings → Privacy & Security** if the
system dialog does not appear. Denying Calendar access does not
block core Lorvex data; it only affects the corresponding EventKit overlay.

---

## Quick Capture

Quick Capture is the fastest way to get a task into Lorvex without interrupting
your current activity.

### Keyboard Shortcut

With Lorvex active, press **⌘N** (or **File → New Task**) to focus the inline
quick-add field at the top of the Today or Tasks list — Lorvex switches to Tasks
first if you are on another workspace. Type a task title and press **Return** to
save it; the field clears and keeps focus so you can add several in a row.

### From the Menu Bar Icon

Click the Lorvex icon in the menu bar. The compact menu shows an inline
quick-add field — type a title and press **Return** to save it to your inbox.

### From Home Screen Shortcuts (iOS/iPadOS)

On iPhone and iPad, long-press the Lorvex icon and choose **Quick Capture** from
the context menu. This opens the capture sheet directly, bypassing the main app
navigation. You can also add the **Capture Task** shortcut from the Shortcuts
app to your Home Screen for single-tap capture.

The Shortcuts app also exposes **Create List**, **Update List**, **Delete List**,
**Create Habit**, **Update Habit**, **Delete Habit**, **Create Event**,
**Update Event**, **Delete Event**, **Complete Task**, **Cancel Task**,
**Reopen Task**, **Defer Task**, **Complete Habit**, **Reset Habit**,
**Daily Review**, **Current Focus**, **Add to Focus**,
**Clear Focus**, **Remove Focus**, **Focus Schedule**, **Propose Schedule**,
**Save Schedule**, **Save Memory**, **Read Memory**, and **Delete Memory**. Use
them from
iPhone, iPad, Mac, or Siri to create, rename, update, or delete empty lists,
create/update/delete habits, create/update/delete Lorvex-owned calendar events,
complete, cancel, reopen, or defer tasks, complete or reset today's habit progress, save a review summary,
read, add to, clear, or remove a task from today's focus plan, inspect or propose a focus schedule, save
the proposed schedule back to Lorvex, write, read, or delete a memory key, or
clear the working context through the same Lorvex-managed storage used by the
native app and MCP tools.

The **Open Lorvex** shortcut can jump directly to Today, Tasks, Lists, Calendar,
Habits, Reviews, or Memory. On iPhone and iPad, destinations
that do not have a dedicated tab route into the closest native mobile workspace.

On Apple Watch, the companion app includes a compact **Capture** section for
adding an inbox task from your wrist. The snapshot-backed watch forwards the new
task to the paired iPhone over WatchConnectivity; capture is read-only only when
no forwarder is wired, as in SwiftUI previews.

---

## Today & Focus

### Daily Routine

The **Today** workspace is your daily dashboard. It shows:

- Tasks due or scheduled for today
- Today's Focus — the AI-curated, reorderable day plan
- An optional time-blocked schedule interleaved with your calendar events
- A summary of completed tasks

Open Today from the sidebar, by pressing **⌘1**, or by tapping the Today tab
on iPhone/iPad.

On iPad, Lorvex supports hardware-keyboard navigation: **⌘R** refreshes,
**⌘N** opens Capture, and **⌘1**-**⌘5** switch the primary tabs (Today, Tasks,
Calendar, Habits, More). **⌘8** opens Lists, **⌘M** Memory, **⌘E** Review, and
**⌘,** Settings. On visionOS the same shortcuts apply, plus **⌘6**, **⌘7**, and
**⌘9** for Tasks, Calendar, and Habits.

### Setting Current Focus

To set a task as your current focus:

- In any task list, right-click a task and choose **Add to Focus**.
- In the Task Detail view, click **Focus**.
- Ask your AI client: "Focus on task X."

Several tasks can share the current focus plan. The plan is an ordered list you
work in any order; reorder it by drag, and mark tasks complete or "in progress"
as you go — there is no timer.

### Focus Schedule

Lorvex can lay your Today's Focus tasks into a time-blocked schedule, interleaved
with your real calendar events. Ask your AI client to "propose a schedule for
today" (or use the **Propose Schedule** shortcut), review the blocks, and save
it. The saved schedule appears in Today, collapsed by default.

### Focus Filter for iOS Focus Modes

Lorvex provides an iOS Focus Filter. In **Settings → Focus**, you can add the
Lorvex filter to any Focus mode (Work, Personal, Do Not Disturb, etc.). The
filter has two controls: a Lorvex focus profile (the built-in **Lorvex Focus**)
and a **Show Non-Focus Tasks** toggle. When that Focus mode is active and the
toggle is off, Lorvex hides tasks that are not in your current focus plan from
its widgets and Apple Watch, narrowing those glanceable surfaces to what you are
focused on. The filter does not change the in-app Today view.

---

## Tasks & Lists

### Habits

Open **Habits** from the sidebar or press ⌘4. The macOS workspace can create,
edit, delete, complete, and reset habits against the shared Lorvex core. Use
the row buttons or context menu to change an existing habit without leaving the
native workspace.

### Lists

Open the **Lists** catalog from the **Navigate** menu or the Command Palette
(⌘K) — it has no sidebar row of its own; the sidebar's list rows scope the Tasks
workspace instead. The macOS workspace can create, edit, and delete empty lists
through the same core list catalog used by MCP and mobile. Drag task rows onto a
list to move them; lists with assigned tasks must be emptied before deletion.

### Creating Tasks

- **Quick Capture:** ⌘N, type, **Return**.
- **Inline quick-add:** Type in the quick-add field at the top of the Today or
  Tasks list and press **Return**. Tasks land in the scoped list (when a list is
  selected), the inbox (all-tasks Tasks), or today's plan (Today).
- **Full details:** ⌘N, **File → New Task**, and the toolbar **+** all focus the
  same inline quick-add — there is no separate new-task sheet. To set notes, due
  date, tags, recurrence, and checklist items, open the task and edit it in Task
  Detail (**⌘⇧I**).
- **Mobile Task Detail:** On iPhone and iPad, open a task to review its
  planned date, tags, dependencies, AI notes, checklist, and reminders. Tap
  **Edit** to update title, notes, priority, estimate, planned
  date, tags, and dependencies; add checklist items inline, swipe checklist
  items to delete them, add reminders with the native date picker, swipe
  reminders to delete them, or tap a checklist item status circle to mark it
  complete.
- **Mobile Task Rows:** Today and Focus rows show compact native metadata for
  priority, estimate, planned date, recurrence, checklist progress, reminders,
  dependencies, and the first tag.
- **Mobile Today summaries:** The iPhone and iPad Today tab shows the day's
  schedule (today's calendar events) and, when you have any, a habits summary —
  it does not list your lists. Tap a habit's progress ring to complete it for
  today or tap a completed one to reset it; swipe a habit row to edit or delete
  it. Creating habits, events, and lists lives on their own tabs, not in Today.
- **Mobile Lists:** On iPhone and iPad, lists live in the **Tasks** tab. The
  Tasks home lists them as rows below the smart collections; tap one to open its
  task list, and swipe a list row to edit its name and description or delete it
  (empty lists only). Tap **New List** (the **+** in the Lists section header) to
  create one. Handoff and system `openList` activities open the same list route.
- **Mobile Habit Creation:** Tap the **+** in the **Habits** tab toolbar to
  create a core-backed daily habit with a cue and target count.
- **Mobile Calendar Creation:** Tap **New Event** in the **Calendar** tab to
  create a canonical Lorvex event; swipe an editable event row to edit or delete
  it. The Today schedule summary is read-only and has no New Event footer.
- **Via AI:** Ask your connected AI client to create a task. The AI calls the
  `create_task` MCP tool and returns the full created task object.

### Moving Between Lists

Drag a task row onto a different list in the sidebar to move it. To reassign
several at once, select multiple tasks and use the **Lists** submenu in the
workspace selection menu — the batch menu that appears in the header while a
selection is active.

### Recurrence

In Task Detail, open the **Recurrence** row and choose a pattern:

- Daily, weekly, monthly, yearly with standard intervals
- Custom day-of-week patterns

The task detail view shows the saved repeat rule and skipped occurrence count.
On iPhone and iPad, Task Detail opens a full recurrence builder — a repeat
toggle, a frequency picker, an interval stepper, and weekday chips (for weekly
repeats) — matching the macOS detail editor.
Advanced recurrence fields such as end-by date or occurrence count remain
available through MCP recurrence tools.

### Tags

Tags are free-form labels you attach to tasks. Create a tag inline while
editing a task. Use tags to filter and organize your task lists. The MCP host
exposes tag management tools so your AI client can tag tasks during capture or
triage.

### Batch Operations

Select multiple tasks by ⌘-clicking rows (⇧-click extends a range). The
workspace selection menu — the batch menu in the header while a selection is
active — also offers **Select All** and **Clear Selection**. With tasks selected:

- **Complete** — marks all selected tasks complete.
- **Defer** — defers all selected tasks to tomorrow.
- **Move to List** — reassigns all selected tasks to a different list.
- **Cancel** — marks all selected tasks cancelled.
- **Reopen** — reopens tasks in the selection that are completed, cancelled, or
  deferred.

On iPhone and iPad, tap **Select** in the Tasks workspace toolbar, then tap task
rows to select them; a bottom action bar offers Complete, Defer, and Reopen.

---

## Calendar & EventKit

### Viewing Calendar Events

The **Calendar** workspace shows a merged timeline of Lorvex planning blocks
and Apple Calendar events. EventKit events appear in a distinct style alongside
your Lorvex tasks so you can see scheduling conflicts at a glance.
Use the row buttons or context menu to edit or delete Lorvex-owned events.
Imported EventKit events are read-only overlays.

Calendar permission is required to display EventKit events. If permission is
denied, Lorvex shows only its own planning blocks with a permission prompt in
the Settings diagnostics panel.

### Importing from System Calendars

In **Settings → Calendar**, choose which Apple Calendar calendars to overlay.
Lorvex reads those calendars through EventKit and merges their events into the
Calendar workspace view. Import failures (permission errors, missing calendars)
are recorded in the import report visible in Settings diagnostics.

### Exporting Lorvex Events to System Calendar (macOS)

Write-back to the system Calendar is a **macOS-only** feature. On macOS, when
you create or update a Lorvex calendar event, Lorvex can write it through
EventKit into a dedicated Lorvex calendar as a write-through copy. This keeps
the rest of your Apple ecosystem (the system Calendar, Siri, and any
calendar-aware apps) aware of your Lorvex schedule without duplicating data
ownership. The Lorvex database remains authoritative; EventKit holds a mirrored
copy.

Enable this in **Settings → Calendar → Two-Way Calendar Sync**.
If the write fails (permission denied, calendar not available), Settings
diagnostics show the export report so you can retry after granting permission.

On iPhone, iPad, and Apple Vision Pro, Lorvex reads the system calendar for
display and planning but does not write to Apple Calendar; calendar events you
create there stay Lorvex-native. Those events still sync across your devices
through iCloud (Lorvex's own CloudKit sync).

### ICS Export

To export Lorvex calendar events as an ICS file:

1. Open **File → Export Calendar…** (macOS) or use the **Export** action in the
   Calendar workspace sheet (iOS).
2. Choose a date range.
3. Save or share the resulting `.ics` file.

The AI client can also trigger ICS export via the `export_calendar_ics` MCP tool.

---

## Reviews & Memory

### Daily Review

The **Reviews** workspace opens your daily review. Lorvex presents:

- Tasks completed today
- Tasks that were due but not completed
- A prompt to write a brief reflection

Complete the review by submitting the reflection text. Daily reviews are stored
in the database and visible in the review history.

On iPhone and iPad, the **Review** tab also provides a native daily review form
for summary, wins, blockers, learnings, mood, and energy. Save the form to update
the same daily review record used by macOS and MCP tools.

### Weekly Review

The weekly review summarizes:

- Completed tasks for the week
- Unfinished tasks carried over
- A space for a weekly reflection

Open the weekly review from the **Reviews** workspace or ask your AI client for
the `get_weekly_brief` tool call.

### Memory

Lorvex keeps a memory store — AI-managed notes, observations, and context
snapshots the assistant remembers about you as a key→value store with last-write
semantics. On macOS, open the **Memory** workspace from the sidebar's Reflect
group or press **⌘6**. You can browse, search, write, and delete entries; edits
are synced across your devices.

On iPhone, Memory is its own row in the **More** tab, separate from Review. On
iPad, it is its own row in the sidebar's Workspaces section. Use it to review
recent context entries or write a compact key/content memory update through the
same core path used by macOS and MCP tools.

## MCP & AI Integration

### How the MCP Host Works

`LorvexMCPHost` is a command-line helper bundled inside the app. Your AI client
(Claude, Codex, or any MCP-capable client) launches it as a subprocess over
stdio. The helper connects to the same `LorvexCoreServicing` boundary as the
app, so all AI writes go through the same data path, audit log, and sync
invariants as in-app mutations.

The host is stateless per invocation: each stdio session is a fresh process.
The Lorvex database is the persistent state.

### Tool Catalog

The MCP host exposes tools across these domains:

| Domain | Example tools |
|---|---|
| **System / Overview** | `get_overview`, `get_setup_status`, `get_session_context`, `get_sync_status` |
| **Tasks** | `create_task`, `update_task`, `get_task`, `list_tasks`, `search_tasks`, `complete_task`, `cancel_task`, `reopen_task`, `defer_task`, `move_task_to_list`, `append_to_task_body`, `get_deferred_tasks` |
| **Batch tasks** | `batch_create_tasks`, `batch_update_tasks`, `batch_defer_tasks`, `batch_complete_tasks`, `batch_reopen_tasks`, `batch_move_tasks` |
| **Focus** | `set_current_focus`, `add_to_current_focus`, `get_current_focus`, `remove_from_current_focus`, `clear_current_focus` |
| **Focus schedule** | `propose_daily_schedule`, `save_focus_schedule`, `get_saved_focus_schedule` |
| **Lists & tags** | `create_list`, `update_list`, `delete_list`, `archive_list`, `unarchive_list`, `get_lists`, `get_list`, `get_list_health_snapshot`, `list_all_tags`, `rename_tag` |
| **Calendar** | `create_calendar_event`, `update_calendar_event`, `delete_calendar_event`, `get_calendar_timeline`, `search_calendar_events`, `batch_create_calendar_events`, `edit_scoped_calendar_event`, `delete_scoped_calendar_event`, `export_calendar_ics`, `add_calendar_event_exception`, `remove_calendar_event_exception`, `link_task_to_event`, `unlink_task_from_event`, `link_task_to_provider_event`, `unlink_task_from_provider_event`, `get_linked_events_for_task`, `get_linked_tasks_for_event` |
| **ICS export** | `export_calendar_ics` |
| **Habits** | `create_habit`, `update_habit`, `delete_habit`, `complete_habit`, `uncomplete_habit`, `batch_complete_habits`, `get_habits`, `get_habit_completions`, `get_habit_stats`, `get_habit_reminder_policies`, `upsert_habit_reminder_policy` |
| **Reviews** | `get_daily_review`, `add_daily_review`, `amend_daily_review`, `get_weekly_brief`, `get_review_history` |
| **Memory** | `read_memory`, `write_memory`, `delete_memory` |
| **Checklists** | `add_task_checklist_item`, `update_task_checklist_item`, `toggle_task_checklist_item`, `reorder_task_checklist_items`, `remove_task_checklist_item` |
| **Recurrence** | `set_task_recurrence`, `remove_task_recurrence`, `add_task_recurrence_exception`, `remove_task_recurrence_exception` |
| **Reminders** | `add_task_reminder`, `set_task_reminders`, `remove_task_reminder`, `get_due_task_reminders`, `get_upcoming_task_reminders` |
| **AI context** | `set_task_ai_notes`, `set_list_ai_notes` |
| **Dependencies** | `get_dependency_graph`, `get_upcoming_tasks` |
| **Data export** | `export_data` |
| **Preferences** | `get_all_preferences`, `get_preference`, `set_preference`, `complete_setup` |
| **Audit / logs** | `get_ai_changelog`, `get_recent_logs` |
| **Guidance** | `get_guide` |

Every write tool returns the complete updated object. The AI always sees the
resulting state, not just a success flag.

### Idempotency Keys

Create and update tools accept an optional `idempotency_key` string. If the
client submits the same key twice (for example, after a network retry), Lorvex
returns the result of the first operation instead of creating a duplicate. Use a
UUID or a deterministic hash of the intended operation as the key. If a helper
stops after committing the mutation but before saving its full response, Lorvex
returns `idempotency_response_unavailable`; inspect current state rather than
retrying the mutation under a new key.

---

## Widgets & Watch

### Home Screen Widget (iOS/iPadOS)

1. Long-press the Home Screen and tap **+**.
2. Search for **Lorvex**.
3. Choose a widget: **Lorvex Focus** (the focus widget — Small, Medium, Large,
   plus Lock Screen accessory families), **Today Tasks** (Small, Medium, Large),
   **Habits** (Small, Medium, and Lock Screen circular), or **Daily Progress**
   (Small, and Lock Screen circular and inline).
4. Tap **Add Widget**.

Widgets refresh from a shared App Group snapshot the main app publishes. If the
App Group entitlement is not configured for your build, widgets show preview
data.

Widget rows and the whole-widget tap area carry `lorvex://` deep links that
open Today or the tapped task detail in the app. On the focus widget, Medium
task rows add a one-tap **Complete** button and Large rows add both **Complete**
and **Defer**. Those are the only interactive controls — a glanceable widget
deliberately omits destructive and focus-membership actions.

### ControlWidget (iOS 18+)

Lorvex provides a Control Widget for the iOS Control Center. It shows the
current focus task and opens Lorvex directly to Today when tapped. Add it from
Control Center itself: swipe down to open it, long-press to enter edit mode, tap
**＋ Add a Control**, and search for **Lorvex Focus**.

### Watch App

The `LorvexWatchApp` companion shows your current focus task and the next queued
focus tasks on Apple Watch. The iPhone projects the bounded focus, habit,
briefing, and aggregate subset the Watch actually consumes into a versioned,
workspace-fenced replica. WatchConnectivity carries that latest-state replica,
and the Watch atomically stores it as `watch_replica_v1.json` in its own App
Group container. The iPhone's fuller `widget_snapshot_v3.json` remains local to
the WidgetKit surfaces; it is not the Watch transport contract.

**Completing, canceling, or deferring a task** from the Watch is forwarded to
iPhone over WatchConnectivity. The Watch persists every command before updating
its UI, keeps it until a checksum- and identity-bound application ACK arrives,
and retries temporary transport or phone failures in FIFO order. The phone
records the terminal receipt in SQLite in the same transaction as the canonical
domain write, then publishes a fresh authoritative replica. Quick capture and
habit completion use the same durable path. A terminal rejection remains visible
on the Watch until dismissed; previews without a forwarder stay read-only.

### Watch Complications

Lorvex ships a focus complication backed by the Watch's atomically stored replica
(shared with the Watch app, not with the iPhone Widget extension). It supports
circular, rectangular, inline, and watchOS corner accessory families. Add it
from the Watch app or directly from a watch-face customization flow.

---

## Sync & Export

### CloudKit (Status)

The local CloudKit export path can project the app snapshot for diagnostics,
and live mode drains the Swift sync outbox into the private CloudKit database.
Core planning entities such as tasks, lists, habits, calendar events, memory,
and focus plans route through the same native inbound sync
engine used by the Swift core tests. Real iCloud writes require a provisioned
CloudKit container and a logged-in iCloud account.

For local testing:

```bash
# Encode CKRecords without network access
LORVEX_CLOUDKIT_EXPORT=record-plan ./script/build_and_run.sh

# Write to the private CloudKit database (provisioned build only)
LORVEX_CLOUDKIT_EXPORT=live ./script/build_and_run.sh
```

Settings diagnostics show the latest export report: mode, record count, source
sequence, and any failure text.

In live mode, recognized CloudKit remote-change pushes trigger a private
record-zone change fetch using the cursor stored with the SQLite traversal. The
native inbound processor commits fetched records and the successor token in one
SQLite transaction.

The Cloud Sync Settings tab also shows readiness for the full sync stack:
outbound record export, private database subscription, remote-change refresh,
inbound record application, and atomic SQLite change-token checkpointing are
ready. The inbound boundary applies decoded CloudKit records through the native
`Apply.applyEnvelope` registry with typed HLC LWW gates, tombstones,
redirect-aware pending inbox draining, and conflict logging. Settings shows the
applied, skipped, deferred, remapped, replayed, and undecodable counts from the
latest remote-change report.

### JSON / CSV / ZIP Export

From **Settings → Data → Export**: choose the categories you want, then pick
**JSON**, **CSV**, or **ZIP** (one JSON file per category).

Human JSON/ZIP task exports include an Apple-native task-state graph for the most
faithful same-app import, alongside portable task JSON. The native graph includes
deletion high-waters and opaque future-field state so deleted task-domain records
do not silently reappear after restore. It never installs CloudKit account
receipts or the source device as this device's runtime identity; a single-file
JSON provenance header may still describe which Apple device produced it. If the
target already contains tasks or the native graph's list/tag roots were not
selected, import safely uses the portable merge instead. CSV is portable only.

Import is non-destructive, not an authoritative iCloud rollback. With Live
iCloud Sync enabled, Lorvex first downloads every visible CloudKit page, proves
the exact current account/generation, resolves deferred inbound work to a fixed
point, and refuses to import while any pending or corrupt remote record remains.
The same sync gate stays held until the import decisions finish. If that proof
cannot be made, nothing is imported and Settings asks you to retry after Cloud
Sync is ready. When sync is off, import deliberately compares only with local
data; enable sync first when current iCloud state must participate in collision
decisions.

The AI client can request portable exports via the `export_data` MCP tool.

### Spotlight Indexing

The Lorvex Mac app indexes tasks in macOS CoreSpotlight automatically. Search
for any task title in macOS Spotlight, and tapping a result opens the task
detail view via a `lorvex://task/<id>` deep link. Lists, habits, calendar
events, and daily reviews are indexed by name (or date) the same way. Only
titles and names are indexed — never notes, checklist text, or other private
free text.

Spotlight re-indexes whenever the app refreshes its snapshot. To force a
re-index, use **Task → Refresh (⌘R)** on macOS.

---

## Keyboard Shortcuts

### Global (macOS)

| Shortcut | Action |
|---|---|
| ⌘N | Quick Capture |
| ⌘K | Command Palette |
| ⌘1 | Today workspace |
| ⌘2 | Calendar workspace |
| ⌘3 | Tasks workspace |
| ⌘4 | Habits workspace |
| ⌘5 | Reviews workspace |
| ⌘6 | Memory workspace |
| ⌘R | Refresh data |
| ⌘F | Search tasks |
| ⌘, | Settings |

The numeric accelerators map to the visible sidebar workspaces (⌘1–⌘6). The day
plan lives inside Today, so there is no separate Focus workspace. The
Eisenhower matrix and the dependency graph are MCP-data-only — the AI can
read and write them, but there is no macOS human view, so they have no
numeric shortcut and are absent from the sidebar, Navigate menu, and Command
Palette (⌘K). Lists has no numeric shortcut either, and no sidebar row of its
own — the sidebar's list rows scope the Tasks workspace. The Lists catalog is
reached from the Navigate menu or the Command Palette (⌘K).

### Task Operations (macOS)

These act on the selected task.

| Shortcut | Action |
|---|---|
| ⌘⇧I | Show task detail |
| ⌘S | Save task edits |
| ⌥⌘F | Add to / remove from Focus |
| ⌘⇧D | Defer to tomorrow |
| ⌘⇧Return | Complete task |
| ⌘⇧O | Reopen task |
| ⌘⌫ | Cancel task |

### Quick-Add Field (macOS)

The inline quick-add sits at the top of the Today and Tasks lists; ⌘N (or
File → New Task) focuses it.

| Shortcut | Action |
|---|---|
| Return | Save the task and keep the field focused for the next one |

On iPhone and iPad, the **+** opens a capture sheet instead: fill in the title
(and optional notes) and tap **Capture**, or tap **Cancel** to dismiss.

---

## Handoff & Spotlight

### Continuing on Another Device

Lorvex advertises Apple Handoff activity from macOS. When the Lorvex Mac app is
open to a task or workspace, and your other Apple devices are signed into the
same iCloud account, a Handoff icon for that view appears on those devices — in
the Dock on another Mac, or the App Switcher on iPhone and iPad. Click or tap it
to open the same view there. The iPhone and iPad app can continue a Handoff
started on a Mac, but it does not advertise its own activity, so Handoff flows
from a Mac to another device, not the reverse.

Handoff uses the `lorvex://` URL scheme to encode the destination workspace and
current task. It does not transfer database content — both devices must have
access to the same database (either local or via CloudKit sync when available).

### Finding Tasks via Spotlight

On **macOS**, press ⌘Space and type any part of a task title. Lorvex results
appear under the Lorvex category. Pressing Return or clicking the result opens
task detail inside the app. Spotlight indexing is a macOS feature; the iPhone
and iPad apps do not index into iOS Search.

Spotlight results carry `lorvex://task/<escaped-id>` links. If the app is not
installed or the database is unavailable, the link cannot resolve.

---

## Troubleshooting

### App won't launch

If `Lorvex.app` quits immediately after opening:

1. Check that the macOS version is 15 or later (Lorvex requires macOS 15+).
2. If you built from source, confirm `swift build` completed without errors.
3. Open Console.app, filter by process name `Lorvex`, and look for crash
   reports or permission errors immediately after the launch timestamp.
4. Try launching from the terminal to see stderr:
   ```bash
   /Applications/Lorvex.app/Contents/MacOS/Lorvex
   ```

### MCP host not found by client

If your AI client reports that the MCP server could not be started or the
`LorvexMCPHost` binary is not found:

1. Confirm the app bundle is built and placed where the config points:
   ```bash
   ls /Applications/Lorvex.app/Contents/Helpers/LorvexMCPHost.app/Contents/MacOS/LorvexMCPHost
   ```
2. Regenerate the MCP client config to pick up the correct path:
   ```bash
   python3 script/generate_mcp_client_config.py \
     --app-bundle /Applications/Lorvex.app
   ```
3. Run the smoke test to confirm the host starts cleanly:
   ```bash
   python3 script/mcp_stdio_smoke.py
   ```
   This source-build command uses a temporary database. Do not point
   `MCP_HOST_BINARY` at an installed sandboxed helper: the corresponding release
   smoke is intentionally destructive and is reserved for the packaging
   workflow with an explicit `LORVEX_ALLOW_DESTRUCTIVE_APP_GROUP_RESET=1`
   acknowledgement.
4. Check that the `command` path in the client config points at the
   `Contents/Helpers/LorvexMCPHost.app/Contents/MacOS/LorvexMCPHost` path
   inside the bundle, not a stale path from a previous build.

### CloudKit shows "No Account"

Lorvex requires an iCloud account signed in on the device to use CloudKit sync.

1. Verify you are signed into iCloud in **System Settings → Apple ID**.
2. Confirm the CloudKit container (`iCloud.com.lorvex.apple`) is provisioned in
   your Apple Developer portal and the app is built with the CloudKit entitlements
   variant (`LorvexAppleCloudKit.entitlements`; Mac App Store builds use
   `LorvexAppleCloudKitAppStore.entitlements`). See `docs/DISTRIBUTION.md §8`.
3. If the app shows "No Account" even with an active iCloud session, the build
   may be using the basic entitlements file (without iCloud keys). Check
   **Settings → Diagnostics** for the CloudKit error detail.
4. For local development, set `LORVEX_CLOUDKIT_EXPORT=record-plan` to test the
   export code path without a network connection.

### EventKit permission denied

If Lorvex cannot read calendar events after you granted
permission:

1. Open **System Settings → Privacy & Security → Calendars** (macOS) or
   **Settings → Privacy → Calendars** (iOS) and confirm Lorvex has full access.
2. If the permission entry is missing, delete the app and reinstall — the system
   permission prompt reappears on first access.
3. After granting permission, use **Task → Refresh (⌘R)** (macOS) or pull to
   refresh (iOS) to trigger a new EventKit read. The Settings diagnostics panel
   shows the latest import/export report with any error detail.
4. If `EKAuthorizationStatus.denied` is logged, the only recovery path is
   granting access in System Settings; the app cannot re-prompt once denied.

### watchOS complication shows stale data

The complication reads a snapshot file from the shared App Group container. If
the data is stale:

1. Open the Lorvex app on iPhone or Mac and let it refresh (pull to refresh or
   use **Task → Refresh (⌘R)**). The app writes a fresh snapshot to the shared
   container on every refresh.
2. On the watch, force-quit the Lorvex app and reopen it; this triggers a fresh
   read from the container.
3. If the complication is still stale, check that the App Group entitlement
   (`group.com.lorvex.apple`) is configured in your build and that both the iOS
   app and the watch app share the same App Group ID. The current default build
   uses a no-op publisher when the App Group is not set up; complications in
   that configuration always show placeholder data.
4. Background complication refresh requires a WatchConnectivity session between
   the watch and phone. The phone forwards snapshots to the watch over WCSession
   and the watch forwards its mutations back; complication timelines reload from
   the pushed snapshots.
