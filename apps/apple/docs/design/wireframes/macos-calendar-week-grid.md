# macOS Calendar Week Grid — As-Built Wireframe

> ASCII transcription of the macOS calendar week grid, derived from the SwiftUI source.
> Each region cites the view file:line that renders it. Current-state reference, not a redesign.

**Entry view:** `Sources/LorvexApple/Views/CalendarWorkspaceView.swift:21` (body) → week branch
mounts `CalendarWeekGridView` at `CalendarWorkspaceView.swift:64`; the grid body is
`Sources/LorvexApple/Views/CalendarWeekGridView.swift:99`.

**Backing state:** `AppStore.calendarTimeline: CalendarTimelineSnapshot?`
(`Stores/AppStoreCalendarState.swift:5`). The grid never reads it raw — it consumes the
search-filtered derivations `filteredCalendarEvents`
(`Stores/AppStoreContentSearchDerivedState.swift:5`) and `filteredScheduledTasks`
(`Stores/AppStoreTaskSearchDerivedState.swift:33`), assembled into per-day columns by
`CalendarGridModel.buildDays(...)` (`CalendarWeekGridView.swift:66`). A `nil`
`calendarTimeline` shows the loading overlay (`CalendarWorkspaceView.swift:112`).

Scope note: this wireframe covers only the **week time-grid** (`mode == .week`). List mode
(`mode == .list`, rendered by `CalendarWorkspaceContentList` / `CalendarEventRow`) and the
mode-gated toolbar batch menu (`CalendarWorkspaceView.swift:115`, `.disabled(mode != .list)`)
are a separate list idiom and out of scope. Tapping a block opens
`EditCalendarEventSheet` (recurring-scope edit lives there, not in the grid).

## Layout (as built)

```
┌──────────────────────────────────────────────────────────────────────────────────┐
│ Calendar                                              [⬆ Export ICS]   [ + ]       │  WorkspaceHeader
│ "N events and M planned tasks from Lorvex."                                        │  (title/subtitle/actions)
├──────────────────────────────────────────────────────────────────────────────────┤  Divider
│ [‹]  Jun 1 – Jun 7  [›]   [This Week]                   ◷ Week | ☰ List            │  Nav bar (week mode)
├──────────────────────────────────────────────────────────────────────────────────┤  (ICS status line, when present)
│                                                                                    │
│  ── grid (CalendarWeekGridView) ──────────────────────────────────────────────    │
│           │ SUN │ MON │ TUE │ WED │ THU │ FRI │ SAT │                              │  day-name header band
│           │  1  │  2  │ (3) │  4  │  5  │  6  │  7  │   (today = tinted circle)     │
│           ├─────┼─────┼─────┼─────┼─────┼─────┼─────┤                              │  Divider
│  all-day  │ [▍task] [▍evt] │ ... per column ...     │                              │  all-day strip
│           ├─────┼─────┼─────┼─────┼─────┼─────┼─────┤                              │  Divider
│  ┌ scroll region (24h, hourHeight=56) ───────────────────────────────┐  ( ⌃ Earlier )│  off-screen pill (top overlay)
│  │ 6 AM│     │     │     │     │     │     │     │                     │            │
│  │     │     │┌───┐│     │     │     │     │     │  hour gutter(56pt)  │            │
│  │ 7 AM│     ││▍ev││     │     │     │     │     │   + 7 day columns   │            │
│  │     │     ││ 7a││     │     │     │     │     │   (lanes 0..2)      │            │
│  │ 8 AM│ ─ ─ │└───┘│ ─ ─ │ ─ ─ │ ─ ─ │ ─ ─ │ ─ ─ │  hour grid lines    │            │
│  │     │     │     │═════│  ← red now-line + dot on today's column     │            │
│  │ 9 AM│     │     │┌──┐ │     │     │     │     │            (+2)─┐   │            │  +N overflow badge
│  │     │     │     ││▍ ││     │     │     │     │                 │   │            │
│  └──────────────────────────────────────────────────────────────────┘  ( ⌄ Later )│  off-screen pill (bottom overlay)
└──────────────────────────────────────────────────────────────────────────────────┘
```

