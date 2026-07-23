# Design Tokens

Lorvex's frontend visual language is encoded as CSS custom properties and
`@utility` blocks in `app/src/index.css`. This file is the canonical
catalog: what each token / utility *means*, when to reach for it, and
when not to. Concrete numeric values are intentionally not duplicated
here — they live alongside the `--token` declaration in `index.css`
and shift per theme / appearance profile. The role descriptions below
do not.

This catalog is a living reference. When you add a new token family or
@utility composition, register the role here so the next contributor
inherits the rationale. When you migrate inline literals to a token,
remove the literal from the codebase rather than keep both forms — the
token is only useful if it is the single source of truth.

## Table of contents

| Section | What lives here |
| --- | --- |
| [Color](#color) | Surface ladder, accent ladders, text scale, semantic feedback |
| [Accent tint ladder](#accent-tint-ladder) | Six-step `--accent-tint-*` for accent fills, halos, glows (#3642) |
| [Border tokens](#border-tokens) | Soft + strong surface-3 hairlines (#3643, #3654) |
| [Ink-shadow ladder](#ink-shadow-ladder) | Six-step `--shadow-ink-*` for black-tinted shadows / drops / edges (#3652) |
| [Danger-tint ladder](#danger-tint-ladder) | Six-step `--danger-tint-*` for danger-keyed surfaces (#3654, #3709) |
| [Success-tint ladder](#success-tint-ladder) | Six-step `--success-tint-*` for success-keyed surfaces (#3703, #3708) |
| [Warning-tint ladder](#warning-tint-ladder) | Six-step `--warning-tint-*` for warning-keyed surfaces (#3703, #3708) |
| [Swipe-hint tokens](#swipe-hint-tokens) | `--swipe-hint-{success,warning}` mid-alpha gradient stops for touch swipe affordances |
| [Accent-tint selection token](#accent-tint-selection-token) | `--accent-tint-selection` for `::selection` backgrounds |
| [Accent-tint focus token](#accent-tint-focus-token) | `--accent-tint-focus` for the global keyboard focus-ring outline (#3787) |
| [Shell-card gradient stop tokens](#shell-card-gradient-stop-tokens) | `--shell-card-stop-{top,mid,bottom}` for `.shell-card`'s fallback gradient (#3787) |
| [Danger-tint validated-input tokens](#danger-tint-validated-input-tokens) | `--danger-tint-validated-{border,focus}` for `[aria-invalid='true']` form controls (#3787) |
| [Desktop shell tokens](#desktop-shell-tokens) | Gradient atmosphere primitives for the desktop-shell utility (#3653) |
| [Typography family](#typography-family) | `--app-font-family` per-OS stack (#3653) |
| [Glass surface tokens](#glass-surface-tokens) | `--glass-*` composition primitives for liquid panels (#3653) |
| [Radius scale](#radius-scale) | `--radius-r-*` from chip to modal |
| [Shadow / depth](#shadow--depth) | Elevation, glow, rail, event-card, empty-state |
| [Z-index](#z-index) | Stacking contract from base to tooltip |
| [Typography](#typography) | `--font-*` families and the `--text-*` size ramp |
| [Modal width scale](#modal-width-scale) | Canonical four-step modal width |
| [Spacing helpers](#spacing-helpers) | Chip + row paddings used by the chip / row utilities |
| [Easing curves](#easing-curves) | `--ease-overshoot`, `--ease-modal-settle`, `--ease-glow-cycle` |
| [Animation tokens](#animation-tokens) | Tailwind 4 `@theme`-registered keyframe shorthands |
| [Glass + profile](#glass--profile) | Liquid panel fills, material backdrop saturation, highlight insets |
| [Clarity-profile overrides](#clarity-profile-overrides) | `--clarity-override-*` for the high-contrast profile |
| [Focus utilities](#focus-utilities) | `focus-ring-soft` / `focus-ring-strong` + semantic-tone variants policy |
| [Composed `@utility` blocks](#composed-utility-blocks) | Chip / row / heading / panel / shell / animation shells |
| [Window scoping](#window-scoping) | `data-window-kind` / `data-window-transparent` opt-out for overlays / popover (#3691, #3698) |

---

## Color

The base color tokens declare a four-step surface ladder
(`--color-surface-0..3`), an accent pair
(`--color-accent`, `--color-accent-hover`), a three-step text ladder
(`--color-text-primary`, `--color-text-secondary`, `--color-text-muted`),
and three semantic feedback colors (`--color-danger`,
`--color-success`, `--color-warning`).

`--color-card` and `--color-popover` are derived via `color-mix()` from
`--color-surface-3` with explicit alpha so card/popover surfaces stay
in lockstep with the surface scale.

**Use** the named tokens for any background, text, border, or focus
ring. **Do not** hand-roll `rgba(0, 0, 0, x)` literals — the gates
guard against this regression and the values do not respect the active
theme.

Additional color tokens (#3653):

- **`--color-hover-tint`** — tint applied to row / list-item hover
  states across themes. Per-theme overrides redefine the value (paper
  warms it slightly; mica / liquid_glass shift hue toward the active
  surface). **Use** when a surface needs a hover wash that respects
  the theme's tone. **Do not** hardcode a hover background — the
  hover tint is profile-aware in a way `--color-surface-2` is not.
- **`--color-card`** / **`--color-popover`** — derived via
  `color-mix()` from `--color-surface-3` so cards / popovers stay in
  lockstep with the surface ladder. Light themes redefine the
  alphas; clarity profile substitutes opaque values. **Use** for any
  card or popover background. **Do not** mix in literal alphas.
- **`--color-overlay`** — modal / sheet backdrop. Defined per
  appearance profile (translucent surfaces use a stronger overlay,
  Mica uses a lighter one to let the desktop bleed through). **Use**
  for modal overlays. **Do not** spell `bg-black/40` — the literal
  ignores the active profile.
- **`--color-on-accent`** / **`--color-on-accent-soft`** — foreground
  color for content painted on `bg-accent` / `bg-success` /
  `bg-danger` / `bg-warning` fills. Default is white; themes whose
  accent is light enough that white drops below WCAG AA (midnight,
  mica dark, adwaita dark) override it to dark ink. The `-soft`
  variant is the same color at ~0.86 alpha for secondary labels on
  accent surfaces. **Use** via the `text-on-accent` Tailwind utility
  on every accent / success / danger / warning button. **Do not**
  hand-roll `text-white` against semantic fills — that hard-codes
  white regardless of accent lightness.

## Desktop shell tokens

`--desktop-shell-{top-tint, top-strength, left-bloom-strength,
right-bloom-strength}` (#3653) — composition tokens for the
`desktop-shell` utility's gradient atmosphere. Per-theme values control
how much the top edge tints the shell, and how strong the left
(surface-1) and right (accent) blooms read against the wallpaper.

**Use** these only when authoring the desktop shell utility itself or
a sibling shell (popover-window shell, focus-mode shell) that should
share the atmosphere. **Do not** read them from arbitrary component
CSS — the shell is the composition boundary.

## Typography family

- **`--app-font-family`** (#3653) — platform-aware UI font stack.
  Each OS gets its own variant (Segoe UI on Windows, Inter on Linux,
  Roboto on Android, system stack on macOS) so the app blends into
  the host platform. **Use** at the html/body root only — every
  descendant inherits. **Do not** override per-component; mismatched
  fonts make the surface feel like a third-party widget.

## Glass surface tokens

`--glass-{surface-tint, surface-alpha, bg, border, shadow-soft,
shadow-inner, blur}` (#3653) — composition primitives for the
liquid-glass panel system. The `liquid-popover-panel`,
`liquid-settings-panel`, `liquid-sidebar-shell`,
`profile-material-shell` utilities build on these so a single retune
updates every glass surface.

| Token | Role |
| --- | --- |
| `--glass-surface-tint` | Hue + lightness used as the panel's tint base before alpha mixing. |
| `--glass-surface-alpha` | Mix percentage of the tint against transparent — controls the panel's opacity. |
| `--glass-bg` | Composed background for inline glass surfaces (uses the tint + alpha). |
| `--glass-border` | Hairline color for glass panels — softer than `--color-surface-3` to keep the edge optical, not structural. |
| `--glass-shadow-soft` | Outer drop for floating glass panels. |
| `--glass-shadow-inner` | Inset top-edge highlight that fakes a lit edge. Distinct from the broader `--glass-highlight-inset-*` (which is `::after` pseudo-rendered on shells). |
| `--glass-blur` | `backdrop-filter` blur radius. Per-profile overrides retune blur strength. |

**Use** when authoring a new glass shell in `index.css`. **Do not**
read these from component CSS — author against the composed
`liquid-*-panel` utility instead.

## Accent tint ladder

Seven discrete steps for accent tints, introduced in #3642 and
extended with the `2xl` symmetry rung in #3729. The ladder fixes the
alpha vocabulary so every accent halo / hover fill / glow shadow
composes on the same scale.

| Step | Alpha | Typical use |
| --- | --- | --- |
| `--accent-tint-xxs` | 0.06 | Faint hover backgrounds, drop-target wash |
| `--accent-tint-xs` | 0.12 | Inset rings, secondary glow halos |
| `--accent-tint-sm` | 0.20 | Empty-state glow, soft drop-shadow base |
| `--accent-tint-md` | 0.32 | Primary glow, hover link tint |
| `--accent-tint-lg` | 0.50 | Active borders, prominent drop-shadow tops |
| `--accent-tint-xl` | 0.80 | Hover link color (still recognizably accent) |
| `--accent-tint-2xl` | 0.85 | Near-opaque accent fill (symmetry rung; #3729) |

**Use** when you need an alpha-fade of the active accent. The ladder
keeps theme retunes coherent — a teal accent produces a teal halo, an
orange accent produces an orange halo, all on the same alpha rhythm.

**Do not** pick a one-off alpha (e.g. `oklch(from var(--color-accent) l c h / 0.27)`).
If a step doesn't fit, that's a signal the design intent is unclear,
not that the ladder needs an extra step. Discuss before extending.

## Border tokens

- **`--border-surface-3-soft`** (#3643) — `1px solid` half-strength
  surface-3 hairline. Used by the four Milkdown editor shells (editor
  wrapper, code block, blockquote, table) so they all share one
  border treatment. **Use** for any soft hairline that should be
  dimmer than the full `--color-surface-3` divider. **Do not** use
  for prominent dividers — those should still read as full-strength
  surface-3.
- **`--border-surface-3-strong`** (#3654) — surface-3 at 0.3 alpha,
  used by the liquid-glass profile's
  `[class*='border-surface-3']` override. **Use** as the
  glass-profile counterpart to the soft hairline. **Do not** mix
  with `--border-surface-3-soft` on the same surface — pick whichever
  emphasis level the profile is opting into.

## Ink-shadow ladder

`--shadow-ink-{xxs, xs, sm, md, lg, xl}` (#3652) — six discrete
black-tinted alphas powering every shadow / drop / edge in the
stylesheet. Parallel to the accent-tint ladder. Light themes redefine
the ladder values rather than respelling every literal, so depth
retunes happen in one place.

| Step | Dark α | Light α | Typical use |
| --- | --- | --- | --- |
| `--shadow-ink-xxs` | 0.06 | 0.04 | Rail edge, very subtle drops |
| `--shadow-ink-xs` | 0.08 | 0.05 | Desktop card subtle drop |
| `--shadow-ink-sm` | 0.10 | 0.06 | Tooltip secondary |
| `--shadow-ink-md` | 0.14 | 0.08 | Popover secondary |
| `--shadow-ink-lg` | 0.22 | 0.12 | Tooltip / popover primary, modal secondary |
| `--shadow-ink-xl` | 0.45 | 0.22 | Modal primary, event-card hairline |

**Use** when composing a black-tinted shadow / drop / edge. **Do not**
inline `oklch(from black l c h / α)` — pick the nearest step. If the
step doesn't fit, raise it: a one-off alpha is a signal of design
drift, not of a missing rung.

## Danger-tint ladder

`--danger-tint-{xs, sm, md, lg, xl, 2xl}` (#3654, #3709) — six-step
ladder for surfaces tinted by the active theme's danger color.
Parallel to the accent-tint ladder.

| Step | Alpha | Typical use |
| --- | --- | --- |
| `--danger-tint-xs` | 0.06 | Error-state background tint |
| `--danger-tint-sm` | 0.20 | Error-state badge fill |
| `--danger-tint-md` | 0.40 | Error-state hairline (medium emphasis) |
| `--danger-tint-lg` | 0.60 | Error-state hairline (high emphasis) |
| `--danger-tint-xl` | 0.75 | Error-state CTA fill / focused destructive |
| `--danger-tint-2xl` | 0.90 | Solid destructive CTA hover |

**Use** for danger-keyed surfaces that need a tint matching the
active theme's danger hue. **Do not** inline
`oklch(from var(--color-danger) l c h / α)` and **do not** write
`bg-danger/N` Tailwind opacity utilities — pick a step. The xl/2xl
steps were added in #3709 so the ~30 raw `bg-danger/N` sites in the
sweep could snap onto the catalog rather than inlining oklch literals.

## Success-tint ladder

`--success-tint-{xs, sm, md, lg, xl, 2xl}` (#3703, #3708) — six-step ladder for
surfaces tinted by the active theme's success color. Parallel to the
danger-tint ladder, but tuned lighter because success surfaces tile
across full panels (StatCard, ReviewSection, completion toasts) where
danger tints only mark single overdue lines.

| Step | Alpha | Typical use |
| --- | --- | --- |
| `--success-tint-xs` | 0.06 | Broad area background (StatCard, panel fill) |
| `--success-tint-sm` | 0.12 | Chip / pill fill (status badge, count chip) |
| `--success-tint-md` | 0.20 | Hover / active emphasis on the same chip |
| `--success-tint-lg` | 0.30 | High-emphasis hairline + selected state |
| `--success-tint-xl` | 0.50 | Timeline / progress fill (mid-emphasis) |
| `--success-tint-2xl` | 0.85 | Solid CTA hover ("Mark done" button) |

**Use** for success-keyed surfaces that need a tint matching the
active theme's success hue. **Do not** write `bg-success/N` Tailwind
opacity utilities — pick a `bg-[var(--success-tint-X)]` step so a
theme retune of `--color-success` propagates uniformly. The xl/2xl
steps were added in #3708 to cover heavy-alpha CTA hover sites
(FocusModeQueueFooter, FocusPopoverPanel, DayTask) plus timeline
accent fills (BlockComponents progress bar / rail).

## Warning-tint ladder

`--warning-tint-{xs, sm, md, lg, xl, 2xl}` (#3703, #3708) — six-step ladder for
surfaces tinted by the active theme's warning color. Same alpha steps
as the success-tint ladder.

| Step | Alpha | Typical use |
| --- | --- | --- |
| `--warning-tint-xs` | 0.06 | Broad area background (overdue panel fill) |
| `--warning-tint-sm` | 0.12 | Chip / pill fill (stale badge, defer count) |
| `--warning-tint-md` | 0.20 | Hover / active emphasis on the same chip |
| `--warning-tint-lg` | 0.30 | High-emphasis hairline + selected state |
| `--warning-tint-xl` | 0.50 | Timeline / event-block accent rail |
| `--warning-tint-2xl` | 0.85 | Solid CTA hover (warning-keyed) |

**Use** for warning-keyed surfaces that need a tint matching the
active theme's warning hue. **Do not** write `bg-warning/N` Tailwind
opacity utilities — pick a `bg-[var(--warning-tint-X)]` step. The
xl/2xl steps mirror success-tint and were added in #3708 for
parity.

## Swipe-hint tokens

Mid-alpha tonal washes that drive the day-card swipe-affordance gradient
on touch devices. Defined alongside the warning/success ladders so the
hint color tracks the active theme's semantic hue, but at a higher
alpha (0.55) than the regular `*-tint-md` step — the gradient needs to
read clearly through a moving card without becoming opaque.

| Token | Role | Use when | Avoid when |
| --- | --- | --- | --- |
| `--swipe-hint-success` | Right-swipe affordance gradient stop (complete action) | Wiring the right-edge wash on the calendar swipe-hint utilities (`.cv-swipe-hint-right`); any future "positive swipe" affordance that needs a theme-tracking success tint at mid-alpha | A static success badge or chip — use `chip-success` / `--success-tint-sm` instead. Inline `oklch(... / 0.55)` — that's the literal this token replaces |
| `--swipe-hint-warning` | Left-swipe affordance gradient stop (defer / dismiss action) | Wiring the left-edge wash on the calendar swipe-hint utilities (`.cv-swipe-hint-left`); any future "neutral swipe" affordance that needs a theme-tracking warning tint at mid-alpha | A static warning chip — use `chip-warning` / `--warning-tint-sm`. The gradient *must* fade to transparent on the inner side, so this token is meant as one of two stops, never as a flat fill |

## Accent-tint selection token

`--accent-tint-selection` (#3725 catalog backfill) — accent at alpha
0.35. A one-off step between the regular `--accent-tint-md` (0.32) and
`--accent-tint-lg` (0.50) intentionally placed *off* the standard
ladder because text-selection backgrounds need slightly more presence
than `md` (which loses against bright theme accents) but `lg` is too
saturated for some palettes (washes the selected glyphs out).

| Token | Role | Use when | Avoid when |
| --- | --- | --- | --- |
| `--accent-tint-selection` | `::selection` background fill | Styling text-selection backgrounds across editable surfaces (Milkdown editor, plain `<input>` / `<textarea>`) so highlighted text reads as accent without the standard ladder's contrast pitfalls | A non-selection surface — pick the nearest ladder step. Inline `oklch(... / 0.35)` — that's the literal this token replaces |

## Accent-tint focus token

`--accent-tint-focus` — accent at alpha 0.60. The base
`focus-visible` outline rule for `<button>` / `[role='button']` /
`<a>` and `<input>` / `<textarea>` / `<select>` consumes this single
token; do not reintroduce inline `color-mix(...)` duplicates. 0.60 sits between
`--accent-tint-lg` (0.50, active borders) and `--accent-tint-xl`
(0.80, hover link color) — the focus ring needs more presence than a
passive border but stays calmer than a hover affordance.

| Token | Role | Use when | Avoid when |
| --- | --- | --- | --- |
| `--accent-tint-focus` | Default keyboard focus-ring outline color | Wiring the global `:focus-visible` rule for buttons, links, and inputs so every focusable element shares the same accent ring | A bespoke focus treatment that needs more or less presence — pick a ladder step instead. Inline `oklch(... / 0.60)` — this token replaces it |

## Shell-card gradient stop tokens

`--shell-card-stop-{top, mid, bottom}` (#3787) — the three alpha stops
(95 % / 90 % / 86 %) that fall back to drive `.shell-card`'s linear
gradient when the active appearance profile does not override
`--shell-card-bg`. The 4-pt drop between mid and bottom is what gives
the card its soft-edge feel; the named stops preserve that curve while
letting future profiles retune individual rungs.

| Token | Role | Use when | Avoid when |
| --- | --- | --- | --- |
| `--shell-card-stop-top` | Gradient start (surface-1 95 %) | Composing alternative `--shell-card-bg` overrides that want to keep the canonical top stop | A flat fill — pick `--color-surface-1` directly |
| `--shell-card-stop-mid` | Gradient midpoint (surface-0 90 %) | Same; ensures the 70 %-position kink stays consistent with the default ladder | Same as above |
| `--shell-card-stop-bottom` | Gradient end (surface-0 86 %) | Same; preserves the 4-pt soft-edge drop | Same as above |

## Danger-tint validated-input tokens

`--danger-tint-validated-{border, focus}` (#3787) — alpha 0.55 / 0.70
respectively. The `.validated-input[aria-invalid='true']` recipe needs
a 55 %-alpha border and a 70 %-alpha focus shadow that don't sit on
the standard `--danger-tint-*` ladder (which jumps 0.40 → 0.60 →
0.75). Splitting them keeps the canonical ladder semantically clean
(each rung documents one use) while still giving the validated-input
recipe named tokens.

| Token | Role | Use when | Avoid when |
| --- | --- | --- | --- |
| `--danger-tint-validated-border` | `border-color` for `[aria-invalid='true']` form controls | Wiring the canonical validated-input recipe; any future "soft danger border" surface that wants the same 55 %-alpha rung | A standalone danger affordance — pick a `--danger-tint-*` ladder step |
| `--danger-tint-validated-focus` | `box-shadow` ring for focused `[aria-invalid='true']` controls | Pairing with the border above to give the focus ring slightly more presence (0.70) than the resting border (0.55) | Same as above |

## Radius scale

`--radius-r-{chip, control, card, panel, window, modal}` — six-step
corner-radius ladder from `9999px` (chip pill) up to `1.25rem` (modal).

Pick the step that names the surface, not the visual radius you
remember from a mockup. A "card" should always be `--radius-r-card`,
not `--radius-r-control` or `--radius-r-panel`, even if a particular
mock looks tighter — the ladder is what keeps surface families
distinguishable across themes.

Each radius token has a matching Tailwind 4 `@utility` shortcut
registered in `app/src/index.css`:

| Token | Utility |
| ----- | ------- |
| `--radius-r-chip` | `rounded-r-chip` |
| `--radius-r-control` | `rounded-r-control` |
| `--radius-r-card` | `rounded-r-card` |
| `--radius-r-panel` | `rounded-r-panel` |
| `--radius-r-window` | `rounded-r-window` |
| `--radius-r-modal` | `rounded-r-modal` |

Prefer the named utility (`rounded-r-card`) over the arbitrary-value
form (`rounded-[var(--radius-r-card)]`) — it reads as the surface role
and keeps the call site short.

`--radius-scrollbar` (#3704) — `6px`. Sits outside the `r-*` ladder
because it is component-internal (matches the 6px scrollbar thumb
half-width to read as a fully-rounded capsule) rather than a surface
family. Only the WebKit scrollbar thumb consumes it.

## Shadow / depth

- **`--shadow-tooltip`, `--shadow-popover`, `--shadow-modal`** —
  three-step elevation ladder for ephemeral surfaces (#3613). Each is
  composed of two black-derived oklch shadows; light-theme depth can
  be retuned in one place.
- **`--shadow-desktop-card`** — body-level elevation for the desktop
  card grammar.
- **`--shadow-glow-accent`, `--shadow-glow-success`** — accent-aware
  outer glows for focus-grabbing affordances (toasts, success states).
  The accent variant is composed on the `--accent-tint-md` step so a
  theme retune flows through automatically (#3642).
- **`--shadow-rail-edge`** — left-edge dimming for sticky rails so
  the rail content visually separates from the body card.
- **`--shadow-nav-active`** — inset-ring accent glow on the active
  navigation chip (uses `--accent-tint-xs`).
- **`--shadow-event-card`** — flat 1px black hairline beneath
  calendar event cards.
- **`--shadow-empty-state`** — outward accent glow on empty-state
  panels (uses `--accent-tint-sm`).

## Z-index

`--z-{base, elevated, sticky, overlay, popover, modal, toast, critical, tooltip}`
— nine-step stacking ladder. Use the named token, never a numeric
literal. The numeric values are intentionally spaced so a future
retune (insert a new mid-tier layer) doesn't force a renumbering
of every consumer.

## Typography

`--font-sans` and `--font-mono` resolve the platform font stacks.

`--text-{2xs, 3xs}` extend the Tailwind ramp downward (11 px and 10 px)
for the dense info chrome (status meta, badge counts). Each carries an
explicit `--line-height` companion. **Use** these for any chip / meta
text. **Do not** reach for `text-[11px]` literals.

`--text-{13, 15}` fill the mid-rung gaps between `text-xs` (12 px) and
`text-sm` (14 px), and between `text-sm` and `text-base` (16 px).
Footer CTAs, focus-mode chrome, mobile focus footers, and onboarding
row metadata had drifted to
`text-[13px]` / `text-[15px]` arbitrary values; the named tokens
re-collapse the drift. **Use** `text-13` (13 px / 1.1 rem line) for
focus-mode footer CTAs and stepper-adjacent metadata, and `text-15`
(15 px / 1.4 rem line) for mobile focus footer CTAs. **Do not** reach
for `text-[13px]` / `text-[15px]`
literals.

The standard `--text-{xs, sm, base, lg, xl}` Tailwind defaults remain
the shipping ramp for body and headings.

## Modal width scale

`--modal-w-{sm, md, lg, xl}` — four-step canonical modal widths
(400 px → 640 px). Every modal must pick one of these so the visual
rhythm stays consistent across Command Palette, Confirm, Quick
Capture, Welcome, Help.

## Popover width scale

`--popover-w-{xs, sm, md, lg}` (#4373) — four-step canonical popover
widths (200 px → 320 px). Floating panels anchored to a trigger
(date pickers, list pickers, duration pickers, language picker,
filter dropdowns) pick one of these so the visual rhythm stays
consistent across surfaces. Distinct from `--modal-w-*` — modals
are dialogs anchored to the viewport center at much wider scale;
popovers shrink-wrap dense list content adjacent to their trigger.

| Token | Width | Typical use |
| --- | --- | --- |
| `--popover-w-xs` | 200 px | Compact filter / language pickers with a short label list |
| `--popover-w-sm` | 240 px | List pickers with secondary metadata (DueDate, Duration, Recurrence, ListPicker) |
| `--popover-w-md` | 280 px | Date pickers needing room for a 7-column calendar grid |
| `--popover-w-lg` | 320 px | Larger pickers with embedded form controls or thumbnails |

**Use** for the panel itself via `w-[var(--popover-w-md)]`. **Do not**
hand-pick a one-off width — if a step doesn't fit, raise the
question rather than invent a new size.

## Touch-target tokens

`--tap-target` (#4374) — `44px`, the WCAG 2.5.5 / Apple HIG minimum
touch-target size. Consumed by the `min-tap` utility. **Use** the
`min-tap` class on small touch affordances (mobile week-grid day
buttons, mobile chevrons) whose visual size would otherwise
undershoot. **Do not** inline `style={{ minWidth: 44, minHeight: 44 }}` —
the literal drifts out of sync with a future platform retune (an
Android 48-dp adjustment would update one token, not 30 sites).

## Toggle focus-ring cutout

`--toggle-ring-cutout` (#4371) — the surface color the `<Toggle>`
track paints around its focus outline so the outline reads as a
halo rather than a stray ring. Defaults to `--color-surface-0`
(the document body). Ancestors that paint a non-surface-0 fill
(settings cards on `surface-1`, toolbar chips on `surface-2`)
override this token locally so the cutout matches. **Use** by
overriding `--toggle-ring-cutout` on the ancestor container.
**Do not** inline `peer-focus-visible:shadow-[0_0_0_2px_var(--color-surface-N)]`
in the toggle — that defeats the local-surface override.

## Spacing helpers

- **`--chip-tight-{px, py}` / `--chip-cozy-{px, py}`** — chip padding
  pairs, consumed by the `chip-tight` / `chip-cozy` utilities below.
- **`--row-comfortable-py` / `--row-compact-py`** — list-row padding
  pairs.

## Easing curves

- **`--ease-overshoot`** — springy `cubic-bezier(0.34, 1.4, 0.64, 1)`.
  Toasts and attention-grabbing micro-interactions.
- **`--ease-modal-settle`** — calm `cubic-bezier(0.215, 0.61, 0.355, 1)`
  easeOutCubic. Modals, sheets, large surfaces. No overshoot.
- **`--ease-glow-cycle`** — symmetric `cubic-bezier(0.37, 0, 0.63, 1)`
  used by the breathing focus-glow keyframe.

## Animation tokens

`--animate-{modal-in, toast-in, check-pop, ring-glow, ring-glow-paused,
drop-settle, drop-afterglow, check-draw, strike-sweep, breathing-478,
ambient-drift, focus-task-in, focus-task-out, focus-footer-slide,
sparkle-draw}` — Tailwind 4 `@theme`-registered animations. Apply via
the `animation:` shorthand or the equivalent `animate-*` utility,
never by hand-coding the `@keyframes` at the call site.

R2 polish additions:

- **`drop-settle`** + **`drop-afterglow`** (#4386) — FLIP-style 280 ms
  landing + 600 ms accent halo on the just-moved task card in
  Eisenhower / Kanban / Calendar week-grid drop surfaces.
- **`check-draw`** + **`strike-sweep`** (#4385) — paired with the
  existing `check-pop` for the task-completion sequence (button pop →
  checkmark stroke draw → title strikethrough sweep → row settle).
- **`breathing-478`** + **`ambient-drift`** (#4388) — calming
  4-7-8 breathing rhythm and slow radial-gradient drift behind the
  focus-mode break screen.
- **`focus-task-in`** / **`focus-task-out`** / **`focus-footer-slide`**
  (#4389) — cross-fade choreography when the focus-mode active task
  rotates, plus an "up next" footer slide on action-in-flight.
- **`sparkle-draw`** (#4396) — 200 ms stroke-draw on the Quick
  Capture natural-language date sparkle glyph.

## Glass + profile

- **`--profile-material-{shell, panel}-saturate-{composed, standalone}`**
  (#3627) — backdrop-filter saturation pairs for liquid glass
  surfaces. Composed variants (layered atop a tint) get more
  saturation; standalone variants sit closer to the desktop and use
  a gentler boost.
- **`--glass-highlight-inset-strong`, `--glass-highlight-inset-soft`** —
  inner edge highlights for glass panels. Strong = full top-edge
  gradient; soft = secondary surfaces.

## Clarity-profile overrides

`--clarity-override-{backdrop, bg, …}` — the high-contrast appearance
profile substitutes opaque, saturated values for the translucent
glass treatments. These overrides are never read directly by
component code; the profile-scoped media block in `index.css`
swaps them in. **Do not** reference `--clarity-override-*` from
component CSS — author against the base token, and the profile
swap takes care of itself.

## Focus utilities

Two policy levels, defined as `@utility` blocks in `index.css`:

- **`focus-ring-soft`** — compact controls (icon buttons, list rows,
  chips, inline editable inputs). Single 2 px outline at +1 px
  offset. Cheap, does not fight tight layouts.
- **`focus-ring-strong`** — prominent controls (primary actions,
  CTAs, dialog buttons, anything with a solid `bg-accent` fill).
  2 px outline at +2 px offset plus a 2 px `--color-surface-0` halo
  so the ring stays legible against busy backgrounds and meets
  WCAG 2.4.7 / 1.4.11 non-text contrast.
- **`focus-ring-soft-success` / `focus-ring-soft-danger` /
  `focus-ring-soft-warning`** (#3688) — semantic-tone variants for
  controls whose primary fill is success/danger/warning rather than
  accent (e.g. green "Complete" buttons, red "Delete" confirms,
  amber "Defer" pills). Same 2 px outline + 1 px offset geometry as
  `focus-ring-soft`, anchored on the matching color token. Use these
  instead of hand-rolling `focus-visible:ring-success/60` etc., which
  is now blocked by the `focus_ring_consistency` gate.

Both accent utilities flip the outline to `--color-danger` for any
element with a non-`false` `aria-invalid` value (so `true`, `grammar`,
and `spelling` all show the danger ring — #3633). The semantic-tone
variants do not flip on `aria-invalid`: they're already a non-accent
tone, and a Complete button shouldn't switch tone on validation.

The `scripts/verify/focus_ring_consistency.mjs` gate enforces:

- Hand-rolled `focus-visible:ring-*` is forbidden — use one of the
  utilities.
- Solid `bg-accent` paired with `focus-ring-soft` is a violation.
  The halo separation only comes from `focus-ring-strong`. The gate
  excludes `bg-accent/<n>` (faded) and `bg-accent-hover` from the
  match (#3640).

## Composed `@utility` blocks

Tailwind 4 `@utility` blocks compose into class names that callers
can spell directly. Authoring in this file rather than at the call
site keeps the surface treatment shared.

- **`chip-tight` / `chip-cozy`** — chip padding pairs anchored on the
  `--chip-*` tokens. Use `chip-tight` inside dense rails, `chip-cozy`
  on standalone chips.
- **`chip-{success,warning,danger}`** (#3719, base layer re-split in
  #3756) — tone-keyed chip fill + foreground utilities. Static spans
  carry only this base; interactive sites add the `-interactive`
  modifier (below) to opt into the transition + hover step. Pair with
  `chip-tight` / `chip-cozy` for padding/radius.
- **`chip-{success,warning,danger}-subtle`** (#3744) — fainter starting
  tier (`tint-xs` instead of `tint-sm`) for quiet affordances —
  AI-suggested chips, dismissable danger badges, "completed today"
  pills. Pair with `-interactive` when hoverable.
- **`chip-{success,warning,danger}-interactive`** (#3756) — adds
  `transition: background-color 150ms` + `:hover` step. Apply
  alongside `chip-{tone}` (or `chip-{tone}-subtle`) on buttons /
  filter pills. Read-only spans should NOT carry this utility — the
  whole point of the split is to keep the transition declaration off
  static badges.
- **`tonal-surface-{success,warning,danger,accent}-xs`** (#3759) —
  faint tonal panel recipe combining `bg-[var(--{tone}-tint-xs)]` +
  `border-{tone}/15`. Use for rest-tier panels (StatCard,
  OverdueSeveritySection rows, SectionOverdueAlertCard); compose with
  structural utilities (rounded, padding) at the call site.
- **`tonal-surface-{success,warning,danger,accent}-sm`** (#3768) —
  banner-shell + standalone tonal panel recipe combining
  `bg-[var(--{tone}-tint-sm)]` + `border-{tone}/40`. Use for
  Banner-class container surfaces (OnboardingChecklist, SnapshotPanel,
  status alerts) where the tonal step needs to read at conversation
  distance rather than the rest-tier whisper of `-xs`. The /40 border
  opacity is harmonised across tones (#3776 — prior callers used /30,
  /35, /45; the consolidation darkens the quietest sites by ~0.05 alpha
  and lightens the loudest by the same amount, an intentional trade for
  one-place retuning). If a site genuinely needs a quieter or louder
  border, drop the utility and inline the recipe with a comment naming
  the consumer.
- **`heading-section` / `heading-meta`** — section heading and meta
  caption typography. Encode the size + weight + tracking once.
- **`disabled-state`** — canonical disabled affordance (opacity +
  pointer-events). Use on every disabled button, never a one-off
  `opacity-50 cursor-not-allowed`.
- **`liquid-popover-panel`, `liquid-settings-panel`,
  `liquid-sidebar-shell`, `profile-material-shell`** — glass-panel
  shells. Each inherits the liquid panel fill / shadow so a single
  retune updates every surface.
- **`clarity-first-surface`** (#3592) — opt-out switch for the
  profile-material panel/shell visuals. When a surface carries this
  utility (or contains a descendant that does), `profile-material-*`
  panels inside it flatten to the `--clarity-override-*` tokens
  defined at `:root`. **Use** on reading-first surfaces where the
  ambient glass/material treatment would harm legibility (long-form
  notes, dense data tables). **Do not use** as a generic "turn off
  effects" toggle — it is scoped specifically to the
  profile-material family.
- **`desktop-shell` / `desktop-card`** — desktop body grammar. The
  shell is the outer container; the card is the elevation step
  inside.
- **`cv-changelog-row`** — the changelog row pattern (timeline tick
  + body) used by the AI changelog and conflict log views.
- **`slide-panel`** — right-side slide-over animation shell. Encodes
  the enter/exit easing on `--ease-modal-settle`.
- **`toast-enter-exit`** — toast micro-interaction shell. Composes
  the `--animate-toast-in` token with the `--ease-overshoot` curve.
- **`progress-fill`** (#4370) — determinate progress-bar fill recipe
  that pairs with inline `transform: scaleX(<0..1>)`. Sets
  `width: 100%`, `transform-origin: 0 50%` (inline-start under LTR;
  flipped to `100% 50%` for `[dir='rtl']` ancestors), and
  `will-change: transform`. Use for any determinate progress fill
  (focus-mode queue progress, sync progress, weekly-review
  throughput, onboarding checklist). **Do not** drive the fill with
  `transition-[width]` + an animated `width` property — that forces
  layout on every frame and forfeits the GPU-compositor fast path.
- **`min-tap`** (#4374) — minimum touch-target recipe anchoring on
  `--tap-target` (44 px). Use on mobile chevrons and day-grid buttons
  whose visual size undershoots WCAG 2.5.5. Replaces inline
  `style={{ minWidth: 44, minHeight: 44 }}` literals.
- **`task-strike-sweep`** — title strikethrough sweep used by the
  task card when `isDone` flips true. Draws a 1px line via a
  `linear-gradient(currentColor)` background whose width animates
  0% → 100% over 220ms (`strikeSweep` keyframe), then the card swaps
  to a static `line-through` so the sweep is in-flight only. Hue rides
  `currentColor` so the line reads as the title draining rather than
  as a new accent. **Use** on the title row of a task card the moment
  it transitions to complete. **Do not use** for static struck-through
  text — apply `line-through` directly; this utility only earns its
  keep during the completion transition. Reduced-motion collapses to
  the final 100% line so the visual end-state still reads.
- **`break-ambient-drift`** (#4388) — slow focus-break background
  pan. The break screen owns the radial-gradient layers and background
  sizing; this utility owns only the `--animate-ambient-drift` wiring
  under `prefers-reduced-motion: no-preference`. **Use** for that
  break-screen ambient layer only. **Do not use** as a generic
  decorative motion helper or inline the animation at the call site,
  because reduced-motion handling must stay centralized.
- **`toast-success-pop`** (#4376) — success-icon stamp animation for
  success-toned toasts. Overshoot scale (0.6 → 1) over 280ms on
  `cubic-bezier(0.34, 1.56, 0.64, 1)` so the check icon "stamps" rather
  than fading in. **Use** on the icon glyph inside a `Toast` with
  `tone='success'`. **Do not use** on the toast surface itself (that
  is `toast-enter-exit`'s job) and not on neutral/warning/danger toasts
  whose register stays calm. Reduced-motion suppresses the animation.
- **`settings-autosave-check-sweep`** (#4402) — autosave-chip
  checkmark reveal. Animates `stroke-dashoffset` 14 → 0 over 360ms
  (`settingsCheckSweep` keyframe) so the saved confirmation reads as a
  stamp rather than a flicker. **Use** on the `<path>` of the
  checkmark glyph inside the Settings header autosave chip when it
  transitions to the saved state. **Do not use** on persistent
  checkmark glyphs (status icons, completed-row check) — those should
  paint statically. Reduced-motion resolves the path immediately.
- **`toast-stack-layer`** (#4398, #4402) — depth offset for stacked
  toasts. Each layer behind the frontmost shifts by
  `var(--toast-stack-depth) × -4px` translateY + a 2%-per-step
  scale-down so the visible stack reads as a card deck rather than a
  flat column. Transition is 220ms on the canonical settle curve.
  **Use** on every toast inside `ToastContainer`, setting
  `--toast-stack-depth` per layer (0 = frontmost). **Do not use** for
  single-toast surfaces or non-stack overlays — the offset only makes
  sense within the stack. Reduced-motion removes the transition but
  keeps the final stacked positions so the visual hierarchy survives.

---

## React UI primitives

Several recipes ship as React components in `app/src/components/ui/`.
They consume the tokens / utilities above but enforce the recipe at
the call site so a later retune lands once instead of N times.

- **`<Banner>`** (#3726, hardened in #3748–#3752 for cycle 32) — the
  tonal status banner used for stale-data, sync-error, calendar offline,
  notification-permission, and similar status surfaces. Owns the tonal
  shell + role / aria-live defaults + body-copy hierarchy. Props of
  note: `tone`, `title`, `density` (compact / cozy / **comfortable**
  default = `py-3`), `align` (heuristic — center when title or
  single-line body, start otherwise), `bodyTone`, `actions`, `icon`.
  Info tone now wears `border-accent/20 bg-[var(--accent-tint-xs)]` so
  it visually registers as a banner (#3751).
- **`<TonalButton>`** (#3743, `loading` added in cycle 32 #3753,
  `accent` tone added in cycle 37 #3798) — the outlined tone-coloured
  action recipe (`border border-{tone}/40 text-{tone}
  hover:bg-[var(--{tone}-tint-sm)]`). `tone`: danger / warning /
  success / **accent** (the McpSetupSection copy-snippet chips). The
  accent tone uses the canonical `focus-ring-soft` (already
  accent-tinted) since a separate `focus-ring-soft-accent` would
  duplicate the default. `size`: sm / md (default —
  `text-xs px-2.5 py-1`) / lg (`text-xs px-3 py-1.5`).
  `loading={isPending}` disables the button, sets `aria-busy='true'`,
  and prefixes the label with a small inline spinner (suppressed
  under `prefers-reduced-motion`). Pair the destructive consumers
  (DangerZonePanel, TrashPanel, DeferredTaskRow) with `loading`
  rather than the bare `disabled` + label-swap pattern.
- **`<TonalIconBubble>`** (#3758) — the circular tinted icon container
  (`w-N h-N rounded-full bg-[var(--{tone}-tint-*)]`). `tone`: success /
  warning / danger / accent / muted. `size`: xs (w-4) / sm (w-8,
  default) / md (w-10) / lg (w-12). `tint`: xs / sm / md (defaults
  pair with size — small bubbles default to `xs`, larger to `sm`).
  Used for streak flames, error badges, per-row check affordances.
- **`<Pill>`** (#3760) — the rounded-full tonal capsule (distinct from
  `chip-tight` which is square-rounded). `tone`: success / warning /
  danger / accent / muted (default). `size`: sm (`text-3xs`,
  popover-row badges) / md / lg / **cozy** (#3775 — chip-shape variant
  using `--radius-r-chip` rather than the default capsule, plus a
  taller `py-1` rhythm; reserved for panel-level status badges such as
  the TodayHeader overdue / today-pool count chips, where the count
  needs to read at panel distance rather than as a popover capsule).
  `tabular={true}` swaps to `tabular-nums font-semibold` for count
  badges.
- **`<Button>`** (POL-H7) — canonical button primitive. `variant`:
  primary / secondary (default) / ghost / **outline** (#3780). The
  `outline` variant is a self-contained recipe (text-xs px-2.5 py-1.5,
  border-surface-3, hover:bg-surface-2, focus-ring-soft) that ignores
  `size` — adopt it for "quiet bordered chip" actions: header "Select"
  toggles (UpcomingView, AllTasksView, SomedayView, TodayHeader) and
  banner inline secondary actions (NotificationPermissionBanner,
  SyncStatusBanner, StaleDataBanner). New "outline-style" buttons
  must consume this variant rather than reinventing the recipe. The
  cycle 37 sweep (#3798) migrated 12 hand-rolled chip-style buttons
  (NativeCalendarPanel, AdvancedPreferencesPanel, four SyncMethodCard
  sites, SidebarHeader's command-palette chip, LanguagePicker trigger,
  Three McpSetupSection
  reveal-config chips) onto this variant.

  `size` (canonical order — rhythm-ascending; padding-based first,
  then fixed-square icon rungs; #3827):
  - `xs` (#3816) — `text-2xs px-2.5 py-1.5` review-row sub-action
    rhythm. Pair with `variant='outline'` for the canonical quiet
    review-row affordance (StalledListRow "Open list",
    DeferredTaskRow rescope).
  - `sm` — 24-28 px tall, header chip-style actions
  - `banner` — 28 px tall (text-xs px-2.5 py-1.5; #3784) — matches the
    `outline` rhythm so a `primary` button aligns with an adjacent
    `outline` button inside a `<Banner>` action row
  - `md` — 32-36 px tall, default for stand-alone buttons
  - `lg` — 40 px tall, primary CTAs (DailyReview Save)
  - `monoChip` (#3814) — 36×36 minimum chip with
    `text-3xs font-mono leading-none` typography for command-palette-style
    header triggers carrying a glyph + inline keystroke hint (`⌘K`).
    Pairs naturally with `variant='outline'`; the outline variant is the
    one place that honors `xs` and `monoChip` typography by appending
    the size rule after the recipe.
  - `icon` (#3796) — 28×28 square hit area for stand-alone icon-only
    buttons (banner dismiss-X, modal close affordances). Pairs
    naturally with `variant='ghost'`. Emits `focus-ring-soft` (#3800)
    rather than the strong halo — icon-only buttons are compact
    controls per the focus-ring policy.
  - `icon-lg` (#3818) — 36×36 square hit area for pagination /
    navigation affordances (FocusPopoverPanel close / minimize, mobile
    focus overlay chrome). Mirrors `icon` at the larger 36-px header
    rhythm. The `outline` variant is the only one that ignores `size`;
    every other variant honors it. Internally the size map splits into
    `PADDING_SIZE` (xs / sm / banner / md / lg / monoChip) and
    `ICON_SIZE` (icon / icon-lg) so the render path consults the right
    map per size category (#3834).

- **`<ToggleChip>`** (#3812) — selectable accent chip primitive
  (promoted from `quick-capture/ToolbarChip`). The single canonical
  recipe for "small pill button that renders an idle / selected
  pair": quick-capture toolbar (DatePills, DurationDropdown,
  PriorityDropdown, TagsToggle), changelog filter chips, calendar
  view-mode segmented control, mobile list filter row, settings
  segmented controls (week start, focus break), DatePicker quick
  chips, focus-popover pause/resume pill. `tone` (#3829): `accent`
  / `warning` / `danger` / `success` — each maps to its own
  `--{tone}-tint-sm` (`/20`) rung, matching the Banner / Pill /
  TonalButton tone ladder. `size`: `xs` (`text-xs px-2 py-0.5` —
  changelog filter pills; defaults to capsule shape) / `sm`
  (`text-xs px-2 py-1` — default; quick-capture rhythm) / `md`
  (`text-sm px-3 py-1.5` — settings segmented controls). `variant`
  (#3833): `default` carries the `hover:bg-surface-3` wash;
  `segmented` drops the wash and the chip's own radius so it sits
  flush inside a bordered segmented group (calendar view-mode,
  week-start day picker, focus-break option picker). `shape`
  (#3832): `control` (default) → `--radius-r-control`; `pill` →
  `rounded-full` for capsule affordances like the focus-popover
  pause/resume chip. The selected-state fill pins to the canonical
  `--{tone}-tint-sm` rung; off-ladder alphas (`/10`, `/12`, `/15`)
  are intentionally not exposed. `selectedClassName` /
  `inactiveClassName` overrides cover the per-site exotic
  treatments (priority-color tint, danger validation ring,
  popover "running" surface fill) without spreading drift back
  across call sites.

- **`<CompactNumberInput>`** (#3789, #3795, #3799, #3803, #3809) — the
  "tight numeric stepper inside a popover / chip toolbar" recipe.
  Encodes a narrow, fixed-width `<input type='number'>` that opts
  into `.validated-input` (so a parent `aria-invalid='true'` paints
  the danger border), hides the WebKit/Firefox spinner UI (the
  surrounding toolbar typically already has explicit increment chips),
  and uses `focus-ring-soft` (POL-H8) because the stepper is one of
  several controls in its toolbar. `background`: `surface-1` /
  `surface-2` / `surface-3` (default; the duration-popover rung) —
  the resting border tracks the chosen tier through a `BORDER_CLASS`
  map (#3799) so the border reads against the fill rather than
  vanishing into it. **Disclosure (#3822):** `surface-1` and
  `surface-2` backgrounds both resolve to `border-surface-3` (the
  canonical resting border tone); only the `surface-3` background
  steps the border *down* one rung to `border-surface-2` because the
  chip is already on the brightest tier. `width`: closed union `sm` (w-12) / `md` (w-14,
  default) / `lg` (w-20) / `full` (w-full) / `flex` (flex-1). Width
  rungs are intentionally typed (#3809) — adding a new width belongs
  inside the primitive's `WIDTH_CLASS` map, not at a call site as a
  free-form Tailwind class. Consumers: DurationDropdown,
  RetentionSettingsPanel, RecurrenceField, EventRecurrenceFields,
  TaskUnifiedMetaCard.
- **`<AutosizingTextarea>`** (#3757) — long-form textarea that grows
  from `minRows` to `maxRows` based on content height, then becomes
  scrollable. Properly handles border-box accounting and resets to
  `auto` before measuring so deletions shrink the box. `resize='vertical'`
  re-exposes the native CSS resize handle for cases where the user
  should be able to override the auto-size (Notes-for-AI). Used by
  EventForm description, ReflectionSection, TitleInput body,
  NotesForAiSection.

  Hardenings to be aware of when touching this primitive:
  - **rAF coalescing** (#3770) — synchronous keystroke bursts collapse
    to one `measureNow()` per frame. The pending handle is cancelled
    on unmount and at the top of the synchronous layout-effect
    measurement (#3779) so a queued frame can't fire after the layout
    pass and stomp the height we just wrote.
  - **Webfont re-measure** (#3778) — `document.fonts.ready` triggers
    one re-measure after fallback metrics are replaced by the real
    font. The handler lives in a mount-only `useEffect` with a
    `did-fire` guard, not the value-change layout effect, so a fast
    typer doesn't accumulate one font-load handler per keystroke.

---

## Window scoping

Lorvex ships several auxiliary windows that intentionally must not
paint the standard `--color-surface-0` body fill: floating popover
panels, the focus-mode overlay, and the
Mica-effect main window on Windows all need either a transparent or
material-backed background so the host compositor's surface shows
through. The opt-out is two `<html>`-level data attributes (#3691):

- **`data-window-kind='overlay'`** — set on auxiliary windows that
  paint their own bespoke surface (popover, focus-mode overlay).
  Anything matching this attribute is excluded from the
  unconditional `html, body { background: var(--color-surface-0) }`
  fallback at the top of the `@layer base` block, and from the
  `bg-surface-0` `@apply` further down.
- **`data-window-transparent`** — set on windows that need a fully
  transparent body so the desktop or another window paints through
  (e.g. command-palette frame, drag preview). Same exclusion contract
  as `overlay`.

`bg-surface-0` does **not** apply to overlay or transparent windows.
A new auxiliary window kind opts out by setting one of these
attributes on the document element at boot (Tauri main process
injects them based on the window's role); the CSS guards do the
rest. The body remains `text-text-primary` and inherits typography
across every window kind — only the background paint is scoped.

Mica is theme-keyed, not window-kind-keyed (the same window switches
between Mica and standard themes at runtime), so it has its own
`!important` override at `:root[data-theme='mica']` that wins against
the unscoped fallback by force rather than by selector specificity.

---

## Profile-material composition tokens (#3673)

The `profile-material-shell` and `profile-material-panel` utilities
compose translucent surfaces from a fixed parameter set so a profile
retune lands once instead of being respelled per consumer.

- **`--profile-material-shell-alpha-top` /
  `--profile-material-shell-alpha-bottom`** — vertical gradient
  endpoints for the shell fill. Top is the "bright" edge; bottom
  meshes into the desktop background.
- **`--profile-material-shell-blur`** — backdrop-filter blur radius
  for the shell. Tune per profile; never inline.
- **`--profile-material-shell-saturate-composed` /
  `--profile-material-shell-saturate-standalone`** — backdrop-filter
  saturation, with separate values for the in-window-chrome composed
  context vs. a standalone shell rendered alone (e.g. a tear-out).
- **`--profile-material-panel-alpha-top` /
  `--profile-material-panel-alpha-bottom`** — same vertical gradient
  endpoints for inner panels (settings, popovers).
- **`--profile-material-panel-blur` /
  `--profile-material-panel-saturate-composed` /
  `--profile-material-panel-saturate-standalone`** — backdrop-filter
  controls for inner panels, mirroring the shell tokens.
- **`--profile-material-border-alpha`** — alpha value for the inner
  hairline border the panel/shell paints to crisp the edge against
  the desktop bleed-through.
- **`--profile-material-highlight-alpha`** — alpha for the top inset
  highlight that makes the surface read as glass rather than tinted
  paint.

## Shell card / panel tokens (#3673)

Some themes (mica, adwaita, liquid) collapse the elevation of inner
cards/panels to ride the OS-level material rather than paint their
own. The `--shell-card-*` and `--shell-panel-*` tokens absorb that
divergence in one place so the shared `.desktop-card` /
`.profile-material-panel` rules stay token-driven.

- **`--shell-card-bg`** — desktop-card fill color when the host
  theme delegates the card material to the OS shell.
- **`--shell-card-backdrop`** — corresponding backdrop-filter on
  desktop-card when the OS material is in play.
- **`--shell-card-border-color`** — single-edge border color for
  desktop-card (the rule uses logical `border-inline-end` only).
- **`--shell-card-border` (#3668)** — full `border:` shorthand value
  consumed by `@utility desktop-card`. Themes that want a flat shell
  set it to `none`; default themes inherit a translucent
  surface-3-alpha border via the var() fallback.
- **`--shell-card-border-inline-end` (#3668)** — `border-inline-end:` shorthand
  consumed by `@utility desktop-card`. Structural-override themes
  retune to `1px solid var(--shell-card-border-color)` to paint a
  single edge stroke; default themes inherit `--shell-card-border`.
- **`--shell-card-radius` (#3668)** — corner radius for desktop-card.
  Defaults to `1.15rem`; structural-override themes retune to `0` for
  a flush, full-bleed shell.
- **`--shell-card-shadow` (#3668)** — `box-shadow:` for desktop-card.
  Defaults to `var(--shadow-desktop-card)`; structural-override themes
  retune to `none` so the OS material owns elevation.
- **`--shell-bg` (#3668)** — backdrop for `@utility desktop-shell`.
  Default is the layered gradient; structural-override themes retune
  to a flat color so the DWM/Adwaita/glass material shows through.
- **`--shell-panel-bg` / `--shell-panel-backdrop`** — same role for
  inner panels (settings, profile-material-panel).

## Structural panel tokens (#3673)

The `--structural-panel-*` tokens encode the inner panel's frame
(border / radius / shadow) so a profile change updates every consumer
without each rule respelling the trio inline.

- **`--structural-panel-border`** — full `border:` shorthand value
  (width + style + color).
- **`--structural-panel-radius`** — corner radius, scaled by
  `--profile-radius-scale` so a profile that wants softer corners
  retunes once.
- **`--structural-panel-shadow`** — elevation shadow for the panel
  frame.

## Platform / profile tokens

The `windows` / `windows_light` and `adwaita_dark` / `adwaita` themes
import primitives that match each host platform's native control
chrome rather than being authored from the surface ladder alone.
These primitives are scoped to their owning theme block and are not
read from cross-theme component code — they participate in the
theme's structural-override recipe (border, sidebar, headerbar) only.

### Windows (Fluent) primitives

Defined inside `:root[data-theme='windows']` and
`:root[data-theme='windows_light']`. Map to Microsoft's Fluent
control-stroke / subtle-fill ladder so Lorvex's buttons / inputs /
cards inherit the host-platform stroke vocabulary.

| Token | Role |
| --- | --- |
| `--win-control-stroke` | Hairline stroke for control surfaces (buttons, inputs) — top + side edges |
| `--win-control-stroke-bottom` | Darker bottom edge (Fluent's "highlight bottom border") that gives controls their pressed-edge depth cue |
| `--win-card-stroke` | Hairline stroke for card surfaces — softer than `--win-control-stroke` to let cards read as content rather than interactive |
| `--win-subtle-fill` | Fluent "subtle" interactive fill (resting state for ghost-style controls) |
| `--win-secondary-fill` | Fluent "secondary" fill (resting state for filled controls) |
| `--win-control-fill` | Fluent "control" fill (input fields, baseline filled controls) |

**Use** only inside the windows theme's structural-override recipes
(`--shell-card-border-color`, `--shell-card-bg`, structural panel
border). **Do not** read these from component CSS.

### Adwaita (GNOME) primitives

Defined inside `:root[data-theme='adwaita_dark']` and
`:root[data-theme='adwaita']`. Map to libadwaita's
border / shade / inner-highlight vocabulary so Lorvex blends into a
GNOME shell.

| Token | Role |
| --- | --- |
| `--adw-border` | Resting Adwaita panel hairline |
| `--adw-border-strong` | Emphasized Adwaita hairline (focused / selected) |
| `--adw-view-bg` | View (content) background |
| `--adw-sidebar-bg` | Sidebar / rail background |
| `--adw-headerbar-bg` | Header-bar background |
| `--adw-shade` | Resting shade overlay (drop / inner) |
| `--adw-card-shade` | Card-tier shade overlay (heavier than `--adw-shade`) |
| `--adw-btn-gradient` | Button background gradient (`none` to opt out) |
| `--adw-btn-shadow` | Button drop shadow (`none` to opt out) |
| `--adw-entry-shadow` | Entry (input) inner shadow (`none` to opt out) |
| `--adw-inner-highlight` | Inner top-edge highlight (`none` to opt out) |

**Use** only inside Adwaita-scoped structural overrides. **Do not**
read from cross-theme component code — the Adwaita treatment is the
theme block's contract, not the surface ladder's.

## Theme radius tokens (#3673)

- **`--profile-radius-scale`** — multiplier applied across the
  `--radius-r-*` ladder for profiles that want larger (or smaller)
  rounding without rewriting every individual radius token.
- **`--theme-radius` / `--theme-radius-sm` / `--theme-radius-lg`** —
  ember/midnight radius overrides consumed by the global form-control
  selectors. New themes should prefer the `--radius-r-*` ladder.

---

## When you change a token

1. Update the value in `app/src/index.css`.
2. Update the role here if the contract changed.
3. Re-run the canonical token/static gates:
   `npm run verify:theme-tokens`,
   `npm run verify:design-tokens-completeness`,
   `npm run verify:utility-completeness`,
   `npm run verify:focus-ring-consistency`,
   `npm run verify:motion-reduce-redundancy`, or the full
   `npm run verify:frontend-static-contracts` bundle when the change
   touches shared theme/static contracts.
4. Re-run `npm run -w app typecheck`.
5. Snapshot tests for a few representative surfaces (Today view, a
   modal, a toast) to verify the visual weight is intact.
