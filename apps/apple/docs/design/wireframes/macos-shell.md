# macOS Shell — As-Built Wireframe

> ASCII transcription of the macOS shell layout, derived from the SwiftUI source.
> Current-state reference, not a redesign. Line numbers are intentionally omitted
> (they drift); cite files and types instead.

**Entry view:** `ContentView` (`Sources/LorvexApple/Views/ContentView.swift`), a
two-column `NavigationSplitView`.
**Backing state:** `AppStore.selection: SidebarSelection`,
`AppStore.selectedTaskID`, `AppStore.selectedHabitID`,
`AppStore.showCommandPalette`.

## Layout (as built)

Two columns — sidebar + workspace. The workspace owns the full main area; a
trailing `.inspector` is shown only while a task **or** a habit is selected (the
two are mutually exclusive). There is no global toolbar search and no
customizable toolbar.

The sidebar opens with its five fixed destinations in one section without a
header: `SidebarSelection.sidebarGroups` holds a single group
(`SidebarGroupKind.plan`), and `SidebarView.planSection` renders it as a
`Section` with no header. A "Lists" section (a header row with its
own ＋ to create one) and an "Archived" section (present only once at least
one list has been archived) follow. Memory and Settings are not part of the
scrolling list at all: `SidebarView.utilitiesFooter` pins them below a
divider at the foot of the column, so they never scroll away.

```
┌───────────────────┬──────────────────────────────────┬─────────────────────────┐
│ SIDEBAR (column)  │ WORKSPACE (detail column)        │ INSPECTOR (trailing)    │
│ NavigationSplitVw │   WorkspaceView fills the area    │ .inspector — present     │
│   sidebar         │                                  │ only while a task OR a   │
│                   │  switch store.selection          │ habit is selected        │
│  ☀ Today          │   .today    → TodayView          │                          │
│  ▦ Plan           │   .tasks    → TasksView          │  TaskDetailView          │
│  ✓ All Tasks      │   .lists    → ListsWorkspaceView │    or HabitDetailInspector│
│  ☑ Review         │   .calendar → CalendarWorkspaceV.│                          │
│  ↻ Habits         │   .habits   → HabitsWorkspaceView│  Closes when the subject │
│ ── Lists ──   (+) │   .reviews  → ReviewsWorkspaceV. │  is deselected (the      │
│  🗂 <list rows>    │   .memory   → MemoryWorkspaceView│  standard inspector       │
│ ── Archived ──    │                                  │  control clears it).     │
│  🗂 <archived>     │  Exhaustive switch, one case per │                          │
│ ─────────────────  │  destination.                    │  The window's minimum    │
│  🧠 Memory         │                                  │  width grows while the   │
│  ⚙ Settings       │                                  │  inspector is open.      │
│                   │  The chosen view fills the full  │                          │
│                   │  width; the inspector shares it  │                          │
│                   │  only while a subject is open.   │                          │
└───────────────────┴──────────────────────────────────┴─────────────────────────┘
```

The `.calendar` destination's row reads "Plan" and the `.tasks` row reads
"All Tasks" (`SidebarSelection.macOSLocalizedTitle`); the enum cases and
routes are named `calendar` and `tasks`.

The main window hides its title-bar text (`.windowStyle(.hiddenTitleBar)` in
`App/LorvexPrimaryScenes.swift`): each workspace names itself with a large
in-content title, several through the shared `WorkspacePlanHeaderChrome`, and
puts its navigation and actions in the unified toolbar through `.toolbar`. A
workspace's `.navigationTitle` still sets the window's title, which the title
bar does not show. A detached single-list window (`DetachedListWindow.swift`)
keeps the standard window style, so its `ListDetailPane` removes the title
text with `.toolbar(removing: .title)`; the list's name appears once, in the
pane's own header.

## Regions

