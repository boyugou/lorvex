# Lorvex Apple — Design System

The visual contract every Apple surface composes from: one semantic color
system, one surface ladder, one type scale per platform, and a small set of
shared components. `script/verify_design_tokens.py` enforces the rules below
on every gate, so a view either uses a token or names a documented exception.

The product premise shapes the language: the assistant does the organizing, the
human captures, orients, executes, and reflects. Screens therefore stay calm
(few elements, generous spacing) but never bare (every element is a crafted
component, not a default control). Native first: system materials, SF
typography, system controls and gestures, then a considered layer of color,
tiles, cards, and motion on top.

## 1. Color

Color is semantic. A view never names a system hue (`.orange`, `Color.red`,
`Color(red:green:blue:)`); it names what the color means, through
`LorvexDesign.Palette` (`Sources/LorvexCore/Support/LorvexDesignSystem.swift`).
Each hue carries at most one meaning per surface family, so a red date and a
red flag never argue about what red means.

| Hue | Meaning | Tokens |
|---|---|---|
| accent (the system accent) | selection, the lead task's row, primary actions, links | `accent`, `selectionFill` |
| red | overdue, P1 priority, errors, destructive actions, the calendar now-line | `overdue`, `priorityHigh`, `error`, `destructive`, `nowIndicator` |
| orange | due today or soon, P2 priority, warnings | `dueSoon`, `priorityMedium`, `warning` |
| green | completed, success, a habit finished today | `done`, `success` |
| secondary gray | neutral counts, cancelled, someday, blocked, low priority, section leaders | `neutral`, `cancelled`, `someday`, `blocked`, `priorityLow` |
| pink | mood in reviews | `mood` |
| yellow | energy in reviews | `energy` |

Rules that follow from the table:

- Counts and section leaders are neutral. A "3 planned" chip, a "Deferred"
  header, or a "Snoozed" header never borrows a status hue.
- Warnings appear in Settings, diagnostics, editors, and banners, never on a
  task row. The one row use of `dueSoon` is the due date itself: orange when
  the deadline is today or tomorrow, red (`overdue`, with its own glyph) once
  the day has passed, secondary otherwise — the same rule as the inspector's
  Due row.
- The accent is the platform accent (`Color.accentColor`). There is no second
  brand blue; `Palette.accent` is an alias so call sites read semantically. On
  watchOS, where `Color.accentColor` renders as a light grey without an asset
  catalog, `Palette.accent` is the system blue that iOS shows by default.
- Entity identity colors are the only non-semantic colors: a list's, habit's,
  or calendar's own tint, chosen by the user as a hex value
  (`Color(lorvexHex:)`), and the fixed destination tints of the smart lists and
  workspaces (`Palette.Destination`). Identity colors appear on icon tiles and
  calendar event blocks, never on status text or on a task placed on a
  calendar. A habit without a chosen color takes
  a fallback hue from `Palette.identityHues` by a stable hash of its id
  (`LorvexHabitPalette.baseColor(for:)`), so it shows the same color on every
  device; the fallback hues exclude green so an unfinished habit never reads
  as done.

