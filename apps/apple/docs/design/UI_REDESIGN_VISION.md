# Lorvex Apple — UI/UX Redesign Vision

Status: living design spec. Authored by the implementing engineer as the
design north star for the full Apple-ecosystem redesign. Grounded in the product +
data model; refined-native aesthetic pushed to genuinely high quality. This is the
contract the implementation is built against — not marketing copy.

---

## 1. The core insight — what Lorvex actually is

Lorvex is an **AI-native planner**. The defining difference from every other task app
is structural, not cosmetic: **the AI (via the MCP host) is the primary write surface;
the human app is primarily a place to capture, glance, execute, and reflect.** The
assistant does the heavy organizing and scheduling. The human stays in the loop.

Almost every task app is built for a human to *manually organize*: dense lists,
manual drag-reorder, manual scheduling, projects, filters, labels. If we copy that,
we build a worse version of a manual task manager **and** we contradict what Lorvex
is. The design must instead optimize for the small set of things the human actually
does, and let the AI absorb the complexity.

**Everything below derives from this insight.** When a design choice is unclear, ask:
"does this help the human capture / orient / execute / reflect / trust — or is it
manual-task-manager habit?"

## 2. The human, and their jobs-to-be-done

The human opens Lorvex to do five things, in rough order of frequency:

1. **Capture** — get a thought out of my head *now*, with near-zero friction, trusting
   it will be filed and planned. This is the #1 human action. It must be global,
   instant, and forgiving (plain natural language; the assistant sorts it out).
2. **Orient / glance** — "what should I be doing right now / today?" Calm, fast,
   confidence-inspiring. The daily driver.
3. **Execute** — complete, defer, focus, small adjustments — lightweight, in the moment.
4. **Reflect** — daily and weekly review. Lorvex's differentiator; it should feel like
   journaling, not data entry.
5. **Trust & browse** — occasionally see *why* the assistant did something (ai_notes),
   browse the full library, search. Transparency builds trust in the automation.

The UI is weighted toward 1–2 (capture + orient), makes 3 effortless, treats 4 as a
first-class destination, and keeps 5 calm and available without cluttering the daily flow.

## 3. Design principles (north star)

- **Calm, not busy — but calm ≠ crude.** The AI absorbs complexity so the screens don't
  have to: one primary thing per screen, generous whitespace, clear hierarchy, no
  wall-of-checkboxes. Confidence over density. **This is never an excuse for bareness.**
  Calm is achieved through *rich, crafted* components — depth, considered color, colored
  icon tiles, substantial cards, motion — and restraint in *quantity*, not *quality*. A
  calm screen still feels designed and full of craft; an empty one feels unfinished. When
  a surface looks sparse, the answer is more polish and richer components, not less.
- **Capture is sacred.** The fastest possible path from thought → captured, reachable
  from anywhere with one gesture. Never bury it behind navigation.
- **Native, but crafted.** Refined-native: system materials, SF typography, native
  components and gestures — *plus* a consistent, considered layer (cards, a real color
  system, colored icon tiles, motion) so it reads as *designed*, not assembled. The bar
  is a best-in-class first-party Apple app, not bare `List`/`Form` defaults.
- **Trust through transparency.** Where the assistant acted, make it inspectable —
  `ai_notes` as a distinct, calm "from your assistant" block; planned-by-AI cues — quietly,
  never noisily.
- **One language, many forms.** A single design system, expressed appropriately per
  platform: touch-first on iPhone, two-pane on iPad/landscape, glanceable on watch,
  template-driven on CarPlay, pointer-dense on Mac, spatial on Vision.
- **Respect the system.** Dynamic Type, dark mode, reduce-motion, VoiceOver, Full
  Keyboard Access are non-negotiable and designed-for from the start, not bolted on.

## 4. Information architecture (reasoned, not assumed)

IA follows the jobs-to-be-done, not a generic task-app template. Two structural decisions:

**Capture is a global gesture, not a destination.** It is the #1 action and must be
available from every primary surface. So it is a persistent affordance (a thumb-reachable
compose control) that presents a focused quick-add sheet — *not* a tab. This also makes
iPhone consistent with macOS, which already retired its separate Quick Capture in favor
of inline capture. Removing the Capture tab is one of the first IA corrections.

