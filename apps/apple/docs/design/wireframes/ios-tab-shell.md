# iPhone Tab Shell + Today — As-Built Wireframe

> ASCII transcription of the iPhone (compact size-class) shell and Today surface, derived from the SwiftUI source.
> Structural reference, not a redesign. **The exact file:line citations below predate
> the IA restructure (tab bar is now Today · Tasks · Calendar · Habits · More; capture
> is a global ＋ sheet, not a tab) and the Today recomposition (the Lists feature-dump
> was dropped; the Focus Schedule is a calm CTA). The SwiftUI source is authoritative;
> treat line numbers as indicative.**

**Entry view:** `Sources/LorvexMobile/LorvexMobileStoreRootView.swift:70` (`tabBarBody`)
**Size class:** compact (iPhone / multitasking-narrow iPad)
**Backing state:** `MobileStore.selectedTab`, `.routePath`, `.snapshot` / `.summary`, `.lists` / `.habits` / `.calendarTimeline`, `.moreNavigationPath`, `.isLoading`

The shell picks tab-bar vs sidebar from `horizontalSizeClass` — `MobileChromeStyle.preferred` returns `.tabBar` for compact, `.sidebar` for regular (`Sources/LorvexMobile/MobileChrome.swift:11`). This doc covers only the compact `.tabBar` branch; the regular `sidebarBody` (`LorvexMobileStoreRootView.swift:111`) is out of scope.

## Layout (as built)

```
┌──────────────────────────────────────────┐
│ Today                          (large nav │ ← navigationTitle, RootView:75
│                                    title) │
├──────────────────────────────────────────┤
│ ╭────────────────────────────────────╮   │
│ │ <focusTitle>                        │   │ ← header Section, TodayView:22-32
│ │ <snapshot.today.summary> (secondary)│   │
│ │ [⊕ N open] [⊙ N focus]              │   │   metric chips, MobileTodayViews:9-14
│ │ → <nextTaskTitle>          (if any) │   │
│ ╰────────────────────────────────────╯   │
├──────────────────────────────────────────┤
│ NEXT                                       │ ← Section, TodayView:34
│  ⤷ <nextTask> row  (swipe / context menu) │   MobileActionTaskRow, TodayView:35-45
│     — or — empty state w/ [Capture Task]   │   MobileTaskEmptyState, TodayView:47
├──────────────────────────────────────────┤
│ TODAY                  (only if openTasks) │ ← Section, TodayView:55-70
│  ⤷ <openTasks[*]> rows                     │   ForEach MobileActionTaskRow
├──────────────────────────────────────────┤
│ HABITS                                     │ ← MobileStoreHabitsSection, TodayView:77
│  ↻ <habit>  N/M today      (◔ gauge) (≤4)  │   HabitSection:48-57
│  [View All Habits] (if hidden) [+ New …]   │
├──────────────────────────────────────────┤
│ CALENDAR                                   │ ← MobileStoreCalendarSection, TodayView:91
│  📅 <event> · date time · loc  (↻) (≤4)    │   CalendarSection:32-33
│  [View all (N more)]  [+ New Event]        │
│  [Export ICS] / [Share ICS]   <status>     │   CalendarSection:52-59
└──────────────────────────────────────────┘
┌──────────────────────────────────────────┐
│ [☀ Today][✓ Tasks][📅 Calendar][↻ Habits][⋯ More] │ ← TabView tab bar
└──────────────────────────────────────────┘   labels from MobileNavigation
```

A global ＋ (top-right of Today / Tasks, plus ⌘N) raises the quick-capture sheet
(`MobileStoreCaptureSheet`); capture is an action, not a tab. Review now lives in More.

The day plan (current focus + the schedule) lives inside Today; there is no separate Focus tab and no session timer. Each non-More tab wraps its content in a `NavigationStack`; `more` does not (its own stack lives inside `MobileStoreMoreView`). On first load with no content, a full-view `ProgressView` covers Today (`RootView:80-84`).