- The empty part of a tinted progress display (a momentum ring's track, a
  milestone bar's rail) never uses a fixed alpha. It reads
  `Palette.trackOpacity(for:)` with the current `colorScheme`, because one
  alpha that reads as a pastel on a light card all but vanishes on a dark one.

- A habit's check-in ring is a control, so its track is the neutral
  `.tertiary` style on every platform, not a faded version of the habit's hue:
  a faded pale hue sits near 1.3:1 against its row, too faint to read as
  something to tap. The arc carries the habit's hue, and a completed ring
  turns green with a check.

- The tertiary style (`.tertiary`) is for what a reader can skip without
  losing anything: the "·" between facts, disclosure chevrons, drag handles,
  a cancelled task's circle, and the days outside the month a calendar shows.
  It measures under 2:1 on the page ground, where text reads as disabled.
  Anything that names, counts, times, or explains — a section label, a row's
  time or duration, an empty state's hint, the ends of a scale — is at least
  `.secondary`, and so is a control drawn as a glyph alone (an icon button, a
  hollow rating step), including one a hover reveals.

- Placeholder text drawn by hand over an editor (the notes editors') takes
  `Palette.placeholderText`, the platform's own placeholder color, so it
  matches the placeholder of the system field beside it. Under Increase
  Contrast the system darkens that color to about 4.5:1 on a card, where
  `.tertiary` stays near 1.8:1.

- Something the clock has cleared (a finished meeting, a task done earlier
  in the day, a day the week has left behind) steps back without losing
  legibility. Its marks fade to `Palette.pastMarkOpacity` (a day's load
  strip, an event's color bar or glyph, a task's circle), and a primary title
  or day number takes the secondary style. The item never fades as a whole:
  secondary text at that opacity measures under 2:1.

- Inside an iOS `List` section header, content takes the header's own color.
  The header already draws in the secondary style, so a hierarchical
  `.secondary` or `.tertiary` inside it compounds: a count beside the title
  would measure about 2.3:1 and a fold chevron about 1.3:1.

- A rating scale's unchosen steps are hollow rings in `.secondary`, and its
  chosen steps fill with the accent (`LorvexDotScale`), so the empty scale
  reads as five places to tap rather than five faint marks. A pale fill for
  the unchosen steps sits near 1.25:1 against the page and looks disabled,
  and the accent at a reduced alpha reads as half-chosen; a pointer preview
  turns the hovered rings accent instead of filling them.

- A button that is a plain row in a `List` or `Form` states its color for the
  whole row, because SwiftUI colors the title from state it never applies to
  the `Label`'s icon. The `destructive` role reddens the title alone, and
  disabling a row drops its title to the default text color while the icon
  stays accent-colored, so either one renders the row in two colors. A
  destructive row (Cancel, Delete, Erase) carries
  `.mobileDestructiveRowStyle()`; a row that can be disabled carries
  `.mobileAccentRowStyle()`. `.tint` does not reach the icon and is not an
  alternative. Swipe actions, context menus, and `Menu` items render both
  halves already and take no extra modifier.

- A destructive button in the bordered style (a detail page's or a batch
  bar's Delete) carries `.mobileDestructiveBorderedStyle()`. The iOS root view
  tints the app with the accent color, and in the bordered style an explicit
  tint outranks the `destructive` role, so the button otherwise draws blue,
  identical to the ordinary action beside it.

- Text inside an editable `TextField` takes an explicit `Color`, not the
  hierarchical `.primary` / `.secondary` shape styles: on macOS both of those
  resolve to the same mid-grey inside a field, so a state expressed through
  them renders as no state at all and the ordinary text sits below full
  contrast.

- An inline-editable row states its status with a control and a text colour,
  never with struck-through text. `.strikethrough` does not reach an editable
  `TextField`'s content, and swapping in a `Text` until the row is clicked
  would cost click-to-edit and Tab traversal.

- A direct-manipulation grip (a block's resize edge, a row's drag handle) is
  drawn for the hovered or selected element only. Its transparent hit area is
  always live, so the cursor and the gesture do not wait on the grip; a grip
  left permanently on every element reads as a stray rule rather than an
  affordance, and a dense surface fills with them.

- A progress bar appears only once there is progress. At zero it is a flat
  tinted capsule that restates the count beside it and reads as a loading
  placeholder; from the first completion on it shows a proportion no count line
  conveys as fast.

- De-emphasis softens a label, never its number. A count greyed alongside its
  label reads as unavailable rather than as secondary, and every count the app
  shows is real data.

- A section header counts its rows only while the section is folded. An open
  section's rows are their own count, so an always-open section's header
  carries none and a folding one drops its count when it opens; VoiceOver
  still hears the count on a folding header either way. A count that is part
  of a sentence ("3 more today") is copy, not a badge, and stays.

- A hue is never the only carrier of a state. Done, cancelled, someday,
  overdue, and sync states carry a glyph or a word beside their color. The one
  state a row tells by tint alone is a task's priority, so while the system's
  Differentiate Without Color setting is on, an open task's circle marks it
  inside the ring (`LorvexTask.Priority.circleGlyph(differentiating:)`: an
  exclamation mark for P1, an arrow pointing down for P3, the plain ring for
  P2). Every task row, detail page, widget row, and watch row draws the circle
  through `LorvexTaskStatusCircle` or the same glyph function. A view reads the
  setting with `@LorvexDifferentiateWithoutColor`, not the environment key
  itself: SwiftUI exposes the key read-only, so the wrapper adds the DEBUG launch
  argument `-lorvexDifferentiateWithoutColor`, the only way a headless capture
  can show these cues (`LORVEX_TOUR_EXTRA_ARGS` on the Mac tour,
  `LORVEX_SIM_EXTRA_ARGS` on the iOS captures).

Severity for system state (Settings status rows, diagnostics, permissions,
sync) uses `neutral`, `success`, `warning`, `error`.

The one decorative color family is `Palette.Sky` (morning, day, evening, sun):
the time-of-day wash at the top of Today and the sun on the day arc. It never
carries status, so it sits outside the table above (§8).

## 2. Surfaces

| Token | macOS | iOS / iPadOS |
|---|---|---|
| `Palette.groupedBackground` | window background | `systemGroupedBackground` |
| `Palette.card` | `controlBackgroundColor` | `secondarySystemGroupedBackground` |
| `Palette.insetFill` | secondary at 8% | secondary at 8% |
| `Palette.hoverFill` | secondary at 12% | unused (no pointer hover on touch) |
| `Palette.selectionFill` | accent at 15% | accent at 15% |
| `Palette.sidebarSelectionFill` | `unemphasizedSelectedContentBackgroundColor`, for sidebar rows outside the source list | secondary at 16% (unused) |
| `Palette.separator` | `separatorColor` | `separator` |

Two panel chromes exist and every panel uses one of them:

- `.lorvexCard()` — an elevated card: `card` fill, `Radius.card`, a hairline
  `separator` stroke, no shadow. Cards are flat on both platforms; depth comes
  from surface contrast, which is how macOS 26 and iOS 26 grouped surfaces
  read.
- `.lorvexInsetPanel()` — a nested group inside a card or a workspace column:
  `insetFill` at `Radius.m`, no stroke.

No surface is raised. The lead task is a row of Today's list whose `card`
fill is tinted with the accent, so it stands out without leaving the list the
user reads top to bottom (§8).

Floating surfaces (toasts, celebrations, the command palette) use
`lorvexFloatingGlass`, which is `glassEffect` on macOS 26 / iOS 26.

## 3. Shape and spacing

| Token | Value |
|---|---|
| `Radius.s` | 6 — chips, row selection, small controls |
| `Radius.m` | 10 — inset panels, editors |
| `Radius.card` | 12 on macOS; 26 on iOS and iPadOS, the corner of an inset-grouped list section; 16 on watchOS |
| `Spacing.xxs / xs / sm / s / m / l / xl` | 2 / 4 / 6 / 8 / 14 / 22 / 32 |
| `Spacing.cardPadding` | 16 |
| `TextColumn.clockTime` | 60 on macOS, 72 on iOS and iPadOS — a column holding the widest clock time in `secondaryText`; views scale it with the text |

Padding and corner radii in views come from these tokens. A literal number is
allowed only for geometry that is not spacing (column widths, hour-row height,
icon sizes), and `CalendarMetrics` owns the calendar grid's numbers.

## 4. Typography

Tokens live in `LorvexDesign.Typography` and are built on Dynamic Type styles.

| Token | macOS | iOS / iPadOS |
|---|---|---|
| `screenTitle` | `.title` semibold | `.largeTitle` bold (system navigation titles where possible) |
| `detailTitle` | 17pt semibold (an inspector's task or habit title) | `.title2` semibold (the item a detail screen is about) |
| `sectionHeader` | `.title3` semibold | `.headline` |
| `primaryText` | 14pt | `.body` |
| `primaryEmphasis` | 14pt medium | `.body` semibold |
| `secondaryText` | `.callout` | `.subheadline` |
| `tertiaryText` | `.subheadline` | `.footnote` |

Row titles use `primaryText`, metadata uses `secondaryText` or `tertiaryText`,
and card or section titles use `sectionHeader`. Fixed point sizes
(`.system(size:)`) are reserved for glyphs that scale with a container (an icon
tile's symbol, a progress ring's numeral) and for the DEBUG snapshot renderers.

Words stay whole at every text size. A column sized for text grows with it
through `@ScaledMetric`, relative to the style the column holds: the time
column of a timeline row and of an assistant change, the week review's day
column, the calendar's hour gutter, the rating dots, and a task row's circle,
which grows with its title3 glyph. An icon tile (`MobileIconTile`) grows with
the body text from its design size up to 48pt, so a row's leading tile keeps
in proportion with the row's text; a tile designed at 48pt or larger keeps its
size. A task title, and an agenda row's title and facts, take up to two lines,
and as many as they need at accessibility sizes
(`lineLimitUnlessAccessibilitySize`). A task row's metadata line keeps to one
line, its estimate and tags dropping whole from the end, until the
accessibility sizes, where it wraps between its items instead. A label, a
duration, or a date range keeps its words together where the text around it
wraps (`lorvexUnbreakable`), a range breaks only after its dash, and a dot
stays with the fact before it (`lorvexDotJoined`), so no line starts with one.
A facts line (`LorvexFactsLine`) breaks between whole facts; when two lines
cannot hold them, each fact takes a line of its own, and only a fact wider
than the line wraps, between its words. A row that sets a time or a day in a
column beside wrapping text stacks it above the text from `.xxLarge` up
(`DynamicTypeSize.stacksTimeColumn`), where a phone-width row can no longer
hold the column, the text, and a trailing value side by side; a dot then sets
the time off from its duration, which would otherwise read as one run of
numbers. A pair of buttons moves onto two lines when it would not fit on one
(`ViewThatFits`). At accessibility sizes a segmented picker becomes one row
per choice, and Today's strip of habit rings becomes one row per habit, since
its columns would hold a word a line. A grid with fixed geometry stops its
text at `.xxxLarge`: the iPhone day grid, where a block sets its start time
under its title only when both fit, and the habit heatmap, whose month labels
would otherwise outgrow their months' columns. A label and its value that
share a line (a milestone and its rung, a stat and its reading, a review task
and its due date) move onto two lines, or become rows, before either breaks
inside a word.

Text the user or the assistant wrote (a task's title and notes, a checklist
item, a list, habit, or memory, an event, a briefing, a review summary) enters
through `Text(userContent:)`, or through `userContentTypesetting(_:)` when the
text is built another way, such as in the serif voice. SwiftUI typesets by the
interface language's rules, and Japanese line breaking splits Latin text
between a letter and a digit ("Review the Q" / "3 planning doc") and, at
narrow widths, inside a word. So under a Japanese interface written text with
no Chinese, Japanese, or Korean characters is typeset as English. Text with
those characters, and the app's own copy, keep the interface's typesetting.

The Home Screen and desktop widgets set their text in their own scale,
`WidgetType` in `LorvexWidgetViews`. A Mac desktop widget gets about an
iPhone widget's canvas, but macOS text styles run smaller (caption, caption2,
and footnote are all 10 points), so each role names a style per platform, a
step or two apart, and a widget keeps the same proportions on both:

| Role | iOS | macOS |
|---|---|---|
| `label`: the widget's name | `.footnote` semibold | `.callout` semibold |
| `title`: the lead task, what is left of the day | `.headline` | `.title3` semibold |
| `display`: the large widget's lead task | `.title3` semibold | `.title2` semibold |
| `row`: a task row's title | `.subheadline` | `.body` |
| `meta`: a time, state, or estimate | `.footnote` | `.subheadline` |
| `foot`: the foot line and the stale capsule | `.caption` | `.subheadline` |
| `tile`: a habit tile's name | `.caption` medium | `.subheadline` medium |

The large widget's briefing is the assistant's serif voice
(`widgetBriefing`). A task row is as high as its circle's hit target, 30pt at
the default size and growing with the row's text, so the circles stack with no
gap. Where a family cannot hold every row, it shows fewer and its foot line
counts the rest ("4 more today"); on the small family the foot line, and then a
secondary fact such as the work left, gives way before a title loses a line or
the widget's name is cut. The Lock Screen families keep the system's accessory
styles.

## 5. Components

Shared components live in `Sources/LorvexCore/Support` when both platforms use
them and in the platform module otherwise.

| Component | Role |
|---|---|
| `LorvexChip` | the one tinted capsule for status pills, count badges, and signal chips: `tertiaryText`, 12% tint fill, tint foreground |
| `.lorvexCard()` / `.lorvexInsetPanel()` | the two panel chromes |
| `LorvexListIconView` (macOS) / `MobileIconTile` (mobile) | the colored rounded-square icon tile that leads catalog rows, destination rows, and section leaders |
| `LorvexEmptyStatePanel` (macOS) / `MobileEmptyState` (mobile) | calm empty states: a tinted glyph tile, a title, one line of copy, at most one action — and none when the toolbar ＋ already owns it, in which case the copy points at the ＋ (on mobile the tab bar holds a second ＋ that opens task capture, so a row whose copy names the toolbar ＋ sets `pointsAtToolbarAdd` and the copy's ＋ is drawn in the accent color the toolbar ＋ wears); `MobileEmptyState.search(text:)` is the no-results row for `.searchable` lists; never a bare `ContentUnavailableView` inside a `List` |
| `WorkspaceTaskSectionHeader` (macOS) | section leader with a neutral tint by default |
| `WorkspaceHeaderIdentity` + `WorkspaceHeaderGlyph` (macOS) | a workspace's large title and its caption, led by a glyph centered in a 23 pt column (`WorkspaceHeaderTitleMetrics.glyphColumnWidth`, as wide as the widest workspace symbol on a 2x display; a list's own wider icon widens it), so every workspace's title starts on one edge whatever its symbol's width. Today's date line, which has no glyph, insets by `WorkspaceHeaderTitleMetrics.titleInset` to start on the same edge |
| `LorvexTaskRow` (macOS) / `MobileTaskRow` (mobile) | the single task row: completion circle, title, metadata line, status chips |
| `.lorvexCalendarTaskSurface(...)` | the one shape a task wears on a calendar — a timed block, an all-day pill, a month chip — on every platform: a faint accent wash inside a hollow dashed outline, where an event wears its calendar's solid fill and leading rail; running or selected firms the outline, done fades it. Blocks and pills also lead with the task's completion circle |
| `LorvexIconButton` (macOS) | the one icon-only button: a semibold secondary glyph in a 28 pt circular hit area that fills faintly on hover, with its label as tooltip and VoiceOver name; inspector pin and close (`InspectorCloseButton`), pager arrows, and remove buttons in editors |
| `InspectorColumn` + `InspectorPanel` (macOS) | the trailing inspector's content column (top-leading, at most 500 pt wide, shared insets) and the faint grouped card each of its sections sits in; the header's panel draws no card, and inside a popover no panel does. The task and habit inspectors are both built from them |
| `InspectorProperties` (macOS) | a task's or a habit's set fields as rows (icon, field name, value) with dashed "+ Field" additions; a row opens its field's popover editor, or a native menu for short fixed choices |
| `InspectorGlyphLabelStyle` (macOS) | the label of an inspector panel's title or reading (a habit's Progress, History and By Weekday titles and its Progress readings, and the task inspector's Checklist and Notes titles): the glyph centered in a column as wide as the widest symbol of its face (`.inspectorPanelTitle` 20 pt, `.inspectorReading` 16 pt), on the title's first baseline, so sibling titles start on one edge whatever their symbols' widths |
| `InspectorActionChip` (macOS) | the face of an action in an inspector's header row: a small semibold symbol and an optional short title in the primary color on a quiet fill, as tall as the row's tallest control (the row sizes itself to its content); the task inspector's Start, Defer and overflow controls and the habit inspector's overflow control wear it, a menu through the button menu style with the plain button style and no indicator; `isActive` draws a toggle's on state in the accent |
| `TaskDetailChoiceRow` (macOS) | a one-click choice in an editor: a title, an optional trailing detail, a hover fill, and an accent title with a checkmark when it is the current value |
| `MobileFieldChip` (mobile) | a one-tap choice in a field editor (the quick days, the length presets): a neutral `.bordered` capsule with primary text, and the system `.borderedProminent` accent fill while it names the field's current value, with the selected trait for VoiceOver; the weekday pills of a habit's cadence wear the same on and off look |
| `TaskDetailMonthCalendar` (macOS) | the month grid of every day field: round 32 pt day cells, the chosen day filled with the accent, today's number accent-colored, neighbouring months dimmed, `LorvexIconButton` arrows |
| `CreationSheetLayout` + `CreationSheetHeader` (macOS) | the create and edit sheet: a small centered action title, the thing being made as a live preview (icon tile in its color, opening the icon and color picker; the name typed beside it), the remaining fields as a grouped form, then Cancel and the confirm button |
| `MobileCreationHeader` (iOS) | the first row of the list and habit sheets, with no card behind it: a 56 pt live preview tile in its color with a pencil badge that opens the color and icon choices in a popover (`MobileIconColorPicker`), the name typed beside it in the detail-title face (wrapping rather than truncating), and a second line for the description or encouragement; the remaining fields are grouped sections below. At accessibility text sizes the tile sits above the text, and the badge stays at its default size. A create sheet puts the cursor in the name as it opens |
| `mobileSheetTitle` (iOS) | the inline title of every sheet with a Cancel button: the system's headline size while it fits between the two bar buttons, the page-label size when only that fits, and two lines of the page-label size otherwise, in a title area two lines tall and capped at the default text size, so a long translation is never cut short with an ellipsis; the navigation title is still set for VoiceOver |

Buttons use the system styles. On macOS the workspace controls are
`.bordered` / `.borderedProminent` (glass on macOS 26); segmented choices use
`Picker` with `.segmented`. Custom button and segmented chromes are not
introduced.

A sheet or composer that makes something new confirms with Create (a habit,
a list, an event, a memory); quick add confirms with Add, since it adds each
typed line as a task. One that changes an existing item confirms with Save,
or with Update in the Mac's memory composer, which creates and edits in one
card. Cancel is plain and the confirm button prominent.

On iPhone and iPad a create or edit sheet titles itself inline, between
its Cancel and its confirm button, so the title does not take a line of
a short sheet's height. A dense form (a task, a habit, an event, a repeat
rule) opens at full height; a form of a few fields (a list, a memory)
opens at a half-height detent that expands. In a regular-width window
(iPad) these sheets show as cards, and the half-height detent is a card
about 360 pt tall while the keyboard is up. Quick add, whose hint under
the notes runs to several lines in a tall script such as Telugu, takes a
card height of its own in place of that detent: 480 pt at the default text
size, growing with Dynamic Type and limited by the room above the keyboard.
The setup wizard keeps its buttons in a safe-area bar, so a row that
scrolls beneath them fades out instead of being cut at their edge.

A field editor (a popover from a property row) holds only its field and follows
four rules. Presets come first and "Custom…" last, so the common answer is one
click. There is no empty state: an editor with nothing set shows the ways to
add one directly. An editor never opens a second popover; a search or a form
it needs is embedded in it. Its background is the opaque window background.

An editor's placeholder asks the question its panel wants answered, and the
panel's subtitle carries the nudge to answer it. A placeholder that repeats the
header tells the writer nothing. The accessibility label keeps the header word,
so VoiceOver still announces the field by its name.

An action that belongs to a whole section ("Move All to Tomorrow" over a
review's open tasks) sits at the trailing end of the section's label line as
plain accent text in the label's size, with no capsule or bordered chrome; a
capsule beside a quiet label outweighs the rows it acts on. Each row's own
version of the action is offered where rows offer actions: on hover on macOS,
and in the context menu and as a VoiceOver action on every platform.

Settings copy that explains a control is a `Section` footer, never a
secondary-text row inside the card. A control that needs its own explanation
gets its own group so the footer sits directly under it, and a group whose
only row already names the setting carries no header.

A settings row that holds a value or a switch is plain text, with no leading
glyph: the control at its trailing edge already says what kind of row it is,
and a column of icons beside toggles reads as decoration. Only a row that
performs an action or leaves the app (Delete iCloud Data, the About links)
leads with a glyph. The macOS settings panes keep their sidebar icons, which
name panes rather than rows.

Every settings control sits at its row's trailing edge, action buttons
included. An action row names what it acts on with its glyph and title, and
its button ("Choose File…", "Delete…", "Copy") ends the row; a button never
takes a row of its own at the leading edge, where it leaves the rest of the
card empty. An action that belongs to the rows above it (Open iCloud Settings
under the account) is a row holding only that button, at the trailing edge. A
row that opens a sheet (Acknowledgments) ends in a chevron, and the whole row
takes the click. A set of choices that needs more than one line (the export
categories) is a grid spanning the card, a column per group with the group's
name on top, rather than a flow from the leading edge. A row's glyph is
centered in a column of one width (`SettingsRowLabelStyle`), so the titles of
a group start on one edge whatever their glyphs' widths.

The macOS Settings window has one toolbar row, which holds the traffic lights
and names the current pane, as System Settings does; the pane's form starts
directly under it, with no header of its own.

A glyph that labels a fact (a task row's due date, estimate, or repeat, a
dependency's start or due day) sits `Spacing.xs` (4 pt) from its text. Glyphs
that fill their box, such as a badge or a calendar, look attached to the
word at 2–3 pt.

A pair of actions that shares a line (a memory's Edit and Delete, a review
section's Move to Tomorrow beside its label) moves onto two lines at
accessibility sizes, each action keeping its full label, through an
`AnyLayout` that swaps the `HStackLayout` for a leading-aligned
`VStackLayout`.

A menu names its choices in words: a priority reads "High", "Medium", or "Low", never
"P1". A group of two or three choices sits inline in its parent menu,
separated by a divider or titled with a `Section`, instead of a nested submenu
that hides two items behind an extra hover.

## 6. Platform conventions

- **macOS.** The sidebar names destinations by what the user does there:
  Today, Calendar, All Tasks, Review, Habits, then the user's lists. The
  shared English names (Tasks, Reviews) stay as command-palette aliases.
  Memory sits in the sidebar footer beside Settings, and on ⌘6. The title bar
  text is hidden; each workspace names itself with a large in-content title
  (subtitle and digest beneath it) while its date navigation, mode pickers,
  and actions ride in the unified window toolbar.
  Actions sit at the toolbar's trailing edge, except in All Tasks and Memory:
  those two show the toolbar search field, which holds the trailing edge, so
  their actions sit at the leading edge. The window owns that one field and
  only changes its prompt with the workspace; a workspace never attaches a
  toolbar search of its own, because two at once make the toolbar insert a
  duplicate item. Find (⌘F) focuses that field, and
  from any other workspace opens All Tasks across every list to search there.
  Sidebar is a `List` with `.sidebar` style.
  Content lists draw rows on the window background with `selectionFill` for
  the selected row and `hoverFill` on hover. Deployment target macOS 26.
- **iPhone and iPad.** Tab bar: Today, Calendar, Tasks, Review, and a round +
  that opens capture from every tab (iPadOS draws the bar floating at the top
  of the window). Settings is a toolbar gear on Today; Memory and Habits live
  on the Tasks home. Today is the calm page; on iPhone its day strip opens the
  schedule as a sheet, and at regular width (iPad) the page keeps a readable
  column with the schedule standing beside it as a pane. Other screens lay
  the same components out for the width, never a stretched phone.
- **Right-to-left languages and numbers.** Every surface lays out mirrored
  under Arabic, so anything that points uses the semantic `forward` /
  `backward` SF Symbols (`chevron.forward`, `arrow.forward.to.line`,
  `arrow.uturn.forward`), which mirror with the layout. A fold header's
  chevron is `LorvexDisclosureChevron`: it points along the reading direction
  while folded and down while open. Paging controls bind their shortcut with
  `lorvexStepShortcut`, so ⌘ plus the arrow key always points the way its
  chevron does, mirrored in a right-to-left layout. A progress ring's arc is
  `LorvexProgressArc`: it starts at twelve o'clock and fills with the reading
  direction, counterclockwise in a right-to-left layout, as the system's
  circular gauges do. A fraction or a count set beside
  other text is one `Text`, never pieces in an `HStack`, which a right-to-left
  layout reverses ("8/3" for three of eight).
  Numbers shown to people render through the locale, which picks the digits
  (Arabic (Saudi Arabia) writes "١٢", Persian "۱۲"): `Text(value, format:
  .number)`, `LabeledContent(_:value:format:)`, or `value.formatted()` where a
  view takes a `String`. `"\(value)"` built into a plain `String` and
  `Text(verbatim:)` always write ASCII digits. Stored forms (day keys, `HH:mm`,
  identifiers, export files) stay ASCII. Typed numbers go through
  `LorvexNumberInput`: a number field starts with `text(for:)` and reads
  with `integer(from:)`, which accepts the digits of every script, since the
  Arabic number pad types Arabic-Indic digits and Chinese and Japanese input
  methods often type full-width ones.
- **watchOS.** The same status colors and tiles at glance scale;
  no new tokens.
- **Widgets.** The same colors and tiles, with the widgets' own type scale
  (§4). A widget opens with its name in the accent ("Today", the list a
  configured Today widget shows, "Habits", "Progress"), except where the lead
  task's ring or the all-clear seal stands at the top-left of the small Today
  widget. A task's circle completes it in place and takes its priority's
  tint; the lead's ring fills while its time runs. Widget buttons are
  `.plain`: on macOS the borderless style is an AppKit control, which WidgetKit
  cannot draw, so a widget would show its unsupported-view placeholder.

## 7. Enforcement and QA

- `script/verify_design_tokens.py` fails the gate when a view under
  `Sources/LorvexApple`, `Sources/LorvexMobile`, `Sources/LorvexWatch`,
  `Sources/LorvexWidgetViews`, `Sources/LorvexWidgetKitSupport`, or
  `Sources/LorvexCore` (`Models`, `Support`) names a raw system hue in a color
  position, uses `.font(.system(size:` outside the documented exceptions,
  passes a numeric corner radius, names a fixed-direction glyph
  (`chevron.left`, `arrow.right.to.line`) where a mirroring `forward` /
  `backward` form belongs, or trims a circle into a progress arc instead of
  using `LorvexProgressArc` (§6). The exception list is in the script and is
  the complete inventory of intentional literals.
- Visual verification is part of every UI change. iOS runs headlessly in the
  simulator (`-lorvexSeedSampleData -lorvexOpenURL lorvex://tab/<tab>` plus
  `simctl io screenshot`); macOS uses the DEBUG `--ui-preview` mode, which
  renders the real windows over a seeded in-memory core.
- Widgets render headlessly too. `script/widget_gallery_macos.sh <outdir>`
  draws the Mac desktop widgets at their desktop sizes (small 162pt, medium
  342×162pt, large 342pt square, inside 16pt margins), light and dark, from the
  DEBUG widget gallery's sample day, in an offscreen window. The iOS gallery is
  the `widgets`, `widgets-large`, `widgets-lock`, and `widgets-more` routes of
  `script/ios_sim_screenshots.sh`, which pins the simulator to the default text
  size; a launch argument picks another size to check a widget still fits.
  Both galleries render through SwiftUI, so neither can show WidgetKit's
  unsupported-view placeholder; `script/verify_source_hygiene.py` keeps the
  AppKit-backed button style, and text styles outside `WidgetType`, out of the
  widget views.
- Reading a macOS tour capture: the tour never activates the app, and an
  inactive window draws its toolbar controls and its sidebar selection in grey.
  Those controls are enabled and the selection is tinted in use; grey in a
  capture is the window state, not a disabled control.
- The tour's `@AppStorage` reads the preview's own wiped-on-launch defaults,
  not the developer's, so a capture round never inherits an expanded section or
  a table-mode toggle from an earlier one. The tour opens the Tasks History
  disclosure there, because it is collapsed by default and a tour that points
  at nothing can never reach the completed and cancelled row treatments.
- A tour stop stays on screen until `script/ui_tour_macos.sh` acknowledges
  it. A settle loop that outruns the app's own dwell time otherwise
  photographs the next workspace and saves it under the previous one's name,
  and the script warns when a round produces two byte-identical PNGs — the
  only visible trace of that failure when captures are reviewed one at a time.
- A row whose content shares a column with a scrolling region is laid out from
  that region's width, not the window's. A pinned header above a `ScrollView`
  keeps full width while a visible scroller narrows the content under it, so
  the two drift apart; the week grid suppresses its scroller for this reason.

## 8. The calm page grammar

Today, and the pages built after it, compose from a small grammar instead of
stacked cards. The parts live in `Sources/LorvexCore/Support/LorvexCalmComponents.swift`
and are presentational: callers pass localized strings and actions, so macOS,
iPhone, and iPad share them with their own copy tables.

| Part | What it is | Component |
|---|---|---|
| Ground | the page background itself; the header, the day strip, and the wells sit directly on it | — |
| Task list | every task the day holds, in one list with no section headers; a timed task's time leads its metadata line, status chips ("Until 3:00 PM", "Started", "Pushed 3 times") sit under its title, and the lead task's row is tinted with the accent | `LorvexTaskRow` (macOS), `MobileActionTaskRow` (iOS), `LorvexTaskRowChip` |
| Labels | a row's estimate and tags on one line; the last ones drop whole when the line runs out of room, never cut to "w…" | `LorvexWholeLabelsLine` |
| Ring | a task's circle grown into a timer; it fills as a running time passes, and is also the Done control (the menu bar panel, the task detail) | `LorvexTaskRing` |
| Well | one question for the user with one verb: today is overbooked ("Move to Tomorrow"), or suggested times wait ("Use These Times"); the button moves under the words where they would not fit beside it | `LorvexDecisionWell` |
| Timeline row | the day as rows in a schedule pane: a time, a marker (a task's circle, a hold's thin bar), a title, a quiet duration; the lead task's row tinted; a red marker where the clock sits | `LorvexTimelineRow`, `LorvexTimelineNowMarker` |
| Label | a quiet group label on the ground in the secondary style, with an optional trailing note | `LorvexPageLabel` |
| Strip | the day drawn to scale (iPhone and iPad Today) | `LorvexDayStrip` |
| Sky | the time-of-day wash; the sun arc takes the list's place on an empty day | `LorvexSkyWash`, `LorvexSunArc` |

Working pages and reflective pages speak differently. Today is a working
page, set entirely in the system face: the date in `Typography.pageTitle`, a
line of facts in secondary text, section titles over task lists in
`Typography.listSection`, and the assistant's briefing in `Typography.briefing`
at body size, marked by the sparkles glyph rather than by a typeface, so a long
paragraph, and Chinese text, stays easy to read. The reviews are reflective
pages, and there the assistant speaks in New York: `SerifVoice.pageSentence`
for the sentence that opens the page. `SerifVoice.assistantSecondary` (serif
italic) marks a reason the product inferred wherever it appears, such as a
proposed schedule's rationale. Text enters the serif voice through
`Text(_:serifVoice:)`, which on macOS sets a string's Chinese runs in Songti:
New York's own fallback to Songti lays the full-width marks out one and a half
ems wide, so a Chinese sentence would read as if a space followed every stop.
Chinese stays upright where the Latin aside leans. A sentence in the serif
voice is always something the product inferred, never something the user
typed. Counts are numerals on every page, "1 task" as well as "6 new tasks
came in", so Today's facts line and a review's sentence count the same way.

The day model behind Today is `LorvexCalmToday` (`Sources/LorvexCore/Support`).
It holds Today's whole list in Today's order — started tasks first, then by
priority and due date — picks the lead among them (`TodayLead`: a task whose
saved time contains the clock, else a started task, else the next saved time
today, else none; calendar events are never the lead), and writes the facts line and the overbooked decision
from the same inputs. The page lists the whole thing with no section headers:
an overdue task's due date reads red and a started task carries its own chip,
so each row already says what a header would. Nothing the user or the
assistant put on today is folded away; only Done (on request) and the
assistant's change log (by default) fold, because they are records rather
than work. A task pushed off three or more times carries a "Pushed N times"
chip. The schedule beside the list (on iPhone, a sheet opened from the day
strip) draws only what has a time: calendar holds and the day's timed tasks
(`LorvexTodayTimeline.timedItems`).

While day hours remain and the day's estimated work exceeds the free
working time left, one well says so ("About 6 hr of work, 4 hr free") and
offers to move the named tasks to tomorrow. With nothing that can move on its
own, it states the fact alone. This is the one decision Today asks about the
shape of the day; nothing else about capacity asks for attention. The
facts line under the date leaves the estimated work out while this well
states it, so the page names the figure once.

Suggested times are a draft until the user answers them. On iPhone they wait
in a well whose button opens the schedule sheet; on iPad they stand in the
schedule pane; on macOS they stand at the top of the schedule section in
Today's column. Either way the suggestion is headed "Suggested Times"
above the saved one, which reads "Current Schedule" while the suggestion
waits, and "Use These Times" is its prominent button; "Dismiss" discards it
without changing the day. On every platform the two answers lead the
suggestion (beside its title on macOS), where a long proposal cannot push
them off screen. Tasks that did not fit get "Move to Tomorrow", so a full day
never ends in a dead-end list; it follows the rows that say what did not fit.

The grammar reaches the glances too. The Today widget and the macOS menu bar
panel draw the same lead task with the same ring and, while its time runs,
the same clock line (`WidgetTodayGlance` mirrors `LorvexCalmToday`'s choice of
the lead from the widget snapshot), then the next lines; the panel sets its
sentence in `SerifVoice.panelSentence`, the serif voice one step smaller than
a page.

On macOS a task's set fields are rows in the order a person plans: an icon,
the field's name, its value ("When — Today, 9:45–10:45 AM", "Due — Thursday").
Normal priority is the default and earns no row. Unset fields follow as dashed
"+ Reminder" capsules. A row opens only that field's editor, and every editor
follows the same rules: presets first and "Custom…" last (priority and repeat
are native menus, whose "Custom…" opens the full editor in place); no empty
state, because an editor with nothing set already shows how to add one; no
popover opened from a popover; an opaque window background; and icon-only
controls are `LorvexIconButton`. Day fields share one picker: presets chosen
per field (Planned and Due offer Today, Tomorrow, This Weekend, and Next
Monday; Hide until offers Tomorrow, Next Monday, and Next Month), then a month
calendar of round day cells. On iPhone the fields still read as one sentence
of words ("Today for 90 min, due Thursday. In Offsite 2026, high priority."),
each word opening its own picker.

Quick-add reads the same words out of the typed line (`LorvexCaptureParser`)
and previews them under the field before Return creates the task. Every
surface names a day through `LorvexDayPhrase`: "today", "tomorrow", or
"yesterday" within a day of the logical today, capitalized only where the word
opens a sentence or stands alone; the weekday within the coming week; a date
beyond, with the year only when it is not this year. Inside the iPhone
sentence, a deadline on the planned day reads "due the same day" rather than
naming the day twice; a standalone Due row always names its day. A deadline
that passed before yesterday says how late it is ("Sep 20 · 9 days late").