**Primary surfaces deserve top-level homes; "More" is a dumping ground.** Today's iOS IA
buries Tasks, Lists, Calendar, and Habits under a generic "More" — for a planner, those
are primary. The new tab set should expose the human's actual recurring destinations and
push genuinely secondary things (Memory, Settings) to the edges.

**Candidate iPhone tab model** (to be finalized against the IA audit, but the reasoning
is fixed): the recurring destinations are *orient*, *time*, *browse/trust*, *reflect*.

- **Today** — orient + execute. The home and emotional center.
- **Calendar** — the time view: scheduled tasks + events, day/week.
- **Library** (a.k.a. Browse) — all tasks by list, smart lists (Inbox/All/Overdue/
  Someday), memory. For browse + trust.
- **Review** — daily + weekly reflection. The differentiator, first-class.
- **➕ Capture** — global compose, not a tab.
- **Settings** — gear/profile entry, not a tab.

Habits live as a Today card + a dedicated detail screen reached from there (and from
Library), rather than consuming a scarce tab slot — unless the audit shows habits usage
warrants its own tab, in which case 5 tabs is still within HIG comfort.

This is a *direction with locked reasoning*, not a locked layout; the audits refine the
specifics (e.g. exactly what belongs in Library vs. Today).

## 5. The visual design language — "refined-native+"

The current system is three thin token groups (type, 5-step spacing, 2-step radius up to
10pt) with no color system, no elevation, no card, no icon tiles, no empty-state
component. That bareness *is* the crudeness. The language adds a deliberate layer on top
of native, without fighting the platform.

- **Color.** A considered **Lorvex accent** (a refined, slightly deeper blue — not raw
  neon system blue), defined as a semantic token so it themes light/dark. A small,
  meaningful **status palette**: overdue (red), due-soon (orange), focus (accent),
  someday (muted/indigo), completed (green), and priority tiers. Surfaces use the system
  grouped backgrounds with an explicit **elevated card** surface. Colors are always
  semantic (asset-catalog or `Color` with light/dark variants), never hardcoded hex in views.
- **Colored icon tiles.** The single highest-leverage move for "designed, not bare": a
  rounded-square tile (~30pt, continuous corners) with a tinted fill (~12–16% of a hue)
  and the SF Symbol in full hue. Used for list rows, habit rows, section leaders, and
  Settings rows — exactly the texture mature apps have, achieved natively.
- **Typography.** Recalibrate. iOS `primaryText` is currently `.title3` (~20pt) — too big
  for rows; it reads as crude/oversized. Move row titles to `.headline`/`.body`, metadata
  to `.subheadline`/`.caption`, and reserve large type for true screen titles. Calmer,
  denser, more legible — closer to Apple's own apps. Keep Dynamic Type throughout.
- **Shape & elevation.** Add card radii (≈16–20pt continuous). Cards sit on an elevated
  surface with hairline separators or subtle material; consistent inset grouping. The
  current 10pt max is too tight for the modern card look.
- **Empty states.** A reusable rich component: a ~56pt glyph in a tinted circle, a warm
  title, a calm one-line subtitle, and exactly one primary action — never a stretched
  button. (This is also the fix for the Today "blue bar" bug, which is a
  `ContentUnavailableView` misused as a `List` row.)
- **Motion & feedback.** Subtle and meaningful: completes spring + haptic, focus changes
  ease gently, transitions are smooth. Honor reduce-motion. `.sensoryFeedback` on the key
  state changes (complete, defer, focus).
- **Iconography discipline.** SF Symbols everywhere; *colored tiles for entities*,
  *monochrome glyphs for actions*. Never decorative.

These become real tokens/components in `LorvexDesign` (shared) + a small set of mobile
components, so every screen composes from the same parts.

## 6. Key interaction patterns

- **Capture.** One compose control → a focused sheet: a single natural-language field
  (plain text, no markdown toggle), optional quick chips (list · date · priority), and a
  quiet "your assistant will organize this" tone. Fast to dismiss, fast to repeat (keep
  open for multi-capture). Available from every primary surface and via the Home-Screen
  quick action / share extension / Siri.
- **Glance (Today).** A warm contextual header with an assistant-authored one-line day
  summary; the focus/time-block plan with "now" highlighted; the few today tasks that
  matter; a habits glance; next events. The AI curates — the human is not handed a
  hundred-row checklist.
- **Execute.** Swipe to complete/defer (native), tap to open detail, long-press for a
  context menu, one gesture to toggle focus. Completion animates with a gentle spring +
  haptic. No dead-end rows.
