# Design Philosophy
---

## The day Lorvex helps with

A morning plan can become obsolete by lunch. Meetings run over, a task takes
longer than expected, or a new deadline lands. Recording each change costs
time, especially when the original plan lives in a chat and the calendar and
task list live elsewhere.

Lorvex gives a person and their connected assistant one working plan. An
assistant on the Mac can read the calendar and schedule a task. The person
can start it from Today, write what happened in Daily Review, and move the
unfinished work to another day. When the assistant next checks the schedule,
it sees the new date.

Three moments guide the product work. In the morning, can I see what fits
around my meetings? When a meeting ends, can I find the task I meant to
resume? When I close my day, can I trust that an unfinished plan will turn
up where I put it? Use those questions to evaluate the native app and the
assistant's actions together.

## What the person and the assistant each do

People can use the native apps on their own or connect an assistant through
the Mac's Model Context Protocol server. Both paths edit the same tasks and
plans. The person chooses how much organizing work to delegate.

| Moment | What an assistant can prepare | What the person can decide in the app |
|---|---|---|
| Planning the day | Read the calendar and suggest slots for tasks with duration estimates. | Accept a time, change it, or leave a task untimed. |
| Returning to work | Read the day's plan and identify an unfinished task. | Start it, resume a different task, or revise the plan. |
| Closing the day | Read the day's task record and help draft a review when asked. | Write what mattered, move one task, or park it in Someday. |

Assistant actions run during a connected session. The Mac hosts MCP, and
Mac, iPhone and iPad each support direct planning and review. With iCloud sync
enabled, an edit made on one device reaches the others.

---

## Inspiration From Productivity Research

Decades of productivity research converge on a set of practices that consistently work for high performers. The tragedy is that all of these practices require manual labor to maintain. AI eliminates that labor:

### GTD's Capture → AI handles automatic capture
David Allen's insight: every incomplete commitment stored in your brain creates cognitive drain (Zeigarnik Effect). The solution is to capture everything into a trusted system.

**AI implementation:** During an active assistant session or explicit capture flow, the AI assistant turns stated commitments into structured tasks. When you tell the assistant "I need to call Marcus about the project" or send the thought through quick capture, it can create the task with context and provenance. Your task list fills itself from user-invoked flows, not silent background monitoring.

### GTD's Weekly Review → AI pre-populates, human approves in 15 min
The weekly review is GTD's critical success factor and most commonly skipped practice. It takes 60-90 minutes manually.

**AI implementation:** Before your weekly review, AI assistant has already: identified projects with no next action, flagged tasks aging past 2 weeks, surfaced Someday/Maybe items that have become relevant, and drafted a summary of what was accomplished. You spend 15 minutes making decisions, not doing clerical work.

### Time Blocking → AI builds the schedule
Cal Newport's core insight: protecting time for important, non-urgent work before urgency can crowd it out.

**AI implementation:** AI assistant knows your calendar, your task list, and your priorities. When you ask it to plan, it proposes a time-blocked schedule. You approve or adjust. Auto-scheduling, but with intelligence: AI picks which tasks belong today, not just packs them sequentially.

### Ivy Lee Method → AI proposes the day's short list
The Ivy Lee Method works because it eliminates morning decision fatigue. But choosing the right short list still requires judgment.

**AI implementation:** When you ask it to plan your day, AI assistant proposes as many tasks as the day's free time holds, measured by their estimates against the hours left after meetings, and ranked by a combination of: deadline proximity, dependency chains, and stated priorities. Human confirms or adjusts.

### Eisenhower Matrix → AI classifies on arrival
Urgent/important classification is valuable but tedious to apply manually to every task.

**AI implementation:** As tasks are created, AI assistant classifies them. When you plan with it, it can also flag when your Q1 (crisis) load is too heavy and surface Q2 (important/non-urgent) work before it becomes crisis.

---

## Design Tenets

### Task management depth we keep
- Smart views (Today, Next 7 Days) as the primary daily interface
- Multi-list organization
- A rich task metadata model (priority, due date, duration, tags, checklists)
- Sticky note floating windows
- Menu bar quick capture

### Where we go further than a human-operated todo app
- Organization is not left entirely manual — the AI does it.
- Priority is a computed, dynamic state, not a static label set once and forgotten.
- Scheduling is load-aware: the system understands how full the day already is.
- The calendar is part of the organizing paradigm, not a separate, disconnected pane.

### Time as a first-class citizen
- **Duration as a required concept.** Every task takes real time. A todo list without duration estimates is a wish list.
- **Day-as-timeline as an optional view.** When you want to see your day as concrete time blocks, this view should be available.
- **Auto-schedule as a core mechanic.** The ability to go from "pile of tasks" to "scheduled day" in seconds.
- **Low-friction batch rescheduling.** When the plan breaks (it always does), batch-move blocks with minimal effort.
- **Native platform aesthetic.** No cross-platform compromise. Platform conventions are a feature.

