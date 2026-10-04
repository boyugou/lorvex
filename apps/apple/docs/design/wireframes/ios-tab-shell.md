# iPhone Tab Shell, Today, and Tasks Home — As-Built Wireframe

> ASCII transcription of the iPhone (compact size-class) shell, the Today
> surface, and the Tasks tab home, derived from the SwiftUI source.
> Current-state reference, not a redesign. Line numbers are intentionally
> omitted (they drift); cite files and types instead.

**Entry view:** `LorvexMobileStoreRootView` (`Sources/LorvexMobile/LorvexMobileStoreRootView.swift`), `tabBarBody`.
**Size class:** the same `tabBarBody` renders at every size class, on iPhone
and iPad alike. Wide layouts live inside the tabs: at regular width Today sets
its task list and a schedule pane side by side (`MobileStoreTodayView.content`),
and the Tasks, Habits, and Memory workspaces set a list beside its detail
(`MobileAdaptiveListDetail`) once they are wider than 700pt.
**Backing state:** `MobileStore.selectedTab`; one typed route path per tab
(`routePath` for Today, `tasksRoutePath`, `calendarRoutePath`,
`reviewRoutePath`); `snapshot` (Today), `lists`, `habits`,
`calendarTimeline`, `todaySchedule` / `proposedDayTimes`,
`isPresentingCapture`.

## Shell (as built)

Four tabs sit in the bar — Today, Calendar, Tasks, and Review — beside the round
＋ that raises Capture. Each wraps its root view in its own `NavigationStack`,
bound to that tab's route path, and resolves `MobileRoute` values through
`MobileStoreRouteView`. `MobileTab` has exactly these four cases, and the
`TabView` declares no hidden tab: iOS 27 aborts when a `TabView` selects a
tab marked `.hidden(true)`. Deep links, Handoff, shortcuts, and notifications
land through `MobileNavigationTarget` (a tab plus the screens to push on its
stack), so a habit link opens `[.workspace(.habits), .habit(id)]` on the
Tasks stack.
Capture is a sheet raised by the round ＋, not a tab of its own. Habits and
Memory are `MobileRoute.workspace(...)` pushes from rows on the Tasks home,
and Settings is the same kind of push from the gear in Today's toolbar.
Today's Habits section header also pushes `.workspace(.habits)`, onto Today's
own stack, so the catalog opens with a back button to the day.
`MobileStore.openWorkspaceDestination`
pushes the same routes for keyboard mnemonics and `lorvex://dest/...` debug
links, so on iPhone `lorvex://dest/lists` lands on the Tasks home, where lists
live.

```
┌────────────────────────────────────────────────────┐
│  [☀ Today] [▦ Calendar] [✓ Tasks] [☑ Review] (+)    │ ← TabView, MobileTab
└────────────────────────────────────────────────────┘
```

| Tab | Root view | Route path | What it shows |
|---|---|---|---|
| Today | `MobileStoreTodayView` | `routePath` | The day: header + briefing, a schedule strip that opens the schedule sheet, the task list, Habits, and Done (below) |
| Calendar | `MobileStoreCalendarView` | `calendarRoutePath` | One time grid (`MobileCalendarDayView`) showing a day (Day) or seven days (Week), segmented in that view's toolbar, under a month row with a fixed-slot Today button; event search. The case is `MobileTab.calendar` |
| Tasks | `MobileStoreTasksHomeView` | `tasksRoutePath` | Search, 2×2 smart-collection grid, Lists, Completed / Cancelled, then Habits and Memory rows (below) |
| Review | `MobileStoreReviewView` | `reviewRoutePath` | Day / Week picker; daily review form plus day evidence, or the weekly review plus this week's digest |

The Habits catalog (`MobileStoreHabitsView`: searchable, with Select and ＋ in
the toolbar) opens as `.workspace(.habits)` on the Tasks stack or on Today's.