## Regions

| Region | What it renders | Data source (model field / store prop) | View file:line |
|---|---|---|---|
| Workspace header | Title "Calendar" + subtitle summary + trailing actions | `summary` string from `filteredCalendarEvents.count` / `filteredScheduledTasks.count` (`CalendarWorkspaceModels.swift:5`) | `CalendarWorkspaceView.swift:23` |
| Header actions (Export ICS / +) | ShareLink or export button, then `plus` create button | `icsExportItem` / `icsExportState` (`CalendarWorkspaceView.swift:8`) | `CalendarWorkspaceHeaderActions.swift:10` |
| Nav prev/next arrows | `chevron.left` / `chevron.right`, step ±1 week | `step(_:)` (`CalendarWorkspaceView.swift:212`) | `CalendarWorkspaceNavigationBar.swift:15`, `:36` |
| Week-range title | "MMM d – MMM d" for the visible week | `weekRangeTitle` from `weekStart` (`CalendarWorkspaceView.swift:206`) | `CalendarWorkspaceNavigationBar.swift:24` |
| "This Week" jump button | Shown only when not viewing current week | `isViewingCurrent` (`CalendarWorkspaceView.swift:189`) | `CalendarWorkspaceNavigationBar.swift:45` |
| View-mode picker | Segmented Week / List toggle | `mode: CalendarPresentationMode` (`CalendarWorkspaceView.swift:11`) | `CalendarWorkspaceNavigationBar.swift:54` |
| ICS status line | Transient export status text | `icsExportState.statusMessage` | `CalendarWorkspaceView.swift:53` |
| Day-name header band | Per-column weekday (`EEE`) + day number; today gets tinted circle | `columns: [CalendarGridDay].date`; `isToday` | `CalendarWeekGridChrome.swift:7` |
| All-day strip | Per-column all-day event pills + scheduled-task pills | `day.allDayEvents` (events), `day.scheduledTasks` (tasks) | `CalendarWeekGridChrome.swift:35` |
| All-day pill | Single title pill with color left-rail | `event.title` / `task.title`, `eventColor` | `CalendarWeekGridChrome.swift:78` |
| Hour gutter | 24 right-aligned localized hour labels; carries the scroll anchor | `hourLabel(_:)`; `WeekGridAnchorModifier` (`CalendarWeekGridChrome.swift:102`) | `CalendarWeekGridChrome.swift:95` |
| Day column | One column: grid lines + interaction + blocks + badge + now-line | one `CalendarGridDay` | `CalendarWeekGridView.swift:185` |
| Hour grid lines | 24 stacked `hourHeight`-tall rows with top dividers | constant `0..<24` | `CalendarWeekGridView.swift:192` |
| Empty-slot interaction layer | Transparent hit layer: tap → create-at-hour; drag → create-with-duration | `createAt(date,minutes,duration)` (`CalendarWorkspaceView.swift:74`) | `CalendarWeekGridView.swift:208` |
| Drag-to-create ghost | Translucent dashed preview block w/ time-range label during drag | `createDraft: CreateDraft?` (`CalendarWeekGridView.swift:38`) | `CalendarWeekGridView.swift:221` |
| Timed event block | Positioned colored block (title + start time), lane-offset | `CalendarGridTimedBlock` (`startMin`/`endMin`/`lane`/`laneCount`/`event`) | `CalendarWeekGridEventBlock.swift:8` |
| Resize handles (top/bottom) | Drag grips on editable single-day timed blocks | `block.event.editable && !allDay && !isRecurring && !isMultiDay` | `CalendarWeekGridEventBlock.swift:89` |
| +N overflow badge | Capsule "+N" at earliest hidden event's Y when >3 lanes | `day.timedBlocks.filter { lane >= maxDisplayedLanes }` (`maxDisplayedLanes = 3`, `:24`) | `CalendarWeekGridView.swift:272` |
| Now guide | Red dot + 1.5pt line on today, faint 1pt guide on adjacent days at the same minute, ticks every 60s | `TimelineView(.periodic … by: 60)` (`CalendarWeekGridView.swift:262`) | `CalendarWeekGridChrome.swift:108` |
| Off-screen pill (Earlier) | Top overlay capsule when a timed block sits above viewport | `nearestAboveMinute` (`CalendarWeekGridView.swift:84`) | mounted `CalendarWeekGridView.swift:151`; view `CalendarOffScreenPill.swift:14` |
| Off-screen pill (Later) | Bottom overlay capsule when a timed block sits below viewport | `nearestBelowMinute` (`CalendarWeekGridView.swift:92`) | mounted `CalendarWeekGridView.swift:161`; view `CalendarOffScreenPill.swift:14` |