### Where we go further than a sequential auto-scheduler
- Auto-schedule should be AI-reasoned — which tasks belong today at all? — not a greedy sequential packing algorithm.
- Duration estimates should be AI-proposed from task patterns, not stay forever manual.
- The product needs real project/backlog depth, not just a day's worth of tasks.
- The AI should propose what goes on today's schedule, not leave that decision entirely to the human.

---

## AI-Native Design Principles

### 0. Radical Simplicity — Less UI Because AI Decides
The most important design principle, and the one most likely to be forgotten during implementation:

**Every UI element exists because the human needs it to make a decision. If AI makes the decision, the UI element is unnecessary.**

- Priority dropdowns should not be default row chrome; Quick Capture and task detail can expose priority correction controls.
- Sort controls should not drive the default Today experience; browsing/power-user views can expose scoped sort options.
- Filter bars should not be the default briefing interface; full-list and upcoming views can expose filters for inspection.
- List assignment pickers should not be required in the default task row; Quick Capture, task detail, and move-to-list flows can expose list correction controls.
- Permanent sidebar should not dominate the app (you mostly look at one view).
- Complex creation forms should not be primary; optional metadata controls stay secondary/collapsible.

Current-product exception: AI-managed priority remains canonical, while human override and power-user controls are shipped correction affordances. Quick Capture, task detail, context menus, filters, and move-to-list controls are valid when they help the user correct AI output, inspect a full workspace, or make a deliberate power-user adjustment. They must not become the default task-row management model.

What remains: a reading experience with occasional taps. Checkbox, title, duration. That's a task row. The daily view is a clean briefing, not a spreadsheet-style management grid. A briefing still leaves nothing out: every task the user or the assistant put on today stays in view, in the plan's order. Simplicity removes controls, never the work; only records, such as what is already done, fold away.

This is not minimalism for aesthetic reasons. It's minimalism because **the AI already processed the complexity and presented the conclusion.** The human doesn't need to see the inputs when they can see the output.

Test every UI element against: "Would this exist if AI didn't?" If yes, keep it. If no, remove it.

### 1. AI Can Read and Write Everything
No field is read-only to AI. No operation is unavailable via MCP. The data model is designed for AI first, UI second. Every attribute has a clear semantic definition. AI notes are a first-class field, not an afterthought.

