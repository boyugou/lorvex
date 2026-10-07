# macOS Calendar Week Grid — As-Built Wireframe

> ASCII transcription of the macOS calendar week grid, derived from the SwiftUI source.
> Current-state reference, not a redesign. Line numbers are intentionally omitted
> (they drift); cite files and types instead.

**Entry view:** `CalendarWorkspaceView.calendarColumn`
(`Sources/LorvexApple/Views/CalendarWorkspaceView.swift`) switches on
`mode: CalendarPresentationMode` and, for `.week` (and for `.day`, reusing the identical
view at `visibleDayCount: 1`), mounts `CalendarWeekGridView`
(`Views/CalendarWeekGridView.swift`). `CalendarWorkspaceView.body` itself is an `HStack`
of that calendar column plus, only while `store.selectedCalendarEvent` is set, a
trailing `CalendarEventInspector` panel — a read-only, calendar-local inspector
distinct from the main window's task/habit `.inspector` described in `macos-shell.md`.

**Backing state:** `AppStore.calendarTimeline: CalendarTimelineSnapshot?`
(`Stores/AppStoreCalendarState.swift`, stored in `AppStoreCalendarStorage`) and `AppStore.scheduledTasks`
(`Stores/AppStoreTaskDerivedState.swift`). The grid reads both directly — there is no
separate search-filtered projection for the calendar — and assembles them into
per-day columns with `CalendarGridModel.buildDays(...)`
(`Sources/LorvexCore/Support/CalendarGridModel.swift`), a platform-neutral layout
function shared with the iPhone day / 3-day view. A `nil` `calendarTimeline` shows the
loading overlay (`CalendarWorkspaceView`).

Scope note: this wireframe covers the **week time-grid** (`mode == .week`). Day mode
reuses the identical `CalendarWeekGridView` at `visibleDayCount: 1`; Month mode
(`CalendarMonthGridView`) is a different view and is not drawn here. Selecting a block
opens the read-only inspector described above; editing goes through
`EditCalendarEventSheet`, reached from the inspector's Edit button or from the
block's right-click menu.

## Layout (as built)

```
┌──────────────────────────────────────────────────────────────────────────────────┐
│ [‹] Jun 1 – Jun 7 [›]  [This Week]        Day | Week | Month              [ + ]  │  window toolbar
├──────────────────────────────────────────────────────────────────────────────────┤  (navigation · principal · primary action)
│ 📅 Calendar                                                                       │  CalendarWorkspaceHeader (title only)
├──────────────────────────────────────────────────────────────────────────────────┤  Divider
│                                                                                    │
│  ── grid (CalendarWeekGridView) ──────────────────────────────────────────────    │
│           │ SUN │ MON │ TUE │ WED │ THU │ FRI │ SAT │                              │  day-name header band:
│           │  1  │  2  │ (3) │  4  │  5  │  6  │  7  │   (today = tinted circle)     │   weekday, day number,
│           │2 hr │     │1 hr │ 30  │     │     │     │   workload caption           │   workload caption
│           │     │     │     │ over│     │     │     │   (blank when day is empty)  │
│           ├─────┼─────┼─────┼─────┼─────┼─────┼─────┤                              │  Divider
│  all-day  │▐Evt │┊Tsk┊│ +2  │     │     │     │     │   event pill (solid rail),   │  all-day strip
│           │     │     │     │     │     │     │     │   task pill (dashed), each   │
│           │     │     │     │     │     │     │     │   column's own "+N" pill     │
│           ├─────┼─────┼─────┼─────┼─────┼─────┼─────┤                              │  Divider
│  ┌ scroll region (24h, hourHeight=56) ─────────────────────────────────────────┐   │
│  │ 6 AM│     │     │     │     │     │     │     │                              │   │
│  │     │     │▐────┤     │     │     │     │     │  hour gutter (56pt) +        │   │
│  │ 7 AM│     │▐ Evt│     │     │     │     │     │  7 day columns, each up to   │   │
│  │     │     │▐ 7a │     │┊○Tsk┊     │     │     │  3 overlap lanes             │   │
│  │ 8 AM│ ─ ─ │▐────┤ ─ ─ │┊    ┊ ─ ─ │ ─ ─ │ ─ ─ │  hour grid lines             │   │
│  │     │     │     │═════│┊    ┊ ← red now-line + dot on today's column          │   │
│  │ 9 AM│     │     │     │┊    ┊     │     │     │        (+2)                  │   │  +N overflow badge
│  │     │     │     │     │     │     │     │     │       (events + tasks past   │   │  (lane 3 and beyond)
│  │10 AM│     │     │     │     │     │     │     │        3 lanes, tap → popover)│   │
│  └──────────────────────────────────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────────────────────────────┘
```

