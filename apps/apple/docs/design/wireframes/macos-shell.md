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

```
┌───────────────────┬──────────────────────────────────┬─────────────────────────┐
│ SIDEBAR (column)  │ WORKSPACE (detail column)        │ INSPECTOR (trailing)    │
│ NavigationSplitVw │   WorkspaceView fills the area    │ .inspector — present     │
│   sidebar         │                                  │ only while a task OR a   │
│                   │  switch store.selection          │ habit is selected        │
│ ── Plan ──        │   .today  → TodayView            │  TaskDetailView          │
│  ☀ Today          │   .calendar → CalendarWksp       │    or HabitDetailInspector│
│  ▦ Calendar       │   .tasks  → TasksView            │                          │
│  ✓ Tasks          │   .lists  → ListsWksp            │  Closes when the subject │
│ ── Lists ──       │   .habits → HabitsWksp           │  is deselected (the      │
│  🗂 <list rows>    │   .reviews → ReviewsWksp         │  standard inspector       │
│ ── Reflect ──     │                                  │  control clears it).     │
│  ↻ Habits         │                                  │                          │
│  ☑ Reviews        │  (.eisenhower/.dependencies/     │  The window's minimum    │
│                   │   .memory have no Mac surface →  │  width grows while the   │
│                   │   fall back to TodayView)        │  inspector is open.      │
│                    │                                  │                          │
│                   │   The chosen view fills the full │                          │
│ ───────────────    │   width; the inspector shares it │                          │
│                   │   only while a subject is open.   │                          │
│  ⚙ Settings       │                                  │                          │
└───────────────────┴──────────────────────────────────┴─────────────────────────┘
```

The window titlebar shows the section name (each workspace's `.navigationTitle`);
its duplicate inline title is suppressed (`.toolbar(removing: .title)` on macOS
15+) so the large in-content header is the single visible title.

## Regions

| Region | What it renders | Data source | View file |
|---|---|---|---|
| Split container | Two-column `NavigationSplitView`; detail = inspector, not a third column | `store.selectedTaskID` / `store.selectedHabitID` (inspector presentation) | `Views/ContentView.swift` |
| Sidebar list | `List(selection:)` styled `.sidebar` | `$store.selection` (via `SidebarRowSelection`) | `Views/SidebarView.swift` |
| Sidebar groups | **Plan** (Today, Calendar, Tasks) and **Reflect** (Habits, Reviews); Lists render dynamically; Settings is a bottom utility row | `SidebarSelection.sidebarGroups` (`Support/SidebarNavigation.swift`) | `Views/SidebarView.swift` |
| Workspace (main) column | Workspace view chosen by selection, filling the full width | `store.selection` (`switch`) | `Views/WorkspaceView.swift` |
| Inspector | `TaskDetailView` while a task is selected, else `HabitDetailInspector` while a habit is | `store.selectedTaskID` / `store.selectedHabitID` | `Views/ContentView.swift`; `Views/TaskDetailView.swift`; `Views/HabitDetailInspector.swift` |
| Command palette sheet | `CommandPaletteView` (⌘K overlay) | `$store.showCommandPalette` | `Views/CommandPaletteView.swift` |
| Setup wizard sheet | `SetupWizardSheet` on first run | `showSetupWizard` (gated on `settings.setupCompleted`) | `Views/ContentView.swift` |

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
- Lists can also open in a detached window from the Lists sidebar/catalog menu.

## Notes for improvement (analysis — NOT yet implemented)
- Sidebar rows are intentionally unbadged because no honest count is available
  there.
- The workspace column has no width persistence; proportions are left to
  `NavigationSplitView` defaults plus `lorvexMinimumWindowSize(.main)`, with the
  inspector using `inspectorColumnWidth(min:ideal:max:)`.
