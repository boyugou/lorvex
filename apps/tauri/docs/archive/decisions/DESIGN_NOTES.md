# Design Notes & Decision Log

> Archived historical document. Preserved for reference only; not part of the current implementation contract.


> Historical reasoning log only. This file explains how the design evolved; it is not the canonical product or schema contract.
>
> Current source of truth:
> - architecture and data model: `docs/design/ARCHITECTURE.md`, `docs/design/DATA_MODEL.md`
> - workflow and feature semantics: `docs/design/FEATURES.md`, `docs/design/MCP_TOOLS.md`

*Running log of design thinking, decisions, and open questions. This document captures the reasoning process so future developers/AI agents understand WHY things are the way they are, not just WHAT they are.*
---

## Session 1: Initial Design

### Starting Point
The project began from a conversation about building an AI-native macOS task manager. Initial direction from the user:

1. AI should be the primary operator (creates, manages, analyzes tasks)
2. Human primarily reads/reviews — not manages
3. MCP integration so an assistant client can control the app
4. Don't just mimic existing task managers — think from first principles about what AI-native means
5. Distribution was undecided at the time; the current Tauri line is direct desktop distribution only.

### Key Design Evolution During This Session

**Evolution 1: From "todo app with AI features" to "AI planning system with a human dashboard"**

We started by looking at a traditional task manager's feature set and thinking about which features to replicate. This was the wrong starting point. The breakthrough was inverting the question: instead of "which human features do we add AI to?", ask "what does the human need to see, given that AI does the work?"

This led to the "chief of staff" mental model: Claude is the operator, the app is the briefing.

**Evolution 2: From traditional sidebar layout to radical simplicity**

The first UX draft had a permanent sidebar with smart views, list navigation, badges. This is the standard pattern for traditional task managers.