## Regions

| Region | What it renders | Data source (model field / store prop) | View file:line |
|---|---|---|---|
| Tab bar | 4 tabs: Today, Capture, Review, More — `Label(title, systemImage:)` per tab, `.tag(tab)` | `MobileTab` cases; selection `store.selectedTab` | `LorvexMobileStoreRootView.swift:71-108`, `:136-144` |
| Tab titles / icons | "Today"/checklist, "Capture"/plus.circle, "Review"/chart.line.uptrend.xyaxis, "More"/ellipsis.circle | `MobileTab.title` / `.systemImage` | `Sources/LorvexMobile/MobileNavigation.swift:13-29` |
| Today nav title (large) | "Today" navigation title on the Today stack | `MobileTab.today.title` | `LorvexMobileStoreRootView.swift:75` |
| First-load spinner | Full-view `ProgressView` overlay shown only while `isLoading` and Today is still `.empty` | `store.isLoading`, `store.snapshot.today == .empty` | `LorvexMobileStoreRootView.swift:80-84` |
| Today route destinations | Pushes `MobileStoreRouteView` for a `MobileRoute` (task/list/etc.) | `store.routePath` | `LorvexMobileStoreRootView.swift:85-87` |
| Header — focus title | `focusTitle` as section header text | `store.summary.focusTitle` (← `snapshot.today.focusTitle`) | `Sources/LorvexMobile/MobileStoreTodayView.swift:24` |
| Header — summary line | Secondary day-summary text | `store.snapshot.today.summary` | `MobileStoreTodayView.swift:26` |
| Header — metric chips | Two chips: open-task count (checklist) + focus-task count (scope); optional next-task label | `summary.openTaskCount`, `.focusTaskCount`, `.nextTaskTitle` | `Sources/LorvexMobile/MobileTodayViews.swift:9-18` |
| Next section | Single row for the next task, else empty state | `store.snapshot.nextTask` (`focusTasks.first ?? openTasks.first`) | `MobileStoreTodayView.swift:34-49`; `nextTask` `Sources/LorvexMobile/MobileHomeModels.swift:33-35` |
| Next empty state | `ContentUnavailableView` + prominent "Capture Task" jumping to Capture tab | `MobileTaskEmptyState` | `Sources/LorvexMobile/MobileTaskEmptyState.swift:15-29` |
| Today section | Conditional — only when tasks remain after excluding the pinned Next task; one `MobileActionTaskRow` per remaining open task | `MobileTodayTaskSections.todayTasks(from: store.snapshot)` | `MobileStoreTodayView.swift:55-70`; `MobileTodayTaskSections` `MobileStoreTodayView.swift:4-9` |
| Lists section | Up to 4 list rows (icon, name, description, openCount, chevron); "View All" if >4; "New List" | `store.lists?.lists` | `MobileStoreTodayView.swift:72-76`; `Sources/LorvexMobile/MobilePlanningSections.swift:11-66` |
| Habits section | Up to 4 active (non-archived) habit rows w/ circular gauge; "View All" if hidden; "New Habit" | `store.habits?.habits` | `MobileStoreTodayView.swift:77-90`; `Sources/LorvexMobile/MobileStoreHabitSection.swift:37-74` |
| Calendar section | Up to 4 event rows (icon, title, date/time/location, recurring glyph); "View all"; "New Event"; Export/Share ICS + status | `store.calendarTimeline?.events` | `MobileStoreTodayView.swift:91-104`; `Sources/LorvexMobile/MobileStoreCalendarSection.swift:24-60` |
| Capture tab | `MobileStoreCaptureWorkspaceView` in its own `NavigationStack`, title "Capture" | — | `LorvexMobileStoreRootView.swift:91-96` |
| Review tab | `MobileStoreReviewView` in its own `NavigationStack`, title "Review" | — | `LorvexMobileStoreRootView.swift:98-103` |
| More tab — Workspaces | `NavigationLink` rows: Tasks, Calendar, Habits, Lists, Memory | `workspaceDestinations` (`MobileDestination`) | `Sources/LorvexMobile/MobileStoreMoreView.swift:17-24`, `:53-55` |
| More tab — Settings | Separate section, single `NavigationLink` to Settings | `MobileDestination.settings` | `MobileStoreMoreView.swift:26-31` |
| More tab — destinations | Pushes `MobileDestinationView` (per-domain workspace) onto `store.moreNavigationPath` | `store.moreNavigationPath` | `MobileStoreMoreView.swift:15`, `:34-35`, `:60-82` |