Two sheets belong to the shell itself: `MobileSetupWizard` on first run
(full-height, not dismissible; every page is an icon badge and a title over a
few short points, with its buttons pinned at the bottom; its pages are
Welcome, iCloud Sync — Turn On or Not Now, since sync is off until someone
turns it on — Notifications — Allow Notifications or Not Now — and Ready)
and `MobileStoreCaptureSheet`, raised by `store.isPresentingCapture` from any
tab's ＋.

## Today (as built)

```
┌──────────────────────────────────────────┐
│                                     (⚙)   │ ← toolbar: Settings only; the principal
│                                            │   slot is blank, so no "Today" title
│                                            │   shows; Capture is the tab bar's ＋
│ Friday, September 18                      │ ← date line, MobileTodayCalmCopy.dateLine
│ 7 tasks left · about 3 hr of work ·       │ ← facts line, LorvexFactsLine(
│ 2 meetings                                │   MobileTodayCalmCopy.facts(page.facts))
│ ✨ The intro comes first, it blocks       │ ← briefing card, only when the day has one;
│    Friday's submission…      (Show more)  │   folds past four lines at the width
├──────────────────────────────────────────┤
│ Schedule ›                                │ ← stripRow, tap opens the schedule sheet;
│  ▬▬▬▬░░░░▬▬░░░░░░░░░░░░░░░░░░░░░░░░░░     │   shown whenever the day holds tasks
├──────────────────────────────────────────┤
│ About 6 hr of work, 4 hr free             │ ← overbookedWell, only when the day holds
│ Moving "<task>" to tomorrow frees         │   more estimated work than free working
│ about 2 hr.         [Move to Tomorrow]    │   time; names the least-urgent movable
├──────────────────────────────────────────┤   tasks, or, when none can move on its
│  ● <started task>  Until 3:00 PM          │   own, points at deferring or the
│  ○ <task>  overdue · estimate · tags      │   assistant, with no button
│  ○ <task>  9:00–9:30 AM                   │ ← taskSection, page.items: started tasks
│  — or — sun arc + "No Open Tasks"         │   first, then priority and due date, no
│                                            │   section headers or row chevrons
├──────────────────────────────────────────┤   (emptyDaySection when the task list and
│ Habits ›                                  │   today's done tasks are both empty)
│   ◯       ◯       ◯                       │ ← habitsSection: a horizontally scrolling
│  name    name    name                     │   strip, each habit a ring over its name;
├──────────────────────────────────────────┤   one list row per habit at accessibility sizes
│ Done  3                                ›  │ ← doneSection, folded by default; the
└──────────────────────────────────────────┘   count shows beside the title while folded
```

"Habits" and "Done" are List section headers set in
their natural case (`.textCase(nil)`) rather than the uppercase a plain
section header gets. The chevron right after "Habits" is a static
`chevron.right`, as is the one after "Schedule": each marks a label that opens
a screen, the Habits workspace or the schedule sheet. Done ends in a
`MobileFoldChevron`, which points right while the section is folded and down
while it is open; tapping the header folds or unfolds the section in place.

The first load shows `MobileInitialWorkspaceSkeleton` over the list while
`store.isLoading` and the snapshot is still empty; later refreshes keep content
on screen and use pull-to-refresh.

### Regions