On reflection, this was wrong. A permanent sidebar exists because the human needs to navigate between views to make decisions. In our app, the human mostly looks at one view (today's briefing) and occasionally checks the inbox. Navigation should be on-demand, not permanent.

Result: no permanent sidebar. Full-width content. Navigation via command palette (⌘K) or a transient panel.

**Evolution 3: From metadata-rich task rows to minimal task rows**

First draft had: checkbox + title + list badge + priority dots + duration per task row. Five elements.

Revised to: checkbox + title + duration. Three elements.

Reasoning: list badge and priority dots were there to help the human evaluate tasks. But AI already evaluated them — that's why they're in the Focus section. The human doesn't need redundant metadata to make a decision the AI already made.

**Evolution 4: The Inbox as an intent-verification interface** *[REMOVED — inbox was replaced by the conversation-as-review-layer model]*

The user pointed out that AI errors are intent errors, not data errors. This changed how the Inbox should work. It's not just accept/reject — it's a **verification interface** where the human sees AI's interpretation alongside their original input, and can correct inline.

Before: Inbox cards had Accept / Reject / Edit buttons
After: Inbox cards are entirely inline-editable. Every field is tappable. Correction is as cheap as creation.

**Evolution 5: Todo ↔ Calendar relationship**

After studying the scheduling approaches across the productivity-tool categories — unified timelines, auto-scheduling onto the calendar, calendar-time defense, and manual time-boxing rituals — we arrived at a clean model:

- Tasks = flexible commitments (our core domain)
- Calendar events = fixed appointments (now represented in a lightweight local event model)
- Schedule = AI's synthesis of both (our output)

We do NOT build a full calendar suite. We keep calendar-event support intentionally narrow (create/edit/delete/query fixed commitments) so scheduling stays realistic, while avoiding heavy calendaring complexity.

**Evolution 6: Focus Mode**

A "one task at a time" view emerged from combining the One Thing methodology, ADHD-friendly design principles, and a "what am I doing right now" focus. Full-screen, one task, Done button. Next task slides in.

This is a genuinely distinctive interaction pattern and could be a signature feature.

---

## Category Research Insights

### AI Auto-Scheduler Failure Modes (And We Must Not Repeat)
1. Black box AI — no transparency, no reasoning, no audit trail
2. Loss of agency — tasks get bumped without warning or explanation
3. Steep learning curve (weeks before value)
4. Metadata burden — still requires manual priority/deadline/duration entry
5. Poor deadline miss handling

### What Guided Rituals Get Right (And We Should Amplify)
1. A structured daily focus ritual is genuinely valuable
2. Duration estimation as a core concept
3. Anti-burnout design (capacity warnings)
4. BUT: the ritual takes 15 min because it's fully manual. Ours should take 1 min because AI pre-populated it.

### What Semi-Automatic Schedulers Get Right (And We Should Evolve)
1. Duration is not optional — a task without duration is a wish
2. Day-as-timeline is the right mental model for scheduling
3. Auto-schedule from a start time is a powerful mechanic
4. BUT: the algorithm is dumb (greedy sequential packing). Ours should be AI-reasoned.

### Universal Gap We Fill
No existing product does the full loop: capture → organize → prioritize → schedule → review. Every tool automates one step and leaves the rest to the human. We automate the entire loop.

---

## Productivity Methodology Synthesis

Research covered: GTD, Time Blocking (Cal Newport), Ivy Lee Method, Eat the Frog, Eisenhower Matrix, PARA (Tiago Forte), Energy Management (Tony Schwartz), and newer AI-era approaches.

### The Meta-Insight
Every methodology that works has the same problem: **it requires manual labor to maintain.** GTD's weekly review: 90 min. Time blocking: daily re-planning. Ivy Lee's 6 tasks: nightly selection. People set up systems, maintain them for weeks, then abandon them when life gets busy.

**AI eliminates the maintenance layer.** The methodology still works — the practices are sound. But the human doesn't have to do the maintenance. AI does.

### What We Inherited From Each Method

| Method | What we took | How AI automates it |
|---|---|---|
| GTD | Capture everything into a trusted system | Claude captures from conversation |
| GTD | Weekly review is critical | AI pre-populates; human reviews in 15 min |
| Ivy Lee | Pick 6 tasks, prioritize, do them in order | AI picks 3-6 focus tasks each morning |
| Eat the Frog | Do the hardest/most important thing first | AI ranks by leverage + deadline + blocks |
| Time Blocking | Every task needs a time slot and duration | AI proposes time-blocked schedule |
| Energy Management | Match task type to energy level | AI learns your patterns and schedules accordingly |
| Eisenhower Matrix | Distinguish urgent from important | AI classifies on arrival; surfaces Q2 work |

### Failure Modes We're Designing Against

1. **Capture-but-never-process** → AI processes automatically; Inbox is a quick review, not processing
2. **List grows, confidence shrinks** → AI maintains, prunes, and surfaces only what's relevant
3. **Complexity as procrastination** → Radical simplicity in UI; no system to fiddle with
4. **No commitment mechanism** → AI proposes schedule = time commitment, not just a list
5. **Urgency bias** → AI proactively surfaces important/non-urgent work before it becomes crisis

---

## Open Questions (Require User Input Eventually)

1. **Launch display name** — finalized as `Lorvex`.

2. **Tech stack finalization** — Tauri 2.x + React + TypeScript is the current plan. Worth validating before coding starts. Alternative: pure Swift/SwiftUI for truly native macOS experience (but worse AI codegen support).

3. **Calendar integration scope for v1** — Read Apple Calendar? Or defer to later? Reading calendar is essential for scheduling proposals but adds complexity.

4. **Distribution model** — To be decided after MVP. Depends on whether the app calls AI APIs directly or only via MCP through Claude Desktop.

5. **In-app AI vs. MCP-only** — Should the app itself have a built-in conversation interface, or is MCP via an external assistant client sufficient? Current lean: MCP-only for v1. The app doesn't need its own AI chat when an assistant client already exists.

6. **What "AI maintains the system" means operationally** — How often does AI recompute urgency scores? Is it triggered by events (task created, deferred, completed) or on a schedule (every hour, every morning)? Currently: event-triggered + daily morning recomputation.

---

---

## Session 2: Critical Corrections

Two important corrections from the user:

### Correction 1: Humans need to browse all their tasks

The radical simplification went too far. We removed browsing capability. But humans NEED to:
- See all their work tasks
- See all their personal tasks
- Browse a specific project/list
- Scan upcoming deadlines
- Review completed tasks

This is basic reading functionality. The simplification should remove *management controls* (priority dropdowns, sort buttons, complex forms), NOT *reading views*.

**Resolution:** Two modes of task display:
- **Curated views (Today, Focus Mode):** Minimal task rows (checkbox + title + duration). AI already filtered and ordered.
- **Browsing views (List view, All Tasks, Next 7 Days):** More context per row (title + due date + duration + priority indicator). Enough metadata for the human to understand their landscape.

Sidebar restored as collapsible (not permanent, but available). Shows smart views + user lists for navigation.

### Correction 2: The app contains no AI

The app does NOT call the Anthropic API. It does NOT embed an LLM. It does NOT parse natural language.

The app is:
- A task management GUI (React frontend)
- A SQLite database
- An MCP server that exposes the database to Claude

All intelligence comes from Claude Desktop connecting to the MCP server. Specifically:
- Quick Capture creates a raw task (just title text). No AI parsing in the app.
- "AI Focus" tasks exist because Claude set a field via MCP.
- AI briefing notes exist because Claude wrote them to a DB field.
- Urgency scores can be computed by a simple formula in the app backend, or by Claude via MCP.
- AI Changelog is a table that Claude writes to. The app just displays it.

This is a cleaner architecture: the app is a beautiful, functional, "dumb" task manager. Claude makes it smart from the outside.

**Implications for features:**
- Quick Capture: no "Sending to Claude..." spinner. Just creates a task. Period.
- In-app conversation panel: removed from scope. Use Claude Desktop for AI interaction.
- No Anthropic SDK dependency in the app itself.

---

### Historical Multi-Device Strategy Retired

This section used to describe a Tauri-owned iPhone client and iCloud sync path.
That direction is retired. Apple-platform production work now belongs to the
Swift app under `apps/apple`; the Tauri line keeps Windows/Linux product-facing
desktop builds, a macOS developer/reference build, provider-neutral sync
infrastructure, and a possible future Android path.

---

## Design Principles Summary (Quick Reference)

0. Radical Simplicity — Less UI because AI decides
1. AI can read and write everything
2. Action space designed for AI (atomic + batch + semantic operations)
3. Inbox as trust infrastructure
4. Priority is dynamic, not a label
5. Duration is a first-class citizen
6. Views are AI-curated, not raw data
7. Human actions are minimal and fluid
8. The app speaks to you, you don't speak to the app
9. AI errors are intent errors — design for cheap correction
10. AI has global context — use it for cross-project intelligence

---

## File Map For Future AI Agents

If you're an AI coding agent reading this project:

**Core Design (read first):**
1. `docs/VISION.md` — what this product IS and why it's different
2. `docs/DESIGN_PHILOSOPHY.md` — the 11 design principles governing every decision
3. `docs/UX.md` — visual design, layout, interaction patterns

**What to Build:**
4. `docs/FEATURES.md` — feature set, organized by tier
5. `docs/DATA_MODEL.md` — full SQLite schema
6. `docs/ARCHITECTURE.md` — tech stack, system diagram, multi-device strategy

**How It Works:**
7. `docs/CLAUDE_OPERATING_MODEL.md` — how Claude actually uses MCP tools (operational playbook)
8. `docs/COMMAND_PALETTE.md` — ⌘K design, search, and full command set
**Context:**
9. `docs/COMPETITIVE_LANDSCAPE.md` — market analysis
13. `docs/DESIGN_NOTES.md` (this file) — decision log and reasoning journey
14. `CLAUDE.md` — project-level coding instructions

The most common mistake will be building a traditional todo app with AI bolted on. Every decision should be tested against: "Would this UI element/feature exist if AI wasn't doing the work?" If no, remove it.
