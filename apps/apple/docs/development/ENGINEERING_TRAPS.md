# Engineering traps and data-flow facts

Rules for writing Swift, SwiftUI, AppKit, and UIKit code in this app that are
not visible from the code alone. Each entry states the rule and the reason it
exists. Where a hygiene rule, source pin, or test enforces it, the entry names
that check. Paths are relative to `apps/apple`.

Contents: [Crashes and isolation](#crashes-and-isolation) ·
[Async work and state](#async-work-and-state) ·
[Layout](#layout) · [Lists, sheets, and dialogs](#lists-sheets-and-dialogs) ·
[Gestures and hit targets](#gestures-and-hit-targets) ·
[Text, type, and locale](#text-type-and-locale) · [Widgets](#widgets) ·
[Data and time](#data-and-time) · [Data-flow facts](#data-flow-facts)

## Crashes and isolation

- **Never build a binding with the failable `Binding(_:)` initializer.**
  `Binding($optional)` force-unwraps on every read, and a closing sheet reads
  once more after the value is nil, which traps. Use `Binding(unwrapping:)`
  (`Sources/LorvexMobile/MobileOptionalBinding.swift`) or `.sheet(item:)`.
  `verify_source_hygiene.py` rejects `Binding($`.
- **Never put a `ForEach` inside a `ViewThatFits` candidate.** SwiftUI evaluates
  candidates it does not choose on a background render thread, where a
  main-actor `ForEach` closure fails Swift 6's isolation check
  (`_dispatch_assert_queue_fail`). Use static `if` branches; leaf candidates are
  fine. Hygiene rule `view_that_fits_no_foreach` enforces it. A `ViewThatFits`
  whose first branch is flexible also flips branches at nearby widths.
- **Mark pure helpers on a View struct `nonisolated static`.** A View's statics
  and initializers are main-actor isolated. A Swift Testing test that calls one
  off the main actor kills the whole test runner with signal 5, reported only
  as `swiftpm-testing-helper ... unexpected signal code 5` while other tests
  look green. The same applies to `Equatable` on a main-actor View: write
  `nonisolated static func ==`.
- **Observe notifications with async sequences.**
  `.onReceive(NotificationCenter.publisher(...))` can crash when the
  notification is posted off the main thread. Use
  `.task { for await _ in NotificationCenter.default.notifications(named:) }`.
- **Declare every custom drag type in the Info.plists.** A `Transferable` type
  backed by `UTType(exportedAs:)` that exists only in Swift lets SwiftUI accept
  the drag but never calls the drop closure. Add a `UTExportedTypeDeclarations`
  entry conforming to `public.data` both to the Mac plist written by
  `script/build_and_run.sh` and to `Config/LorvexMobileApp-Info.plist`, and add
  the Swift file to `DRAG_TYPE_SWIFT_PATHS` in `script/verify_app_metadata.py`,
  which checks the declarations.
- **Pin the time zone of every calendar notification trigger.** A
  `UNCalendarNotificationTrigger` built from date components without a time
  zone fires at that wall-clock time in whatever zone the device is in. Every
  one-shot reminder goes through `UNCalendarNotificationTrigger.oneShot(at:)`
  (`Sources/LorvexCore/Support/ReminderNotificationTrigger.swift`).
- **Treat CR LF as one character.** Swift reads `"\r\n"` as a single
  `Character` that equals neither `"\n"` nor `"\r"`, so `== "\n"`,
  `contains("\n")`, and `split(separator: "\n")` miss Windows line ends. Use
  `Character.isNewline` or iterate unicode scalars; `LorvexListText` parses
  free-text lists.
- **Run recursive walks over swift-markdown output on the deep stack.**
  Deeply nested markdown overflows the default 8 MB thread stack.
  `MarkdownNote.init` builds inside `MarkdownDeepStack.run`, a 256 MB pthread,
  and a source over 100,000 scalars renders as one verbatim code block. Strip
  markdown for excerpts with the linear `LorvexMarkdownMarks.removed(from:)`,
  never `AttributedString(markdown:)`, which recurses.
- `NSApp` is an implicitly unwrapped optional and is nil in some test and tool
  contexts; write `NSApp?.keyWindow`.
- The `--ui-preview` binary is a bare SwiftPM executable without a bundle, so
  `UNUserNotificationCenter.current()` aborts there. Read notification status
  through the store's injected status provider.
- `CKContainer(identifier:)` traps in a build without the iCloud entitlement,
  which includes simulator test harnesses. Do not turn on Sync with iCloud in
  one.
- When SwiftUI traps (SIGTRAP), read the newest `.ips` report in
  `~/Library/Logs/DiagnosticReports/` before guessing:
  `LorvexApple-*.ips` comes from a debug build or tour, and
  `swiftpm-testing-helper-*.ips` from the test runner. Line 1 is a JSON header;
  the rest is JSON with `exception`, `termination`, and the triggered thread's
  frames.

## Async work and state

- **Release a busy flag before the post-mutation fan-out.** After a write, the
  app publishes to Spotlight, reminders, the badge, the widget snapshot, and
  runs a CloudKit cycle. Those steps await the network or the OS, so a busy
  flag or presented sheet held across them freezes controls and drops taps.
  End the flag after the write and the reads that show its result, then run
  the fan-out (`publishAfterTaskCreate()` on macOS; a detached
  `publishMobileSyncSurfaces()` or `habitSurfacesFlight` on iOS).
- **Never await a single flight from inside its own work.** A refresh that
  awaits a sync cycle that awaits the same refresh flight deadlocks every later
  refresh and sync. Inside a flight, call the local reload directly
  (`performLocalRefresh()`); a sync cycle that needs fresh UI calls
  `refreshLocalSurfaces()`.
- **Decide "no unsaved edits" in the same synchronous step that adopts an
  async read.** Checking before the `await` lets a keystroke typed during the
  load be overwritten. Tag each read with the day or record it targets and drop
  it if the editor moved on. An autosave that stores a normalized form must not
  copy the saved text back into a live editor, and must compare "unsaved" under
  the same normalization (`DailyReviewEntry.isStored(...)`), or Quit stays
  blocked. Test these races with the gates on `StubCoreService`
  (`upsertDailyReviewGate`, `loadDailyReviewGate`, `updateTaskGate`); a
  `Task.yield()` passes alone and fails in the full run.
- **Bracket background database work on iOS.** When the app is suspended,
  `Database.suspendNotification` flags every open GRDB connection, and a
  suspended queue throws `SQLITE_ABORT` on writes. App Intents and notification
  actions that run in a backgrounded process wrap their work in
  `DatabaseSuspension.withBackgroundAccess(_:)` and report success only after
  the bracket ends. Never post the real suspend notification in a test. At
  backgrounding, `BackgroundSyncFlush.flushThenSuspend(store:)` writes autosave
  drafts and runs a CloudKit pass; a new self-saving draft must be added to
  that flush.
- **Keep view identity stable across reloads.** A reload that clears a cache a
  view's identity depends on rebuilds the view and drops its `@State`,
  including presented sheets. The symptom is several `onAppear` calls within a
  second; count them before blaming timing.
- **Key a view-owned `.task` on something that changes with the data.**
  `.task(id: key)` re-runs only when `key` changes. Keys in use:
  `AppStore.taskDataGeneration`, `MobileStore.taskWorkspaceRevision` and
  `habitDetailRevision`, `DayReviewReadKey` and `WeekReviewReadKey`
  (`Sources/LorvexCore/Models/ReviewReadKeys.swift`), and
  `AppStore.listPreviewKey`. Test a new key by making an assistant-style core
  edit, refreshing, and expecting the snapshot unchanged but the key different;
  a constant-key control must fail.
- An `@Observable` property assigned a value equal under `Equatable` does not
  notify observers.

## Layout

- **`.frame(maxHeight: N)` takes all of N** when offered it, and centers a
  shorter child. Alone it never shrinks below the ideal height; add
  `minHeight: 0`. Cap a scrolling region's height with `MobileScrollCapLayout`,
  which takes its content's height up to the cap.
- **An `HStack` offers each of two flexible children half the row**, so a
  label beside a long button wraps although room exists. Use
  `ViewThatFits { HStack { label; button.fixedSize(horizontal: true, vertical: false) }; VStack { … } }`
  or `.layoutPriority(1)`. A `.fixedSize()` chip holding user text overflows
  `LorvexFlowLayout`.
- **Never align marks with a fixed `alignmentGuide` offset.** An offset such as
  `center + 4` leaves marks several points low at large text sizes. Align to a
  hidden `Image(systemName: "circle")` in the row's font with
  `.frame(height: 0)` plus an overlay (`LorvexReviewAheadRow.markColumn`), or to
  one `@ScaledMetric(relativeTo:)` constant (`LorvexWeekReviewPage.moodDot`).
- **Measure width only with a `GeometryReader` that sizes its content to the
  proxy.** `Color.clear` in a `ZStack` reports the content's ideal width during
  transitions. A layout that depends on width must be stateless (a custom
  `Layout`); storing a measured width in state makes a pushed screen flip every
  frame ("Geometry action is cycling between duplicate values").
- `.contentMargins` reaches a `List` but never a `ScrollView`.
- `NSHostingController.sizingOptions = [.preferredContentSize]` can recurse
  into a stack overflow; size a panel from `NSHostingView.fittingSize`.
- `.offset` moves drawing but not menu, popover, or dialog anchors. Place an
  anchored view with `.alignmentGuide(.leading)` and `.alignmentGuide(.top)` in
  a top-leading `ZStack`.
- **Equatable rows and pages.** A stored `@Environment` or other
  `DynamicProperty` breaks the synthesized equality of `MobileTaskRow` and
  `MobileTaskRowContent`; read it in a child view. A page skipped by
  `.equatable()` never sees its parent's `@State`, so state a dialog inside a
  pager page reads must be part of the page's `Inputs`. Closures in inputs stop
  SwiftUI from skipping the view.
- Never nest a `NavigationStack` or `NavigationSplitView` inside a pushed view:
  the outer push silently does nothing. Attach `navigationDestination(item:)`
  to the enclosing stack.

## Lists, sheets, and dialogs

- **A hierarchical style inside a tinted control draws in the accent color.**
  `.foregroundStyle(.secondary)` or `.tertiary` inside a `Button`, `Menu`
  label, or List-row button resolves against the tint, producing faint blue at
  about 2:1 contrast; inside a widget `Link` it becomes an accent shade. Use
  `Color.secondary` for glyph-only controls and `.foregroundStyle(.primary)` on
  the button for multi-level labels. Never use `.tertiary` for information.
- A plain `List` row `Button` paints its title and icon separately; only
  `.foregroundStyle` on the button paints both (`mobileDestructiveRowStyle`,
  `mobileAccentRowStyle`). A `List` tints `Label` icons with the accent.
- **A `confirmationDialog` is a popover anchored at the view that carries it**
  and has no Cancel button; the user dismisses it by tapping outside. Attach it
  to the control that raises it (`mobileDeleteConfirmation(...)`).
- **A destructive-role swipe button closes its row's dialog before it shows.**
  Swipe buttons that raise a confirmation carry no role and use
  `.mobileDestructiveSwipeStyle()`. Swipe buttons take the accent tint over
  their role; `mobileNeutralSwipeStyle()` (`.tint(nil)`) gives gray.
- A `.sheet` attached to a `Section` can need two taps; attach tap-driven
  presentations to the tapped view.
- A root `.tint` reaches only views inside it. Put `.tint(.accentColor)` last
  in the root body, or sheets draw a black Cancel.
- iPad sheets are floating cards sized by their detents, and
  `horizontalSizeClass` reads `.compact` inside them. The presenter passes
  `showsAsCard`; detents come from `MobileEditorSheetDetents.detents(...)`.
- An inline sheet title has about 135 pt between the toolbar's glass buttons;
  use `mobileSheetTitle(_:)`, which steps the text down to fit.
- A popover anchored on a view that changes parent is dismissed. Keep one
  `ForEach` inside one custom `Layout` instead of moving rows between
  containers.
- iOS 26 inset-grouped Lists clip a section's first and last rows to a 26 pt
  corner. Open and close such a section with a zero-height `Color.clear` row
  plus `.environment(\.defaultMinListRowHeight, 0)`.
- Row separators start at the leftmost `Text`. A `List` ignores
  `defaultScrollAnchor`. A `VStack` of sub-rows is one List row; use `Group`
  for separate rows.
- The iPhone Habits screen has two row builders: `regularList` (iPad and batch
  mode) and `MobileStoreHabitsSection` (iPhone). An action added to one is
  missing from the other; pin both in tests.
- Selecting a `Tab` marked `.hidden(true)` aborts in UIKit. `MobileTab` holds
  only the tabs that are drawn, and a test guards it.

## Gestures and hit targets

- **A SwiftUI drag-type gesture that can begin on a view takes every touch**,
  even through `simultaneousGesture`, and blocks a UIKit-backed
  `TabView(.page)` pager. The Day and Week grids read scrolling from
  `.onScrollPhaseChange` and lift events with a UIKit long press
  (`MobileCalendarEventLift`); a source pin forbids `DragGesture`,
  `LongPressGesture`, and `simultaneousGesture` there.
- A `.contextMenu` with items delays sibling recognizers by about 0.4 s, so a
  liftable calendar block carries an empty menu builder.
- `TabView(.page)` creates the destination page at swipe time and relays out
  everything if its id list changes. Keep page ids fixed, give content only to
  pages within `MobileLivePages.keptEachSide` of the current one, make pages
  and cells `Equatable`, and never draw repeated chrome with `Canvas`.
- Small Buttons take touches up to about 40 pt outside their frame. Where
  several targets sit close together (iPad month cells), use one
  `.onTapGesture(coordinateSpace: .local)` and resolve the target from the
  location (`MobileCalendarMonthDayCell.chipIndex(atY:...)`).
- A plain-style Button row responds only on drawn content; add
  `.contentShape(Rectangle())`. A List cell clips touches outside its bounds;
  grow a small row with `minHeight: 44`. To reach a 44 pt target without moving
  the layout, pad the label and apply a matching negative padding outside the
  button.
- `.accessibilityIdentifier` on a container replaces its children's
  identifiers; add `.accessibilityElement(children: .contain)` first.
  `.accessibilityLabel` after `.accessibilityElement(children: .combine)`
  replaces the merged text; put extra facts in `.accessibilityValue`.
- A Mac view with only `.onTapGesture` has no Tab stop. Add
  `lorvexKeyboardActivation(_:)` (hygiene rule `paired`); VoiceOver still needs
  an `accessibilityAction`.
- Every animation goes through `Sources/LorvexCore/Support/LorvexReduceMotion.swift`
  (`lorvexAnimated`, `.reduceMotionAnimation`, `.reduceMotionBounce`,
  `.reduceMotionPop`); SwiftUI does not gate `withAnimation` or `.animation` on
  Reduce Motion. A pop-and-return scale must be skipped under Reduce Motion,
  not only un-animated. Any new fold header applies
  `.lorvexFoldState(isExpanded:)` so VoiceOver reads whether it is open.
- Mac window shortcuts are Option-Command 1 to 5; Shift-Command 3, 4, and 5
  belong to the system screenshot tools. Check the menus for a conflict before
  binding a shortcut.

## Text, type, and locale

- **A macOS `TextField(axis: .vertical)` drops its last line** when the font's
  cell height is slightly above SwiftUI's rounded frame. `.title2` does this;
  `.title`, `.title3`, `.headline`, `.callout`, `.subheadline`, and fixed 17 pt
  semibold do not. `LorvexDesign.Typography.detailTitle` is fixed 17 pt
  semibold, and `TitleFieldFitTests` checks frame height against
  `cell.cellSize(forBounds:)`; rerun it after changing a multi-line field's
  font.
- A `lineLimit(n)` text that truncates mid-word with room below needs
  `.fixedSize(horizontal: false, vertical: true)`.
- A single-line macOS `TextField` keeps pasted line breaks.
  `View.lorvexSingleLine($text)` with `LorvexCaptureParser.singleLine(_:)`
  rewrites the text from `.onChange`; a transforming `Binding` setter does not
  re-sync an active field. AppKit's select-all on focus overrides a caret
  position set in the same turn; set it again from
  `.onChange(of: fieldFocused)`.
- XXXL is a standard text size, not an accessibility size. Rows with a time
  column switch layout on `DynamicTypeSize.stacksTimeColumn` (xxLarge and up,
  `LorvexTextSizeLayout.swift`). A `@ScaledMetric` base must hold at the
  smallest size, and a subtree with a capped size needs its `@ScaledMetric` in
  a child struct. Accessibility-size task metadata is one interpolated `Text`
  with no-break spaces (`Text + Text` is deprecated). Helpers:
  `lorvexUnbreakable`, `lorvexDotJoined`, `lorvexClockRangeLabel`,
  `lineLimitUnlessAccessibilitySize`.
- Japanese line breaking splits Latin text between a letter and a digit, so
  user content goes through `Text(userContent:)` or
  `userContentTypesetting(_:)`.
- `Int()` and `Double()` read ASCII digits only; use `LorvexNumberInput`. In
  regular expressions `\d` matches digits of every script, and ICU reads `[:`
  as the start of a POSIX class name (write `[：:]`).
- The `.abbreviated` relative date style returns a bare signed number in
  French, Russian, and Romanian; `LorvexDateFormatters.relativePhrase` falls
  back to `.short`.
- `localizedStandardContains` misses ł, ø, æ, đ, ı, and Arabic hamza forms; use
  `String.containsSearchTerm(_:)`.
- AppKit mirrors layout only while `AppleTextDirection` is on, and that follows
  the system language list, so
  `LorvexAppleTextDirection.alignWithRunningLanguage()` runs first in app
  init. SwiftUI mirrors `rotationEffect` angles but not shapes: every ring arc
  is a `LorvexProgressArc` (the hygiene gate rejects `.trim(from:`), badges are
  placed with padding instead of `.offset`, and a fraction is one `Text`.

## Widgets

- WidgetKit draws only SwiftUI. On macOS `.buttonStyle(.borderless)` renders as
  a yellow placeholder; use `.plain` (hygiene rule).
- macOS widget text styles are small (title2 17 pt, body 13, subheadline 11,
  footnote and caption 10), so widgets use the `WidgetType` roles.
- Scripts with tall line metrics (Tamil, Telugu, Thai, Hindi, Urdu, Persian,
  Arabic, Bengali, Marathi, Vietnamese) make `ViewThatFits` reject rows that
  fit in Latin. `WidgetTypesetting` applies English typesetting for an
  allow-list of widget text.
- Widget timelines bake localized strings in when they are built; a language
  change shows after the next reload.

## Data and time

- Stored and wire day keys never use the user's calendar.
  `LorvexDateFormatters.ymd`, `ymdUTC`, and `hourMinute` pin the Gregorian
  calendar and `en_US_POSIX`; hand-built date keys use a Gregorian calendar.
  Display follows the locale's calendar (`displayCalendar(timeZone:)`).
- There are two overdue definitions. Today and the widgets use the logical day
  in the product time zone (`LorvexTaskSections.isOverdue`); rows and the menu
  bar use the device zone (`task.isOverdue()`).
- EventKit reports an all-day event's end as 23:59:59 on its last day; set
  `isAllDay` before the dates. `CalendarTimelineEvent.occurs(on:)` is the only
  day-membership rule: an event ending exactly at midnight belongs to the
  previous day.
- `deferTask(reason:)` accepts only `not_today`, `blocked`, `low_energy`,
  `needs_breakdown`, and `needs_info`.
- SQLite `DROP COLUMN` on a table's last column scans back to the nearest comma
  even inside an SQL comment; rebuild the table instead.
- The `LorvexMCPHost` helper processes that MCP clients keep alive survive app
  updates, so schema and SQL-function changes must work with an older helper on
  the same database. Register SQL functions on connections, never inside a
  schema object an older helper would have to evaluate.

## Data-flow facts

- **Every local write comes back as a full refresh.** The app process sets
  `DatabaseChangeSignal.postsInProcessOnWrite` at launch, so each committed
  core write posts one coalesced (50 ms) notification without an origin, and
  `AppStore` and `MobileStore` run a full `refresh()` for it. This second pass
  is part of the convergence design in
  `docs/architecture/MULTI_STORE_COHERENCE.md`; do not remove it. Unit tests
  run with the flag off.
- **The Mac inspector edits a draft against its baseline.** The draft
  (`taskDetail*` in `AppStoreTaskDetailStorage`) is compared only with
  `taskDetailDraftSource`, the record it was filled from, never with the live
  task. A save writes only fields that differ from the baseline
  (`taskDetailUpdateDraft(id:)`, `TaskDetailEditedFields`). Every
  selected-task mutation ends in `afterSelectedTaskMutation()` or
  `finishBatchMutation(on:)`; read dirtiness before the record changes. iOS
  edits use a sheet whose `MobileTaskEditDraft` patches against its opening
  baseline.
- **Review pages follow the logical day.** State that holds "the day this page
  shows" either follows the logical day or names a deliberate past day, and
  state that follows today flushes dirty drafts before the day moves
  (`carryReviewToNewLogicalDay(from:to:)` on iPhone,
  `flushDailyReviewDraftBeforeLogicalDayChange(to:)` on the Mac). In tests,
  roll the day by switching the product `timezone` preference between
  `Pacific/Pago_Pago` and `Pacific/Kiritimati` and refreshing.
- **Habit day scope.** `LorvexHabitSchedule.isListed(on:)` is what is still
  open that day (Today, menu bar, widgets, watch); `isReviewed(on:)` is what
  counted that day (day reviews and `DayReview.habitSummarySQL`).
  `LorvexHabit.periodMetDays` is valid only for the day passed to
  `loadHabits(date:)`. Management pages, Siri entities, and MCP list every
  habit.
- **Habit skips are an entity.** Skip Today is an excused day stored as the
  synced composite edge `habit_skip` (table `habit_skips`), because fields of
  `habit` cannot evolve and `habit_completions` requires `value > 0`. A
  check-in on a skipped day wins.
- **Repeating tasks.** A generated occurrence carries
  `recurrence_instance_key = "<group id>:<occurrence date>"`, enforced by a
  schema CHECK and a unique index. The recurrence engine
  (`core/Sources/LorvexStore/CalendarRecurrence*.swift`) is checked against
  python-dateutil; it deliberately clamps an implicit day of month, and a
  YEARLY rule with BYMONTHDAY but no BYMONTH repeats only in the start month.
- **Search folds at query time.** FTS5 with `remove_diacritics 2` misses
  letters such as ł, đ, ß, æ, ı, ё, Greek tonos, and Arabic variants, and treats
  Thai, Lao, Burmese, and Khmer runs as one token. The SQL function
  `lorvex_fold` (`core/Sources/LorvexDomain/SearchFold.swift`) is registered on
  every connection and used only at query time.
  `TaskRepo.Search.searchTasksWithFallback` tries, in order: trigram or LIKE
  for unspaced scripts, LIKE for queries without letters or digits, FTS5, the
  folded scan when FTS5 found nothing, and a LIKE retry for a short trailing
  token.
- **Capture always parses.** Every capture surface goes through
  `AppStore.captureLine(_:)` or `createInlineTask(.inbox)` on the Mac and
  `captureTaskDraft` on iOS, never `core.createTask(title:)` with raw text. The
  "Capture Lorvex Task" App Intent and watch dictation stay unparsed on
  purpose. The first parse compiles every language's patterns (0.1 to 0.4 s),
  so both stores call `LorvexCaptureParser.warmUp()` in the background.
- **Intents take native values.** Date and time parameters are native values
  converted by `IntentDateText`; no intent takes a raw id.
  `LorvexIntentHandoffStore` holds one pending request, consumed by
  `MobileStore.applyPendingIntentHandoff()`.
- **MCP responses are fenced by key name.** A new user-text field needs a
  marker in `storedMarkers` of `MCPResponseFencingSweepTests`; a new tool needs
  a `readCalls` entry or a successful call in the sweep's dataset.
  `ToolRegistry.call` appends a fenced notice listing undeclared arguments.
- **The watch is a replica.** The phone sends the watch replica through
  `updateApplicationContext` plus a pull message; a change to the wire format
  needs `WatchReplicaRoundTripTests`, because watch captures bypass the wire.