| Region | What it renders | Data source | View file |
|---|---|---|---|
| Split container | Two-column `NavigationSplitView`; detail = inspector, not a third column | `store.selectedTaskID` / `store.selectedHabitID` (inspector presentation) | `Views/ContentView.swift` |
| Sidebar list | `List(selection:)` styled `.sidebar`; scrolling content only — the footer below is pinned outside it | `$store.selection` (via `SidebarRowSelection`) | `Views/SidebarView.swift` |
| Sidebar destinations | One section without a header — Today, Plan, All Tasks, Review, Habits, in that order | `SidebarSelection.sidebarGroups` (`Support/SidebarNavigation.swift`) | `Views/SidebarView.swift` |
| Lists section | Every user list, a header ＋ to create one, each badged with its open-task count while that count is above zero; per-row context menu (Edit, Open in New Window, Move Up/Down, Archive, Delete) | `store.orderedLists` | `Views/SidebarListSection.swift` |
| Archived section | Archived lists, muted tint; shown only once `store.orderedArchivedLists` is non-empty; per-row context menu (Unarchive, Open in New Window, Delete) | `store.orderedArchivedLists` | `Views/SidebarListSection.swift` |
| Sidebar footer | Memory and Settings, pinned below a divider so they never scroll with the list above; Memory is excluded from `sidebarGroups` on purpose (it is the assistant's context, not a daily workspace) | `store.selection == .memory`; `SettingsLink` | `Views/SidebarView.swift` (`utilitiesFooter`) |
| Workspace (main) column | Workspace view chosen by selection, filling the full width; the switch is exhaustive over all seven `SidebarSelection` cases | `store.selection` (`switch`) | `Views/WorkspaceView.swift` |
| Inspector | `TaskDetailView` while a task is selected, else `HabitDetailInspector` while a habit is | `store.selectedTaskID` / `store.selectedHabitID` | `Views/ContentView.swift`; `Views/TaskDetailView.swift`; `Views/HabitDetailInspector.swift` |
| Command palette sheet | `CommandPaletteView` (⌘K overlay) | `$store.showCommandPalette` | `Views/CommandPaletteView.swift` |
| Setup wizard sheet | `SetupWizardSheet` on first run | `showSetupWizard` (gated on `settings.setupCompleted`) | `Onboarding/SetupWizardSheet.swift` |

## Interaction (as built)
- Click/arrow-select a sidebar row → sets `store.selection`, swapping the workspace.
- Per-destination ⌘ accelerators jump to a workspace via the Navigate menu
  (`Support/SidebarNavigation.swift`; `App/LorvexAppCommands.swift`).
- ⌘K → toggles `store.showCommandPalette`.
- Selecting a task (incl. a Calendar grid tap via `selectTaskFromList`) presents
  the task inspector; selecting a habit card presents the habit inspector. The
  two are mutually exclusive (enforced in `AppStore`'s selection setters), and
  navigating to a workspace that carries no selection clears it.
- "Pin as Sticky" (task detail header or task right-click menu) opens a floating,
  always-on-top sticky note window for the task (`Views/StickyTaskWindow.swift`).
- A list row's context menu offers Edit, Open in New Window (a detached window
  hosting `ListDetailPane`), Move Up/Down, Archive, and Delete. Delete always
  asks first: an empty list is deleted outright, while a list that still holds
  tasks cannot be, so the dialog offers Archive instead, which retires the list
  and keeps its tasks. Dragging a task onto a list row moves it there, and
  dragging a list row itself reorders the Lists section. An archived list's
  row keeps Open in New Window and Delete, trading Edit/Archive for Unarchive;
  its Delete dialog, for a list that still holds tasks, explains that the list
  must be unarchived and emptied first and offers Unarchive.

## Notes for improvement (analysis — NOT yet implemented)
- The five fixed destination rows (Today, Plan, All Tasks, Review, Habits) are
  intentionally unbadged: a destination has no honest count, and a total
  would only restate the list the destination opens. Only an active list's
  row shows a number, its open-task count, and only while that count is above
  zero; archived lists show none.
- The workspace column has no width persistence; proportions are left to
  `NavigationSplitView` defaults plus `lorvexMinimumWindowSize(.main)`, with the
  inspector using `inspectorColumnWidth(min:ideal:max:)`.