- **Reflect (Review).** Feels like journaling: a calm prompt, mood/energy as expressive
  pickers, the evidence the assistant gathered for the day, wins/blockers/learnings as
  soft text — not a stack of form fields. Weekly = a digest with per-day navigation.
- **Trust.** `ai_notes` render as a distinct tinted, italic, read-only "from your
  assistant" block (never editable in the UI). Changelog reachable but never in the way.

## 7. Per-surface design direction (iPhone first)

- **Today** — the cockpit. Header (greeting + AI day summary) → Focus/Schedule (now-aware)
  → Today's tasks (curated, not exhaustive) → Habits glance → Up next (events). Cards, not
  a flat list. Capture FAB always present.
- **Calendar** — day/week of scheduled tasks + events, touch-tailored; clean event chips;
  drag to reschedule where it makes sense; calm empty days ("nothing scheduled — enjoy it").
- **Library / Browse** — smart lists up top (Inbox, All, Overdue, Someday, Focus), then
  user lists as colored-tile rows with counts, then Memory. Search is
  prominent here. This is the "everything" surface for browse + trust.
- **Review** — the journaling surface above. Daily + weekly, evidence-backed.
- **Task detail** — a calm, scannable sheet/inspector: title, the assistant's notes block,
  human notes (plain text), metadata as tidy chips (list, dates, priority, estimate, tags,
  dependencies, recurrence, checklist), and clear primary actions (Complete/Focus/Defer).
- **Settings** — colored-tile rows (the references' texture), grouped sensibly; sync,
  calendar filter, notifications/badge, permissions, data, about.
- **Create/Edit sheets** — consistent, detented, plain-text inputs, focus-chained fields,
  one clear primary action; never clipped (the onboarding lesson — pinned CTAs, full height).

## 8. Cross-platform adaptation (one language, many forms)

One shared design *language* (tokens, color, iconography, component vocabulary, motion) —
but each platform gets **genuinely distinct layouts and interaction patterns** native to
its form factor. Sharing the language is not sharing the layout; a platform is never a
scaled copy of another.

- **iPhone** — touch-first, single column, tab bar + capture FAB. Task **detail is a
  presented card/sheet** (a detented sheet that rises over the list), *not* a side panel —
  there's no room for a persistent inspector. The reference surface for the language.
- **iPad / landscape** — **designed for the form factor, not a blown-up iPhone.** A real
  two/three-pane `NavigationSplitView` (destinations · list · detail) where detail lives
  in a persistent third column (unlike iPhone's sheet); landscape genuinely uses the
  width — Today's cockpit beside an open task, a true week/month calendar grid, multi-
  column catalogs. Pointer, hover, keyboard, and multi-window/Stage Manager are
  first-class, not afterthoughts.
- **watchOS** — radically reduced: glance (today count + next focus), capture (dictation),
  complete/defer, complications. Read-mostly snapshot client; the same status colors and
  iconography at watch scale.
- **CarPlay** — templates only: today/focus list, tap → action sheet (complete / defer /
  open on phone). Safety-first, no dense UI.
- **macOS** — already acceptable; a later polish pass aligns it to the same color/icon-tile/
  card language and tightens density (pointer-driven). Inline capture stays.
- **visionOS** — the mobile surface with spatial materials/ornaments; glass backgrounds,
  comfortable spacing.

## 9. What changes from today (concrete deltas)

1. Remove the iOS **Capture tab**; make capture a global ➕ → quick-add sheet (consistent
   with macOS inline capture).
2. Replace the **"More" dumping ground** with real top-level destinations
   (Today · Calendar · Library · Review) + Settings/Capture as edge affordances.
3. Build the **design system**: accent + semantic/status colors, card + elevation, colored
   icon tiles, rich empty-state component, recalibrated typography, larger card radii,
   motion/haptics — in `LorvexDesign` + mobile components.
4. Rebuild every iOS surface to compose from those components (kills the bare-`List`/
   default-`ContentUnavailableView` crudeness and the blue-bar bug).
5. Give **iPad/landscape** a true split layout.
6. Re-skin **watch / CarPlay** to the shared language; later **macOS** polish.

Implementation proceeds bottom-up (tokens → components → surfaces), iPhone first, each
surface built → launched in the simulator → screenshotted → refined. Visual verification
is mandatory: the worst bugs here (letterbox, blue bar, clipped CTAs) were invisible to
code review and obvious on first launch.