## Interaction (as built)
- Tap empty slot → `createAt(day.date, hourSnapped, 60)` opens create sheet pre-filled at the tapped hour, 60-min default (`CalendarWeekGridView.swift:210`).
- Drag empty space → sketches dashed ghost; release commits create with the dragged duration snapped to 15 min (min 15); a sub-snap-row twitch falls back to the 60-min tap behavior (`CalendarWeekGridGestures.swift:40`).
- Tap timed block → `editEvent(block.event)` → opens `EditCalendarEventSheet` (`CalendarWeekGridEventBlock.swift:84`).
- Drag timed block (editable single-day only) → live `rescheduleDraft` preview; vertical = new start time, horizontal = day shift; release → `store.rescheduleCalendarEvent(...)` (`CalendarWeekGridGestures.swift:80`).
- Drag bottom edge → resize end time, snap 15 min, min 15-min duration → `store.rescheduleCalendarEvent` (`CalendarWeekGridGestures.swift:124`).
- Drag top edge → resize start time, keep end fixed → `store.rescheduleCalendarEvent` (`CalendarWeekGridGestures.swift:160`).
- Tap all-day event pill → edit (if `event.editable`); tap scheduled-task pill → `openTask(task)` selects the task (`CalendarWeekGridChrome.swift:49`, `:59`).
- Tap off-screen pill → `proxy.scrollTo(WeekGridScrollAnchor.hour(...))` scrolls to the nearest hidden event (`CalendarWeekGridView.swift:151`, `:161`).
- Initial appear / week change → auto-scroll to `initialScrollAnchorHour` (anchors on today's earliest timed event or the now-hour) (`CalendarWeekGridView.swift:104`, `:171`).
- Prev/Next/This-Week change `weekStart`, which triggers `fetchVisibleWeek` to reload only the visible range (`CalendarWorkspaceView.swift:171`).
- ⌘← / ⌘→ on the calendar navigation buttons step to the previous/next week in week mode and previous/next day in list mode (`CalendarWorkspaceNavigationBar.swift:22`, `:44`).

## Notes for improvement (analysis — NOT yet implemented)
- **Off-screen-pill naming is now truthful.** `nearestAboveMinute` and `nearestBelowMinute`
  describe the actual behavior: scroll to the closest hidden event above or below the viewport.
- **Hard-coded `+N` lane cap (`maxDisplayedLanes = 3`, `:24`)** keeps only three overlapping
  lanes visible, but the overflow badge is now interactive: tapping it opens a popover of hidden
  events sorted by time, and editable entries jump to the event sheet. A fuller expanded-column
  mode could still improve dense clusters.
- **Keyboard navigation is partial.** ⌘← / ⌘→ now page the visible calendar period through the
  nav buttons. Arrow-key slot focus and a focusable "now" target remain unimplemented.
- **Cross-week now guide is implemented.** Today keeps the red live now-line; off-day columns show
  a faint guide at the same minute so scanning across the week no longer relies only on the gutter.
- **Multi-day and recurring blocks are sheet-editable, not grid-resizable.** `isEditable`
  still excludes `isRecurring`/`isMultiDay` from drag/resize handles, but editable blocks now show
  a small hint icon and continue to open the event sheet on tap.
```