`▐` marks an event block's solid tint fill and colored left rail; `┊ ┊` marks a task
block's or task pill's hollow dashed "calendar task surface" outline with a leading
completion circle. When every visible day is empty, a banner sits over the top of
the empty grid; see "Empty / unauthorized banner" below.

## Regions

| Region | What it renders | Data source (model field / store prop) | View file |
|---|---|---|---|
| Workspace header | The title "Calendar" with a calendar icon. The header only names the surface: the grid shows every event and planned task itself, so a count would restate it | — | `CalendarWorkspaceHeader` in `CalendarWorkspaceNavigationBar.swift` |
| Toolbar navigation group | `chevron.left` · range chip · `chevron.right`, plus a "Today / This Week / This Month" jump shown only while not viewing the current period | `anchorDate`, `weekRangeTitle`, `monthRangeTitle`, `isViewingCurrent`, `step(_:)`, `jumpToCurrent()` (`CalendarWorkspaceView.swift`) | `CalendarWorkspaceToolbar` in `CalendarWorkspaceNavigationBar.swift` |
| Range chip | Week/Month mode: the visible range; Day mode: the anchor date. Opens the month popover; picking a day re-anchors to its period | `LorvexDateChip(style: .toolbar)` | `LorvexDateChip.swift` |
| Toolbar principal slot | Segmented Day / Week / Month toggle | `mode: CalendarPresentationMode` | `CalendarModePicker` in `CalendarWorkspaceNavigationBar.swift` |
| Toolbar primary action | `plus` Create Event | `store.beginCreateCalendarDraft()` then the create sheet | `CalendarWorkspaceToolbar` |
| Event inspector panel | A trailing, read-only panel beside the grid (part of `CalendarWorkspaceView`'s own `HStack`, not the main window's `.inspector`) showing the selected event's detail, with Edit, Delete, and a close button | `store.selectedCalendarEvent` | `CalendarEventInspector.swift` |
| Day-name header band | Per-column weekday (`EEE`) and day number (today gets a tinted circle), with a workload caption underneath: the day's meeting + task time ("2 hr", "45 min"), or that length plus "over" once it exceeds the working window, in the overdue tint; the line is reserved but blank when the day has nothing planned, so day numbers stay level | `columns: [CalendarGridDay]`; `CalendarWeekDayLoadCaption` (built from `CalendarWeekGridView.weekLoad(_:)`) | `CalendarWeekGridChrome.swift` (header); `CalendarWeekGridDayLoad.swift` (caption + load math) |
| All-day strip | Per-column event pills (solid tint fill + colored rail) then task pills (dashed "calendar task surface" outline with a leading completion circle). A column shows up to three; with more, it shows two and gives the third place to its "+N" pill | `day.allDayEvents`, `day.scheduledTasks` | `CalendarWeekGridChrome.swift` |
| All-day overflow pill | A column's own "+N" pill once its all-day events and tasks number more than three; opens a popover listing the hidden events and tasks, each tappable to open | `CalendarWeekGridMetrics.allDayMaxItems` (3) | `CalendarWeekGridChrome.swift` |
| Hour gutter | 24 right-aligned localized hour labels; also anchors the initial auto-scroll position | `hourLabel(_:)`; `WeekGridAnchorModifier` | `CalendarWeekGridChrome.swift` |
| Day column | One column: hour grid lines, the now-line, the empty-slot interaction layer, event blocks, task blocks, and the overflow badge, layered in that z-order | one `CalendarGridDay` | `CalendarWeekGridView.dayColumn` |
| Hour grid lines | 24 stacked `hourHeight`-tall rows, each with a top divider and a fainter half-hour divider | constant `0..<24` | `CalendarWeekGridHourCell` in `CalendarWeekGridComponents.swift` |
| Empty-slot interaction layer | A transparent hit layer beneath the blocks: tap → create at the tapped hour; drag → create with a custom duration | `createAt(date, minutes, duration)` (from `CalendarWorkspaceView`) | `CalendarWeekGridView.dayColumn`; gestures in `CalendarWeekGridGestures.swift` |
| Drag-to-create ghost | Translucent dashed preview block with a start–end time label, shown only in the column being dragged | `CalendarWeekGridView.CreateDraft` | `CalendarWeekGridView.dayColumn` |
| Timed event block | A positioned, colored block (title, and the start time once tall enough) at its lane offset; a small hint icon marks an editable block that cannot be dragged (recurring or multi-day), whose times change only through the edit sheet | `CalendarGridTimedBlock` (`startMin`/`endMin`/`lane`/`laneCount`/`event`) | `CalendarWeekGridEventBlock.swift` |
| Timed task block | A scheduled task at its time, in the accent tint on the dashed "calendar task surface" outline rather than an event's solid fill and rail, sharing the day's overlap lanes with event blocks; a leading circle completes or reopens it in place | `CalendarGridTaskBlock` (`startMin`/`endMin`/`lane`/`laneCount`/`task`) | `CalendarWeekGridTaskBlock.swift` |
| Resize handles (top/bottom) | Drag grips on an editable, single-day, non-recurring timed event block; visible on hover or selection, with an always-live hit area and resize cursor | `event.editable && !allDay && !supportsScopedMutation && !isMultiDay` | `CalendarWeekGridEventBlock.swift` |
| +N overflow badge | A capsule "+N" at the earliest hidden block's row once a day column holds more than 3 overlapping lanes of events and tasks combined; opens a popover ("Hidden events") listing that day's hidden tasks, then its hidden events, each group in time order | `day.timedBlocks` / `day.taskBlocks` filtered to `lane >= maxDisplayedLanes` (3) | `CalendarWeekGridView.overflowBadge` |
| Now guide | A red dot and 1.5pt line on today's column, a faint 1pt guide at the same minute on every other day, ticking once a minute | `TimelineView(.periodic(from: .now, by: 60))` | `CalendarWeekGridChrome.swift` |
| Empty / unauthorized banner | A banner over the top of the grid when every visible day is empty: "Calendar Access Off" with an Open Settings button while EventKit access needs recovery, otherwise an "Open Week" / "Open Day" prompt with a Create Event button | `EventKitAuthorizationHelper().needsSettingsRecovery`; `columns.allSatisfy(\.isEmpty)` | `CalendarWeekAuthorizeOverlay`, `CalendarWeekEmptyOverlay` in `CalendarWeekGridComponents.swift` |

