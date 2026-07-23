# Apple Accessibility Matrix Audit

Last verified: 2026-07-10  
Code snapshot: `cc8c2c925cb30a36091956842b435f59edefe2ae`

This is a static source audit of the Apple UI, not a claim that Lorvex has
passed an Accessibility Inspector or physical-device audit. It covers macOS,
iPhone, and iPad because App Store Connect accessibility declarations are made
per platform and must hold for every common task on the applicable devices.

## Apple Contract

Apple's 2025 accessibility nutrition labels cover VoiceOver, Voice Control,
Larger Text, Dark Interface, Differentiate Without Color, Sufficient Contrast,
Reduced Motion, captions, and audio descriptions. Apple says to evaluate every
common task on every supported device before claiming a feature. Larger Text is
not currently an available Mac label. The labels are initially voluntary, but
Apple says they will become required over time; after publishing a label it can
be updated but not unpublished.

Apple's audit guidance also makes source inspection insufficient:

- test every screen and complete every common task with assistive technology;
- test on physical devices with VoiceOver, Voice Control, Switch Control,
  Dynamic Type, contrast, button shapes, and Reduce Motion settings;
- use Accessibility Inspector and automated accessibility audits to find
  missing descriptions, small hit regions, contrast failures, clipped text,
  incorrect traits, and parent/child/action problems;
- test Larger Text at at least 200 percent and keep useful content from being
  unnecessarily truncated;
- ensure Full Keyboard Access can operate the whole iPad experience by
  keyboard, not just the controls that happen to receive focus.

Primary sources:

