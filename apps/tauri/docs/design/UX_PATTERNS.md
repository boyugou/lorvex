# UX Patterns — Uniform Edit Hierarchy

Status: canonical. Last revised 2026-04 alongside #2450.

This document defines the uniform rule for *editing* metadata on entities in
Lorvex. Editing the same kind of element — a title, a name, a date —
follows the same surface across every entity, so a user who learns one
entity's rule applies it to the next without relearning.

## The rule

Pick the surface by **field cardinality**, not by entity. Every editable
field on every entity follows one of three patterns, and the choice is
determined exclusively by the table below.

| Surface              | When                                                                 | Behaviour                                                                                                                       |
| -------------------- | -------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------- |
| **Inline edit**      | A single short scalar field (title, name, single-line text).         | Click or `e` on the field. The surrounding chrome stays put; the value transforms into a focused input. Save on Enter or blur, cancel on Esc. No modal, no panel, no route change. |
| **Card-expand**      | A small bounded set of related fields (≤ ~8 fields, no nested lists). | The triggering element grows in place into a form. Surrounding context (other items in the list, the day's events) stays visible. Save / cancel buttons commit explicitly. |
| **Dedicated route**  | Multi-field with rich content (long body, attachments, checklists).  | Open a side panel (desktop) or full route (mobile). The panel coexists with the background list — clicks outside don't dismiss. Drafts auto-save on field blur. |

## How to read the rule

1. Count the editable fields. Title only? Inline. Title + a few attributes?
   Card-expand. Title + body + attachments + nested items? Dedicated route.
2. Apply the same rule across entities, not per-entity. Two entities with the
   same field cardinality use the same surface, full stop.
3. Read-only entities (AI-managed memory, habit metadata) display an explicit
   "AI-managed" affordance in place of the inline editor. The affordance is a
   subtle pill that says "Ask your AI assistant to change this" — never a
   pencil icon, never a clickable input that fails on submit.

## Mapping by entity (after #2450)

| Entity            | Field             | Cardinality | Surface          |
| ----------------- | ----------------- | ----------- | ---------------- |
| List              | name              | 1           | Inline           |
| List              | description       | 1           | Inline           |
| Task              | title             | 1           | Inline (`e`)     |
| Task              | full edit         | many        | Dedicated route (side panel) |
| Calendar event    | full edit         | ~8          | Card-expand      |
| Habit             | name / cue        | —           | AI-managed pill  |
| Habit             | frequency / target | —          | AI-managed pill  |
| AI memory entry   | content           | —           | AI-managed pill  |
| Notes for AI      | content           | 1 (block)   | Inline (block-level) |
| Daily review      | per-question      | several     | Card-expand      |
| Tag display name  | name              | 1           | Inline           |

If you see a UI in the codebase that violates this table, fix it. Don't add
a fourth pattern.

## Anti-patterns to refuse

- **Modal popups for single fields.** A modal interrupts navigation flow for
  a one-line edit. Use inline.
- **Pencil icons that open modals for short fields.** Click the field
  directly; pencils suggest "compose," not "rename."
- **Save / Cancel buttons on inline edits.** Inline edits commit on blur or
  Enter. Buttons make the user think the edit is heavier than it is.
- **Card-expand for one field.** If the edit fits in one input, don't bloat
  it into a card form.
- **Read-only display that *looks* editable.** A clickable-looking title that
  silently fails or opens a docs link confuses users. Use the AI-managed pill
  affordance — visually distinct, accompanied by a copy-prompt button if the
  edit must round-trip through the assistant.

## Onboarding scaffolding

The onboarding flow itself follows the same rule with one explicit exception:
the **OnboardingChecklist** is a non-modal sidebar card (always-visible,
dismissible per-row) so the user can refer to it while exploring the rest of
the UI. The Welcome view, by contrast, is a card-expand on the empty Today
state plus a re-openable modal from the Help menu. See `components/onboarding/`
for the implementation and `components/today-view/WelcomeView.tsx` for the
empty-state copy.

## Discoverability

- A persistent **help button** in the sidebar opens a Help menu containing:
  re-open Welcome tour, Keyboard shortcuts cheatsheet, Onboarding checklist.
- The keyboard-shortcuts cheatsheet remains reachable via `?` and via the
  titlebar `?` glyph on platforms that show a title-bar overlay.
- The OnboardingChecklist re-surfaces if any step regresses (sync turned off,
  MCP binary missing, etc.) so a returning user gets corrective guidance
  without having to remember the help menu.

## Design tokens & focus utilities

The frontend's visual language is encoded in shared CSS custom properties
and `@utility` blocks defined in `app/src/index.css`. The canonical
reference — every token family, every utility block, when to use each
and when not to — lives in
[DESIGN_TOKENS.md](DESIGN_TOKENS.md). UX_PATTERNS focuses on
*pattern composition* (how toasts, sheets, and overlays use the
tokens); the token reference is the catalog itself.

The high-level shape:

- **Color** — surface ladder, accent ladder + the `--accent-tint-*`
  ladder (#3642), text ladder, semantic feedback colors.
- **Borders** — `--border-surface-3-soft` for soft hairlines (#3643).
- **Radius / shadow / z-index / typography** — discrete scales; pick
  the named step rather than literal values.
- **Animation + easing** — three named curves
  (`--ease-overshoot`, `--ease-modal-settle`, `--ease-glow-cycle`)
  composed into Tailwind 4 `@theme`-registered animation tokens.
- **Glass / profile** — liquid panel fills, material backdrop
  saturation pairs, highlight insets; profile-scoped overrides for
  the high-contrast clarity profile.
- **Focus utilities** — `focus-ring-soft` / `focus-ring-strong` plus
  the `focus_ring_consistency.mjs` gate that enforces them.
- **Composed `@utility` blocks** — chip / row / heading / panel /
  shell / animation shells.

See [DESIGN_TOKENS.md](DESIGN_TOKENS.md) for the role catalog and
the per-token guidance on when each is the right pick.