| Region | What it renders | Data source | View |
|---|---|---|---|
| Toolbar | The gear pushes `MobileRoute.workspace(.settings)` onto Today's stack, at every size class. The principal slot holds a blank, accessibility-hidden label, so no title sits above the date line; the "Today" navigation title names the back button once another screen is pushed. Capture is the tab bar's round ＋ on every tab | `store.routePath` | `MobileTodayPageChrome` |
| Header | The date line, the facts line built by `MobileTodayCalmCopy.facts(_:workIsStated:)` (tasks left, then "about N of work" and "N meetings" when either applies, or one sentence on an empty or all-done day; the estimate is left out while the overbooked well below states it), and, when the day has one, the assistant's briefing card (a briefing longer than four lines at the page's width and text size opens on four with a Show more/less toggle; a shorter one has no toggle) | `store.snapshot.today`, `page.facts` | `MobileTodayPage.header` |
| Schedule strip | The day drawn to scale (calendar events and timed tasks); tapping it opens the schedule sheet. Shown whenever the day holds tasks, even before anything is timed | `store.todayStripSegments`, `store.todayStripRange` | `MobileTodayPage.stripRow` |
| Overbooked well | "About X of work, Y free" (for example "About 6 hr of work, 4 hr free"), or "About X of work and no free time left", with a Move to Tomorrow action whose message names the least-urgent movable tasks by title ("Moving “X” to tomorrow frees about Y."). With no movable task it shows the same title and "Defer what can wait, or ask your assistant to plan the day." without the button. Present only when the day holds more estimated work than free working time | `page.overbooked` | `LorvexDecisionWell` |
| Task list | Every unfinished task on the day, started tasks first, then by priority and due date, no section headers, and no disclosure chevron at a row's end (`MobileTaskRow` hides it); a row shows a Started badge, an overdue due date in red, or a timed task's time | `page.items` (`LorvexCalmToday`) | `MobileActionTaskRow` |
| Empty state | A sun arc plus a bounded "No Open Tasks" capture invitation, with no button of its own (the tab bar's ＋ captures), shown only when both the task list and today's done tasks are empty | `page`, `store.doneTodayTasks` | `MobileStoreTaskEmptyState` |
| Habits | A horizontally scrolling row of active habits, each a ring over its name. At accessibility text sizes each habit becomes its own list row (ring, then the full name) instead of a strip column. The "Habits" header pushes the Habits workspace onto Today's own stack. Omitted entirely when there are no habits | `store.habits?.habits` | `MobileTodayPage.habitsSection`, `habitStrip`, `habitRing`, `habitName` |
| Done | What is already done today, newest first, behind a folding header collapsed by default (`@AppStorage("today.done.collapsed")`); the header reads "Done", with the number of done tasks beside it while folded; a row's check reopens the task | `store.doneTodayTasks` | `MobileTodayDoneRow` |

## Tasks home (as built)

```
┌──────────────────────────────────────────┐
│ Tasks                                     │ ← Capture is the tab bar's round ＋
│ [🔍 Search tasks]                         │ ← .searchable; a query swaps the whole
│                                           │   body for the search results list
│ ┌────────────┐ ┌────────────┐             │
│ │ ▣ All    6 │ │ ▣ Sched. 3 │             │ ← LazyVGrid of MobileTaskCollectionCard,
│ └────────────┘ └────────────┘             │   MobileTaskSmartCollection.grid; counts from
│ ┌────────────┐ ┌────────────┐             │   reloadSmartCounts(); tap pushes
│ │ ▣ Prio.  2 │ │ ▣ Someday 1│             │   MobileRoute.tasksScope
│ └────────────┘ └────────────┘             │
├──────────────────────────────────────────┤
│ LISTS                                (+)  │ ← header ＋ presents MobileStoreCreateListSheet
│  ▣ <list>  description          count ›   │   MobileListCatalogRow → .tasksScope(.list(id))
│  — or — "No Lists" row pointing at ＋      │   MobileEmptyState
│  ✓ Completed                    count ›   │   .tasksScope(.completed)
│  ✕ Cancelled                    count ›   │   .tasksScope(.cancelled)
├──────────────────────────────────────────┤
│  ↻ Habits ›                               │ ← MobileNavigationRow → .workspace(.habits)
│  🧠 Memory ›                               │ ← MobileNavigationRow → .workspace(.memory)
└──────────────────────────────────────────┘
```

Habits and Memory have no place in the tab bar, so they open from these two
rows at the foot of the Tasks home, below Lists.

A count at a row's trailing edge draws nothing at zero: a list row shows its
open-task count only while the list has open tasks, as the Mac sidebar badges
a list, and the Completed and Cancelled rows show theirs only once they hold a
task. A store with no task in any status replaces the grid with a first-task
invitation (`MobileEmptyState`, "No Tasks Yet", pointing at ＋ and at the
assistant), since four cards would each count zero. The grid shows until the
counts load, so a store with tasks never shifts; the extra query that tells an
empty store apart (`holdsAnyTask`) runs only when every count is zero.

Every drill-in is `MobileStoreTasksView` for one `MobileTasksScope` (a smart
collection, a status, or a list), which queries the core task corpus with its
own search, paging, and batch selection. A list's drill-in is that list's only
screen: deep links, Handoff, and a newly created list push the same
`.tasksScope(.list(id))`, and `MobileListScopeChrome` adds the list's
description as the navigation subtitle and a ⋯ List Actions menu (Edit List;
Delete List, absent for the Inbox and disabled with its reason while the list
holds tasks). The search results list on the home shows
`MobileEmptyState.search(text:)` when nothing matches.

## Sheets

| Sheet | Raised by | Confirm |
|---|---|---|
| `MobileStoreCaptureSheet` | the tab bar's round ＋ (every tab), ⌘N | Title and Notes fields; Cancel / Add in the navigation bar, Add prominent and disabled until the title has text |
| `MobileStoreCreateListSheet`, `MobileStoreEditListSheet` | Lists header ＋; list row leading swipe Edit; a list screen's ⋯ Edit List | Create / Save prominent |
| `MobileStoreCreateCalendarEventSheet`, `MobileStoreEditCalendarEventSheet` | Create: the Calendar tab's toolbar ＋ (New Event) or a tap on an empty stretch of its day grid. Edit: a tap on an event in the Calendar tab, in Today's schedule sheet, or in the iPad schedule pane | Save prominent |
| `MobileStoreEditHabitSheet` | A Habits catalog row's leading swipe or context menu; the habit page's Edit; Open Details in the context menu of a habit on Today | Save prominent |

Every sheet confirm is `.mobileProminentToolbarButtonStyle()` (glass-prominent
on iOS) with a white spinner while saving.

## Interaction (as built)

- Tap a tab → `store.selectedTab` through the `TabView` selection binding; each
  tab keeps its own navigation stack.
- Pull to refresh on Today → `store.refresh()`, which ends with one sync pass.
- Task row: the leading circle is a checkbox (`MobileTaskCompletionCircle`)
  that completes with a check cross-fade, spring pop, and haptic; the rest of
  the row is a `NavigationLink` to `MobileRoute.task`. Leading swipe Start or
  Pause; trailing swipe Complete (full swipe) and Defer to tomorrow; the
  long-press context menu offers Complete, Start or Pause, and a Defer submenu
  of days (`MobileTaskRowActions`).
- Schedule strip tap → the schedule sheet (`MobileTodayScheduleSheet`); its
  header ⋯ menu offers Suggest Times (`suggestDayTimes`) and, once a task has
  a time today, Clear Times, which confirms through a dialog first. A
  suggestion under review offers Use These Times or Dismiss above its rows,
  and Move to Tomorrow under the tasks that did not fit.
  Tapping a task or event row opens it, dismissing the sheet first on iPhone.
- Habit row (Today's strip or its accessibility-size list row): tap the ring
  to complete or reset today; the long-press context menu offers Open
  Details, which opens the edit sheet. The Habits section header pushes the
  Habits workspace onto Today's own navigation stack.
- Tasks home: tap a card or list → push the scoped list; leading swipe on a
  list row Edit, trailing swipe Delete (none on the Inbox, enabled only for an
  empty list); header ＋ → create-list sheet, whose Create opens the new list's
  screen; typing in search replaces the body with results.
- The Habits and Memory rows below Lists push `MobileRoute.workspace(...)`
  onto the Tasks stack; the Today gear pushes `.workspace(.settings)` onto
  Today's own stack.

## Notes for improvement (analysis — NOT yet implemented)

- The empty Tasks home (no lists, no tasks) has never been captured on device;
  the grid shows four zero cards above a "No Lists" row, which may read as
  heavy for a first launch.