### 2. Action Space Is Designed for AI
The MCP tool API prioritizes:
- **Atomic operations** with clear semantics (update any field)
- **Batch operations** (create/update/complete multiple tasks in one call — LLM tool calls have latency)
- **Semantic operations** (reorganize_by_priority, schedule_day, daily_brief — high-level operations that compress what would otherwise be 10 calls into 1)
- **Rich return values** (every write operation returns the full updated object — AI never needs a second call to confirm state)
- **Context-rich queries** (get_overview returns a situational snapshot; AI doesn't have to issue 5 queries to understand the current state)

### 3. Conversation as the Trust Layer

AI should be aggressive about creating and organizing tasks. But humans must feel in control of their commitments. The conversation with the AI assistant serves as the reconciliation layer:

```
AI assistant conversations
           ↓
  AI proposes tasks in conversation
           ↓
  Human reviews, confirms, or corrects in real-time
           ↓
  AI creates tasks directly in active lists
```

High-confidence AI actions (you explicitly asked for a task) are created directly. Lower-confidence actions (AI inferred a commitment) are discussed with the user in conversation before creating.

### 4. Priority Is AI-Managed, Not a Formula
Tasks have a priority level (1–3) set by the AI assistant based on full context — deadlines, dependencies, defer history, user energy. The AI manages priority dynamically: it can reprioritize as deadlines approach or circumstances change. Tasks sort by priority then due date — simple, transparent, no opaque computed scores.

The human sees: clear priority + due date. Not a magic number.

### 5. Duration Is a First-Class Citizen
Every task should have a duration estimate. Without duration, scheduling is fiction. AI:
- Proposes duration estimates from task type and similar past tasks
- Warns when today's scheduled tasks exceed available time
- This is one of our most important insights: a task without a duration estimate cannot be scheduled honestly

The estimate is what drives scheduling. Lorvex deliberately does **not** track actual
time-on-task — see the non-goals.

### 6. Views Are AI-Curated, Not Raw Data
The human-facing interface is a curated presentation over persisted planning state, not a raw table browser. AI decides:
- Which tasks belong on today
- How to order the backlog

Humans can always see everything (search, full lists) but the default view is the AI's editorial curation.

### 7. Human Actions Are Minimal and Fluid
The human's UI action set is ruthlessly minimal:
- **Complete** (tap checkbox)
- **Defer** (push to tomorrow / next week / someday)
- **Delete** (with undo)
- **Edit title** (double-tap inline)
- **Open as sticky** (for tasks needing ambient visibility)

No drag-to-reorder as primary organization: AI handles order. AI-managed priority remains canonical, while human override and power-user controls are shipped correction affordances. Quick Capture, task detail, context menus, browsing filters, and move-to-list flows let the user correct AI output without turning the daily view into a database editor. Complex forms remain non-primary and should stay collapsed or secondary.

### 8. You Tell the AI, Not the App — and the App Stays Calm
Input is conversational: you tell the AI what you need instead of filling out forms. You then
read the result in a calm, curated surface — Today, your plan, what changed — opening the
app when you want to see where things stand. The app does not push a stream of notifications or
nudges at you, and it does not act as a proactive assistant that reaches out on its own; it is a
read-and-correct surface, not a notification stream. (Reminders you deliberately set on a task or
habit still fire — those are your reminders, not the app speaking on its own.)

---

## The Mental Model: Chief of Staff

The best analogy for this app is **having a brilliant chief of staff.**

A good CoS:
- Captures everything you mention and turns it into action items
- Maintains your project list and keeps it current
- Schedules your work around your commitments
- Does the weekly review prep so the meeting takes 15 minutes
- Remembers context you've forgotten ("this task came out of your March meeting with X")
- When you ask, reasons over everything at once — cross-project deadlines, where you left off, what's slipping

You don't manage your CoS's filing system. You don't tell them what format to use. You give them context, make decisions, and do the actual work.

That's this app.

---

## The Two Audiences: AI Operations + Human Cognition

The app serves two complementary purposes:

### 1. Best-in-class MCP surface for AI task management

This is a core differentiator. On capable desktop runtimes, the MCP server gives assistants rich semantic control over planning, prioritization, scheduling, review, and system maintenance. The data model is deliberately machine-readable and structured so assistants can operate with high leverage.

### 2. Thoughtful human tools for cognition and focus

But the app is not just a passive persistence viewer. The human needs tools that the AI cannot provide:

- **Today** — the assistant-curated, human-adjustable day list. The assistant decides which tasks are on today (and optionally when) and writes a short briefing, but the human works the list in their own order.
- **Calendar Grid** — temporal visualization that gives a sense of density and rhythm. The AI schedules, but the human needs to see the shape of their week.
- **Daily Review** — reflective writing about mood, energy, wins, and blockers. The AI can analyze patterns, but the human does the reflecting.

The key insight: **the AI handles logistics, the human gets tools for cognition.** These are complementary, not competing. A feature is valuable if it helps either audience — the AI operating the system OR the human thinking within it.

---

### 9. AI Errors Are Intent Errors, Not Data Errors
AI doesn't make typos. AI makes **intent errors**: misinterpreting what you meant, creating the wrong task, wrong granularity, wrong attribution.

Design for this:
- **Correction must be as cheap as creation.** If creating a task costs 0 effort, correcting an error must cost nearly 0 effort. Inline editing in the task detail panel — tap the title, fix it, done.
- **Show the mapping.** For every AI-created task, show raw input alongside AI's interpretation. Mismatches become instantly visible.
- **Conversational review.** High confidence → create directly. Lower confidence → discuss with the user in conversation before creating. The Inbox UI/review workflow has been removed; the internal `inbox` seeded default list remains only for bootstrap/default routing.
- **Transparent reasoning.** Every AI decision has a viewable reason — never a black box. Users who see the reasoning learn to trust. Users who don't understand the logic lose trust, regardless of accuracy.

### 10. AI Has Global Context — Use It
When you engage the assistant, it can reason over everything at once — the qualitative edge over
human planning. It surfaces these in the conversation you're already having; the app doesn't push
them at you on its own:
- **Cross-project deadline awareness** — "5 things due Friday across 3 projects; I've moved 2 to today"
- **Gap filling** — "90 free minutes tomorrow; want me to schedule something from your backlog?"
- **Deferral pattern detection** — "You've pushed this 6 times; archive it or address the blocker?"
- **Deadline risk awareness** — "6 hours of work remaining, 3 hours of free time; this is at risk"
- **Context continuity** — "Last time you worked on the grant was 2 weeks ago; you left off at the budget section"

No human does this analysis. No existing tool does either. This is the genuine competitive advantage.

### 11. Asymmetric Configuration — AI Gets More Knobs Than Humans

Traditional apps expose the same settings to everyone. An AI-native app has **two configuration surfaces with different scopes:**

- **AI configuration** (via MCP): dashboard layout, task priorities, task sort order, memory sections, which tasks are on today. These are things AI manages better than humans.
- **Human settings** (via UI): working hours, notification preferences, privacy levels, theme, export. These are things that require human judgment or personal preference.

The human settings page is an **executive override panel**, not a full control panel. It deliberately omits things that AI handles — not to hide them (they're visible in the changelog and memory view), but because surfacing them as toggles adds cognitive load without adding value.

The key safeguards:
- **Changelog** = "I can see everything AI changed"
- **Memory view** = "I can see what AI thinks about me"
- **Manual edit on any field** = "I can always correct AI"

This means: the more the AI earns trust, the simpler the human interface becomes. That's the opposite of traditional software, where power means more settings.

---

## What We Explicitly Reject

1. **Complex creation forms.** If creating a task requires more than typing a sentence, the form is too complex.
2. **Manual drag-to-reorder as primary organization.** AI should order; humans should override rarely.
3. **Static priority labels.** "High/Medium/Low" set once and never updated is theater, not planning.
4. **Maximalist feature breadth.** Cramming in every possible control is both a strength and a weakness elsewhere; it is not our goal. We make deliberate tradeoffs toward AI-native depth over human-operated breadth.
5. **The second brain trap.** This is not trying to become a general-purpose knowledge base or freeform knowledge graph. Notes and reviews exist in service of planning and execution, not as an infinite archive project.
6. **Collaboration features in v1.** Single-user. One person, one AI assistant, one system. Complexity comes later.
7. **The black box.** Users MUST be able to see why AI made a decision. Opaque AI erodes trust even when it's accurate. Every recommendation has a viewable reason.
8. **UI complexity as a proxy for power.** More features ≠ better product. Every element we add is complexity the user must process. In a tool used daily, cognitive overhead compounds. Ruthlessly cut anything that doesn't directly serve "what should I do next?"
9. **Turning Lorvex into a full calendar suite.** We support lightweight calendar-event capture/editing to protect schedule realism, but we do not aim to compete with full-featured calendar products. The core remains tasks, plans, and execution decisions.
10. **Task hierarchy (nested parent/child tasks).** No `parent_id` task tree. A parent task whose subtasks carry independent dates spanning many days has no non-awkward timeline or Today placement, and it duplicates primitives Lorvex already has. Decomposition collapses into two tiers instead: in-task steps with no independent scheduling are a **checklist** (`task_checklist_items`); a multi-day effort whose members each own a date is a **list-as-project** — a `list` of independent dated tasks ordered by `task_dependencies`, where only the dated member tasks land on the timeline (one clear position each) and the list container never does. This also fits the AI-first model: the assistant authors *a list + dated tasks + dependencies*, which is more natural to generate and cleaner to display than a nested tree.
11. **Actual time-on-task tracking.** We store a duration *estimate* — which drives scheduling — but deliberately do not record how long a task actually took. Reliable time-on-task is impractical under real parallel work, the capture UI is intrusive for little payoff, and an earlier implementation was removed. Estimates are AI-proposed and human-adjustable; there is no estimate-vs-actual feedback loop. This also rules out a running session timer or a Live Activity for the task in progress — a live countdown is tracked time-on-task by another name, and glanceable task/habit visibility (including on the Lock Screen) is already a widget's job. A standalone opt-in Pomodoro could serve the niche who want one later, without turning the app into a time tracker.

---

## Habits vs recurring tasks

Habits and recurring tasks are deliberately **separate concepts with different human meaning**, not redundant duplicates. A **recurring task** is an obligation or piece of work that repeats — a weekly report, a rent payment, a maintenance chore. It carries a full RRULE recurrence (including `INTERVAL`, "every N periods"), a duration, and lands on the timeline like any task. A **habit** is a good behavior you want to *build* — meditate daily, gym Mon/Wed/Fri, read four times a week. It is measured by consistency and streaks, is never scheduled onto the timeline, and is completed as a counter rather than as a work item. Habit cadence is therefore about **regularity** (daily / specific weekdays / N-per-week / a monthly day), not "every N periods" — the sparse-interval cadence belongs to recurring tasks. The AI never puts a habit on the day's schedule.

---

## The Potential

If this works as designed:
- Your todo list is never stale (AI maintains it)
- You never miss a deadline because something slipped through (AI tracks dependencies and deadlines)
- You never open your app not knowing what to do next (AI has already curated today)
- Your weekly review is a 15-minute approval session, not a 90-minute clerical ordeal
- Your day is time-blocked and scheduled by AI before you start work
- AI assistant in an MCP client is a primary automation surface for managing your task system, alongside the app's own execution and review surfaces

This is a genuinely new product category. Not "AI-assisted todo app." **An AI-native planning system with a strong automation surface and a strong human workspace.**