- [Overview of accessibility nutrition labels](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/overview-of-accessibility-nutrition-labels/)
- [Manage accessibility nutrition labels](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/manage-accessibility-nutrition-labels/)
- [Evaluate your app for accessibility nutrition labels (WWDC25)](https://developer.apple.com/videos/play/wwdc2025/224/)
- [Performing accessibility audits for your app](https://developer.apple.com/documentation/accessibility/performing-accessibility-audits-for-your-app)
- [Performing accessibility testing for your app](https://developer.apple.com/documentation/accessibility/performing-accessibility-testing-for-your-app)
- [Human Interface Guidelines: Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)
- [Human Interface Guidelines: Typography](https://developer.apple.com/design/human-interface-guidelines/typography)
- [What's new in accessibility (WWDC21): Full Keyboard Access](https://developer.apple.com/videos/play/wwdc2021/10120/)
- [SwiftUI environment values](https://developer.apple.com/documentation/swiftui/environmentvalues)

## Existing Strengths

This codebase has substantial accessibility work already:

- labels, values, traits, identifiers, hidden decorative elements, and named
  actions are widespread across the Mac and mobile targets;
- semantic text styles are the mobile default, and the habit visualization uses
  `@ScaledMetric` for its meaningful geometry;
- common mobile task rows are real `NavigationLink` or `Button` controls, and
  the rating control exposes an adjustable action rather than requiring five
  individual taps from VoiceOver;
- multiple Mac rows and calendar cells explicitly support focus plus Return and
  Space, and the Mac app has a broad command/shortcut surface;
- toasts and milestone celebrations post accessibility announcements instead of
  silently appearing outside VoiceOver focus;
- task state is not communicated by color alone: status glyphs, text labels,
  strikethrough, and accessibility summaries carry much of the same meaning;
- destructive operations generally use standard buttons, menus, and confirmation
  dialogs rather than custom drawing-only controls;
- the repository already states an Accessibility Inspector and VoiceOver policy
  in `apps/apple/docs/CONTRIBUTING.md`.

These are real foundations. The release risk is inconsistency and missing proof,
not the absence of accessibility intent.

## Findings

### A1 — HIGH — Common Mac navigation is not consistently an operable control

`ListCatalogRow` makes the whole row clickable with `.onTapGesture`, combines
its accessibility children, and supplies a label, but it is not a `Button`, is
not focusable, has no Return/Space handler, and does not expose a default
accessibility action. Opening a list is a common task. The row therefore has no
source-level Full Keyboard Access path, and its VoiceOver activation behavior is
at best implicit and unproven.

The inconsistency is important because other Lorvex views explicitly state that
a raw `.onTapGesture` is invisible to VoiceOver and add a default action and
keyboard handlers. Similar gaps remain in calendar all-day pills. `MemoryEntryRow`
does expose a named History action for VoiceOver, but it is not keyboard-focusable
and has no Return/Space equivalent.

Evidence:

- `Sources/LorvexApple/Views/ListCatalogRow.swift`
- `Sources/LorvexApple/Views/MemoryEntryRow.swift`
- `Sources/LorvexApple/Views/CalendarWeekGridChrome.swift`
- `Sources/LorvexMobile/MobileCalendarDayChrome.swift`
- `Sources/LorvexMobile/MobileCalendarEventBlock.swift`

Release condition: every row/pill/block whose primary behavior is open, select,
or edit must be reachable, described, and activatable with VoiceOver and full
keyboard navigation. Drag-only calendar rescheduling also needs an accessible
alternative that reaches the same time/date precision.

### A2 — HIGH — Reduced Motion support covers only a small part of animation

The source contains 49 direct animation/transition/symbol-effect sites under
`LorvexMobile` and 27 under `LorvexApple`. Only milestone celebration views read
`accessibilityReduceMotion` on mobile; the Mac has those views plus a reusable
`reduceMotionAnimation` helper. Many mobile completion springs, bounce effects,
move transitions, picker animations, review animations, progress animations,
calendar interactions, and the repeating skeleton shimmer do not consult the
setting. The Mac still has direct transitions and animation sites outside its
helper.

This is not a demand to remove all animation. Apple asks apps to stop or replace
automatic, repetitive, and motion-heavy movement when Reduced Motion is on.
Opacity or immediate state changes are normally suitable substitutes. A
repeat-forever shimmer and move/scale transitions deserve particular attention.

Evidence:

- `Sources/LorvexApple/Support/LorvexReduceMotion.swift`
- `Sources/LorvexApple/Views/HabitMilestoneCelebrationView.swift`
- `Sources/LorvexMobile/MobileHabitMilestoneCelebrationView.swift`
- `Sources/LorvexMobile/MobileSkeletonLoading.swift`
- `Sources/LorvexMobile/MobileTaskRows.swift`
- `Sources/LorvexMobile/MobileReviewRatingPicker.swift`
- `Sources/LorvexMobile/MobileIconColorPicker.swift`

Release condition: inventory every automatic/repeating, move, scale, spring,
bounce, and parallax effect; define its reduced-motion behavior; then complete
all common tasks with the system setting enabled.

### A3 — HIGH — There is no saved runtime evidence for an App Store claim

The test tree contains helper-level accessibility-label tests and source-text
assertions, but no UI test target using `XCUIApplication.performAccessibilityAudit`,
no rendered-screen audit suite, and no saved Accessibility Inspector or
physical-device matrix. A source assertion that a modifier string exists cannot
prove focus order, activation, hit region, clipping, contrast, rotor behavior,
or device-specific layout.

This blocks truthful publication of accessibility nutrition labels even where
the implementation looks strong. Apple evaluates the completed common task, not
the number of `accessibilityLabel` calls.

Release condition: preserve an audit artifact for every platform/device class,
record the exact build and OS, and keep failures/accepted exceptions alongside
the release evidence. Do not publish any label until this matrix passes.

### A4 — MEDIUM-HIGH — iOS/iPadOS Larger Text is plausible but unproven

The mobile app generally uses semantic fonts, which is the correct foundation.
However, only three `@ScaledMetric` properties exist, all in one habit
visualization. Fixed five- and six-column icon/color grids, compact calendar
columns, one- and two-line truncation, fixed metadata rows, and the review
rating control's title plus five 44-point glyphs plus Clear have no alternate
layout for accessibility sizes. These can compress, clip, or discard useful
content on a small iPhone or narrow iPad window.

Examples:

- `Sources/LorvexMobile/MobileReviewRatingPicker.swift`
- `Sources/LorvexMobile/MobileIconColorPicker.swift`
- `Sources/LorvexMobile/MobileCalendarDayChrome.swift`
- `Sources/LorvexMobile/MobileCalendarEventBlock.swift`
- `Sources/LorvexMobile/MobileTaskRows.swift`

This finding does not apply Apple's Larger Text nutrition label to Mac; Apple
does not currently offer that Mac label. Lorvex's fixed 14-point Mac primary
styles and no-op font-scale preference remain a separate usability/product
decision, not evidence of an invalid Mac App Store label.

Release condition: at 200 percent and the largest accessibility categories,
complete every common task on the narrowest supported iPhone and in narrow iPad
multitasking widths. Prefer vertical/adaptive layout and preserve the task title,
state, destructive warning, and current value over decorative metadata.

### A5 — MEDIUM-HIGH — Several mobile hit regions are visibly below 44 points

Apple's automated audit includes hit-region checks. Source-visible examples
include a 26-by-26 task completion button, 30-by-30 color swatches, 42-by-42 icon
buttons, all-day pills in a strip with a 24-point minimum height, and timed
calendar blocks with an 18-point minimum height. Some may receive additional
container spacing, but the actual interactive control does not consistently own
a 44-by-44 content shape.

Evidence:

- `Sources/LorvexMobile/MobileTaskRows.swift`
- `Sources/LorvexMobile/MobileIconColorPicker.swift`
- `Sources/LorvexMobile/MobileCalendarDayChrome.swift`
- `Sources/LorvexMobile/MobileCalendarEventBlock.swift`

Release condition: measure the resolved accessibility frame, not only the image
frame. Expand the tappable area without forcing every glyph to render at 44
points, and validate dense overlapping calendar events with Accessibility
Inspector.

### A6 — MEDIUM-HIGH — Some visual meaning has no non-color semantic equivalent

Heatmap-style habit views provide a useful summary label, but the visual cells'
per-day values are hidden. A summary can be sufficient for a decorative chart,
but if inspecting an exact day is a common task, the nonvisual interface is not
functionally equivalent.

Evidence:

- `Sources/LorvexApple/Views/HabitHeatmapView.swift`
- `Sources/LorvexMobile/MobileHabitVisualizationSection.swift`

Release condition: expose added/removed semantics in the accessibility value or
actions and add a non-color visual distinction for additions. Decide explicitly
whether exact chart-cell exploration is a common task; if so, expose it as an
accessible list, chart descriptor, or adjustable exploration control.

### A7 — MEDIUM — Increased contrast and color differentiation are not modeled

No first-party source reads `accessibilityDifferentiateWithoutColor` or
`colorSchemeContrast`, and there are no explicit high-contrast variants for the
many opacity-based accents, tint backgrounds, borders, and charts. Many standard
semantic colors and system materials may adapt automatically; static inspection
therefore cannot label every such surface a failure. It does show that custom
color semantics have no deliberate fallback policy and no test evidence.

Release condition: run the exact light/dark/accent combinations with Increase
Contrast and Differentiate Without Color. Ensure selected, overdue, priority,
added, and focus states retain text, shape, glyph, or pattern indicators. Save
contrast measurements for custom text/background pairs.

### A8 — MEDIUM — Reduced Transparency behavior is implicit and unverified

Lorvex uses system materials and Liquid Glass/fallback materials widely, which
is preferable to hand-rendered blur because the system can adapt. No source
reads `accessibilityReduceTransparency`, however, and many custom translucent
overlays and low-opacity strokes have no explicit opaque fallback. Runtime
behavior on each deployment path is unknown.

Release condition: inspect every popover, toast, inspector, toolbar, sheet,
selected row, and overlay with Reduce Transparency plus Increase Contrast. Add
an explicit fallback only where system adaptation does not preserve legibility.

### A9 — MEDIUM — Mac custom appearance pickers expose technical names

The mobile picker translates color swatches and SF Symbols into localized human
names. The Mac `LorvexColorField` announces raw hex strings, and
`LorvexIconColorField` can expose raw SF Symbol identifiers such as
`figure.run`. Its small fixed grid also needs keyboard-order and zoom testing.

Evidence:

- `Sources/LorvexApple/Views/LorvexColorField.swift`
- `Sources/LorvexApple/Views/LorvexIconColorField.swift`
- `Sources/LorvexMobile/MobileIconColorPicker.swift`

Release condition: use the same localized semantic vocabulary across platforms
and verify selection state, arrow/tab order, and the ability to distinguish each
choice without seeing the grid.

### A10 — MEDIUM — Focus restoration is not an explicit application invariant

The source contains announcements for transient toasts and milestones, but no
`AccessibilityFocusState` / `accessibilityFocused` usage and no central focus
restoration policy. After completing/deleting an item, closing an inspector,
dismissing a confirmation, changing a list, or applying an import, assistive
technology may return to an arbitrary ancestor or lose useful context.

This cannot be proved broken from source alone. It is a systematic missing
contract that must be tested because Lorvex frequently removes the selected row
as a result of the action.

Release condition: define the expected next focus for destructive deletion,
completion, dismissal, navigation replacement, import completion, and empty
state transitions. Announce only information that would otherwise be missed;
avoid duplicate announcements from native controls.

### A11 — RELEASE DECISION — Do not claim nutrition labels yet

Current static evidence is insufficient for VoiceOver, Voice Control, Larger
Text, Differentiate Without Color, Sufficient Contrast, or Reduced Motion on
any platform. Dark Interface likely has a strong system-semantic foundation,
but it too needs common-task evidence before publication. Because a published
label cannot be removed, the safe release posture is to leave labels unpublished
until the physical matrix below passes, then claim only the proven features.

## Common-Task Matrix

The status below is intentionally conservative. “Partial” means source support
exists but gaps are already visible. “Unproven” means static source cannot
establish runtime success.

| Common task | VoiceOver | Mac keyboard / iPad Full Keyboard Access | Larger Text (iOS/iPadOS) | No-color / contrast | Reduced Motion |
| --- | --- | --- | --- | --- | --- |
| Onboarding and permissions | Unproven | Unproven | Unproven | Unproven | Unproven |
| Create/edit/complete a task | Partial | Partial | Partial | Partial | Fails static policy |
| Navigate lists and open a list | Partial; Mac activation gap | Mac gap / iPad unproven | Partial | Unproven | Partial |
| Create/edit/track a habit | Partial | Partial | Partial | Chart semantics partial | Fails static policy |
| Inspect habit history/heatmap | Summary only | Unproven | Partial | Partial | Partial |
| Create/open/reschedule calendar item | Gesture parity gap | Gesture parity gap | Partial | Unproven | Fails static policy |
| Complete daily/weekly review | Partial | Partial | Layout risk | Unproven | Fails static policy |
| Browse memory | Unproven | Mac primary-action gap | Not applicable to current Mac UI | Unproven | Partial |
| Change settings and appearance | Partial | Partial | Fixed-grid risk | Unproven | Fails static policy |
| Import/export and confirmations | Unproven | Unproven | Unproven | Unproven | Unproven |
| Recover from error/empty/loading states | Announcements partial | Unproven | Unproven | Unproven | Repeating shimmer risk |

Voice Control and Switch Control should run the same task list. Assistive Access
is not presently a claimed mode, but an iPhone sanity pass is worthwhile if the
product is expected to serve users who enable it.

## Physical and Automated Release Matrix

Use the exact Release archive candidate, not a Debug approximation.

| Platform | Minimum device/window set | Required configurations |
| --- | --- | --- |
| iPhone | smallest supported screen and current large-screen phone | portrait/landscape where supported; 200% and maximum accessibility text; VoiceOver with screen curtain; Voice Control; Switch Control; Reduce Motion; Increase Contrast; Differentiate Without Color; Reduce Transparency; light/dark and non-default accent |
| iPad | compact Split View/narrow window and full screen, with hardware keyboard and pointer | Full Keyboard Access for every task; VoiceOver; Voice Control; maximum text; stage/multi-window paths if enabled; all visual settings above |
| Apple-silicon Mac | minimum supported macOS on baseline hardware and current macOS | VoiceOver; keyboard-only traversal and commands; Accessibility Inspector audit; Increase Contrast; Differentiate Without Color; Reduce Motion; Reduce Transparency; light/dark; multiple windows and sheets |

For UI automation, create one launch state per major workspace and invoke
`XCUIApplication.performAccessibilityAudit`, filtering only documented and
reviewed exceptions. Automation should also complete the common tasks because
an audit of an idle first screen cannot find modal, context-menu, drag,
destructive, loading, or post-mutation focus failures.

## Recommended Release Evidence

For every platform and build, retain:

1. archive/build identifier, OS, hardware, locale, text size, and enabled
   accessibility settings;
2. the common-task checklist with pass/fail and a short failure reproduction;
3. automated accessibility-audit output and the reviewed exception list;
4. screenshots or recordings only where they materially demonstrate clipping,
   focus, motion, contrast, or a fixed result;
5. contrast measurements for custom pairs and an inventory of non-color state
   indicators;
6. the exact App Store Connect labels justified by that evidence.

## Freeze Recommendation

Accessibility should be a release gate, but it is not a persistent data-schema
contract. Fixing these items does not justify delaying the SQLite/CloudKit schema
freeze. The important architectural decisions to freeze now are the common-task
inventory, semantic control policy (real controls before gestures), adaptive
environment policy, focus-restoration expectations, and saved release-evidence
format. Those prevent the accessibility layer from regressing as the UI is
finalized without coupling it to the sync schema.