## Interaction (as built)
- Tap an empty slot → `createAt(day.date, hourSnapped, 60)` opens the create sheet, pre-filled at the tapped hour with a 60-minute default.
- Drag empty space → sketches a dashed ghost; release commits a create whose duration is the dragged span, snapped to 15 minutes and floored at 15 minutes. A drag shorter than one snap row falls back to the same 60-minute tap-to-create instead of committing a sliver event.
- Tap, or press Return/Space on, a timed event block, a resize handle, or an all-day event pill → `selectEvent`, which toggles `store.selectedCalendarEventID` and opens or closes the read-only event inspector panel. Right-click offers "Open Details" (the same action as a tap) and, when the event is editable, "Edit" (opens `EditCalendarEventSheet`) and "Delete". The inspector's Edit button opens the same sheet.
- Tap a timed task block or an all-day task pill → `openTask(block.task)`, which opens the task; a leading circle on either completes or reopens the task in place without opening it.
- Drag a timed event block (single-day, non-recurring, editable only) → a live `rescheduleDraft` preview; vertical movement changes the start time, horizontal movement shifts days; release commits through `store.rescheduleCalendarEvent(...)`. An editable recurring or multi-day block shows a small hint icon instead, and its times change only through the edit sheet; a read-only event does not move.
- Drag the bottom or top edge of an editable event block → resizes the end or start time, snapped to 15 minutes and floored at 20 minutes (`CalendarGridModel.minBlockMinutes`), so a resize can never make a block shorter than the grid's own render floor.
- A move or a resize of an event registers one undo named "Move Event", which writes the event's previous start and end back and leaves its title, location, and notes as they are by then; the undo can be redone. An event deleted in between is left alone.
- Drag a timed task block (not finished) → the block follows the pointer in 15-minute steps and across columns, with the same live preview as an event block; release plans the task there through `store.planTasks(ids:on:time:undoManager:)`, keeping its length. A drag shorter than one step changes nothing.
- Drop a task (an all-day pill, or a task row dragged from a list) on a time in a day column → the column shows a line and the start time under the pointer; release plans the task on that day from that quarter hour. The task keeps its own length when it already has a time, else takes its estimate (half an hour with none); several dropped tasks stack one after another.
- Drop a task on a day's all-day strip → the task is planned on that day without a time; a task that had a time loses it. Every day column is a drop target, both on its strip and on its time axis.
- Month cells take task drops the same way: a task dropped on a day is planned for it and keeps its own time; an open task chip drags to another day. The toolbar's "Unplanned Tasks" toggle shows `CalendarPlanRail` beside the grid in every mode: the open tasks with no planned day, in the canonical order, as the shared task row (completion circle, context menu, drag), with "N more" after the first 40. It reloads on every task change while shown, and the choice persists (`calendar.workspace.planRail`).
- Every plan change from the grid registers one undo named "Plan Task", which restores each task's previous day and time; the undo can be redone. Finished and cancelled tasks never move.
- Tap a day's timed-grid "+N" overflow badge → opens a popover listing that day's hidden tasks, then its hidden events, each group in time order. Picking a task calls `openTask`; picking an event calls `selectEvent`. A read-only event's row is disabled and shows no pencil icon.
- Tap a column's all-day "+N" overflow pill → opens a separate popover listing that column's hidden all-day events and tasks.
- An all-day task pill's context menu adds "Plan a Day Later" and "Plan a Week Later" alongside Open Task and Complete/Reopen; a timed task block's context menu adds the same two items (the block keeps its time on the new day), except on a finished task.
- Initial appear and week change auto-scroll to `CalendarGridModel.initialScrollAnchorHour(...)`, which anchors on today's earliest timed item or the current hour.
- Prev / Next / "Today or This Week" change the anchor date, which reloads only the visible range.
- ⌘← / ⌘→ on the toolbar chevrons step the visible period: a day in Day mode, a week in Week mode, a month in Month mode.
- An empty week or day shows the banner described in the Regions table above.

## Notes for improvement (analysis — NOT yet implemented)
- Overlap clusters beyond 3 lanes rely on the "+N" popover rather than an expanded-column view; a denser inline layout could still help very busy days.
- Keyboard navigation covers period paging (⌘←/⌘→) but not the grid itself: there is no arrow-key way to move slot-by-slot through a day column, and no focusable "now" target.