## Interaction (as built)
- Tap a tab → sets `store.selectedTab` via `TabView` selection binding (`LorvexMobileStoreRootView.swift:71`, `:144`).
- Pull-to-refresh on Today list → `await store.refresh()` (`MobileStoreTodayView.swift:106`).
- Tap a task row → `store.selectTask(id)` (simultaneous tap gesture) and the row's `NavigationLink` pushes `MobileRoute.task` (`MobileTaskRows.swift:48-50`, `:12`; `MobileStoreTodayView.swift:40-44`).
- Task row leading swipe → Focus / Unfocus → `store.toggleTaskFocus(id)` (`MobileTaskRows.swift:51-58`). (Today passes `startSession: nil`, so the row's optional "Start" swipe is absent — `MobileStoreTodayView.swift:42`, `:64`.)
- Task row trailing swipe → Complete → `store.completeTask(id)`; Defer → `store.deferTaskToTomorrow(id)` (`MobileTaskRows.swift:70-86`).
- Task row long-press context menu → Complete / Defer / Focus (`MobileTaskRows.swift:90-125`).
- Tap "Capture Task" in the Next empty state → `store.selectedTab = .capture` (`MobileTaskEmptyState.swift:21-24`).
- Tap "View All Lists/Habits/Calendar" → `store.openMoreDestination(.lists/.habits/.calendar)` jumps to the More tab and pushes that workspace (`MobileStoreTodayView.swift:75`, `:89`, `:103`; `Sources/LorvexMobile/MobileStoreNavigationRouting.swift:57-59`).
- Tap "New List/Habit/Event" → presents the corresponding create `.sheet` (`MobileStoreTodayView.swift:126-149`).
- Edit a list row (tap) navigates via embedded `NavigationLink(value: MobileRoute.list)` (`MobilePlanningSections.swift:45`).
- Habit row: tap circular gauge toggles complete/reset; leading swipe Edit, trailing swipe Delete (`MobileStoreHabitSection.swift:114-132`, `:153-170`).
- Calendar row: leading swipe Edit, trailing swipe Delete (no full-swipe — deliberate, `allowsFullSwipe: false`); "Export ICS" → `store.exportCalendarICS()` then a `ShareLink` (`MobileStoreCalendarSection.swift:74-83`, `:126-148`).
- Tap a More-tab row → `NavigationLink` pushes the `MobileDestination` workspace onto `store.moreNavigationPath` (`MobileStoreMoreView.swift:19`, `:27`).

## Notes for improvement (analysis — NOT yet implemented)
- **Pinned Next task de-duplication is implemented.** `MobileTodayTaskSections.todayTasks(from:)` removes `snapshot.nextTask` from the Today section so the top task appears once in the pinned Next row and not again immediately below it.
- **Persistent iPhone capture affordance is now present.** Today keeps pull-to-refresh as the refresh path and adds a compact toolbar Capture button on compact-width devices (`MobileStoreTodayView.swift:107-114`), while the bottom ornament remains visionOS-only for spatial presentation (`Sources/LorvexMobile/MobileVisionOSOrnaments.swift:29-31`).
- **The four embedded planning sections (Lists/Habits/Calendar + open tasks) make Today a long scroll.** Each caps at 4 rows plus action buttons, but stacked with the header + Next + Today they push the calendar far below the fold. Consider whether the embedded sections belong on the landing surface or behind their tabs.
