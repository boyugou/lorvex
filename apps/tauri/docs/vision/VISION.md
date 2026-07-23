# Product Vision
---

## One-Sentence Vision

An AI-native planning system where your AI assistant helps run the planning layer while the app remains a premium place to see, shape, and execute your day.

The best current experience is desktop + MCP. But the long-term product is not "one primary runtime plus secondary clients." It is one product across peer runtimes, with the app itself staying strong wherever MCP is unavailable.

## Product Principle: Assistant Capability Is Core UX

Lorvex's MCP action space is part of the product UI, not internal plumbing.

- If assistants cannot reliably express intent through tools, product UX is broken even when app screens look polished.
- Tool design should prioritize semantic actions and robust argument handling so assistants can execute user intent in one or two calls.
- Improving assistant ergonomics is continuous product work, not a one-time infrastructure task.

---

## Why This Is Different From Everything Else

There are roughly four categories of productivity tools today. This app doesn't fit any of them. It's a fifth category.

### Category 1: Human-Operated Task Managers

The human does everything: capture, organize, prioritize, schedule, review. The app is a database with views. Powerful, but breaks down because **the system takes more energy to maintain than it returns.**

### Category 2: AI Auto-Schedulers

You add tasks with metadata (priority, deadline, duration). The AI places them onto your calendar. Genuinely useful, but with recurring weaknesses:

- **The black box problem.** Users don't know WHY the AI made a decision. No transparency, no reasoning, no audit trail. A top complaint, because users feel a loss of control.
- **Metadata burden.** You still have to manually enter priority, deadline, duration, and chunking rules for every task. The AI only automates the scheduling step — you still do all the cognitive work of defining the task.
- **No context.** These tools schedule mechanically. They don't know that "prepare board deck" requires deep focus and relates to the meeting on Thursday. They treat all 60-minute tasks the same.
- **No conversation.** The interface is forms and drag-and-drop, not natural language. There's no way to say "I'm tired, move everything to tomorrow."

### Category 3: Guided Planning Rituals

You do a structured morning planning session: pull tasks from various tools, estimate durations, build your day. Beautifully designed, genuinely behavior-changing. But:

- **No AI.** Everything is manual. The ritual takes 10-15 minutes daily because you're doing the work.
- **Doesn't scale.** When you have 50+ tasks across 5 projects, manually choosing what goes on today is a real cognitive load.

### Category 4: Semi-Automatic Schedulers

You add tasks with durations, then press "Auto Schedule" to pack them sequentially into time blocks starting from now. The best existing model for "time as a first-class citizen." But:

- **Human still decides what goes on today.** Auto-schedule only sequences the tasks you've already chosen — it doesn't pick them for you from a backlog of 50.
- **Greedy algorithm, not intelligence.** Tasks are packed sequentially (first-fit). No awareness of energy levels, dependencies, or context. A 2-hour creative writing task gets packed right after 3 hours of meetings.
- **No learning.** You estimated 30 minutes, it took 90. The scheduler doesn't know and doesn't adjust.
- **No capture or organization.** You still manually create, categorize, and prioritize every task. The "auto" part is only the final scheduling step.
- **Weak project/backlog management.** Works great for a day's worth of tasks. Falls apart when you have 5 projects with 80 tasks across them.

The core insight of this category — **duration is required, not optional; a task without a time estimate is a wish** — is genuinely important. We adopt it fully.

### Category 5: AI Meeting Assistants

Focused on extracting value from meetings (notes, action items). Useful but narrow — they capture work, they don't plan it.

### Category 6: This App — AI-Operated Planning System

| Dimension | Traditional Task Manager | AI Auto-Scheduler | Semi-Auto Scheduler | Guided Ritual | **This App** |
|---|---|---|---|---|---|
| Who creates tasks? | Human | Human | Human | Human | **AI from conversations** |
| Who decides today's focus? | Human | Algorithm | Human | Human (guided) | **AI proposes, human approves** |
| Who schedules? | Human | Algorithm (black box) | Algorithm (greedy) | Human (drag to calendar) | **AI proposes with reasoning** |
| Who maintains the system? | Human (weekly review) | Human (metadata entry) | Human (all manual) | Human (daily ritual) | **AI (human reviews in 15 min/week)** |
| Duration matters? | Optional field | Required | **Core concept** | Core concept | **Core concept (AI-estimated)** |
| Transparency? | Full (human controls all) | None (black box) | Full (simple algorithm) | Full (human controls all) | **Full: AI reasoning visible** |
| Context awareness? | None | Metadata only | None | None | **Full: AI has personal context** |
| Scheduling intelligence? | None | Mechanical | Sequential packing | None (manual) | **Contextual: energy, dependencies, deadlines** |
| Primary interface? | App GUI | App GUI | App GUI | App GUI | **AI automation via MCP + full app workspace** |

The critical difference: **AI-heavy operations happen through conversation with your assistant, while the app remains a first-class place to view plans, execute work, capture thoughts, and stay oriented all day.** The MCP client is a primary automation surface. The app is not demoted to a passive dashboard.

### vs. The Semi-Automatic Scheduler Category Specifically

The semi-automatic scheduler is the closest existing category to our vision in spirit — it takes time seriously, it auto-schedules, and the best of it is beautifully native. The difference is the depth of intelligence:

| | Semi-Auto Scheduler | This App |
|---|---|---|
| Picks today's tasks | You pick manually | AI picks from your full backlog |
| Scheduling logic | Sequential packing ("first fit from start time") | Contextual reasoning (energy, dependencies, deadlines, calendar gaps) |
| Duration estimates | You set manually | AI estimates from task context |
| When plan breaks | Manual reschedule / drag | Tell AI assistant "I'm sick, move everything to tomorrow" |
| Backlog management | Weak (one flat list per category) | Full (multi-list, projects, AI-maintained, weekly review) |
| Cross-project awareness | None | "5 deadlines across 3 projects on Friday — redistributing" |

---

## The Core Experience Loop

```
You live your life. Things come up.
        ↓
You mention them to AI assistant (in an MCP client, quick capture, or just conversation).
"I need to finish the paper intro by Friday."
"The hotel in Barcelona — need to confirm booking."
"Remind me to call Marcus next week."
        ↓
AI assistant creates tasks via MCP. Organizes. Sets priority. Estimates duration.
Tasks go directly into the appropriate list.
> *Note: The Inbox UI/review surface was removed; the conversation itself is the review layer. The schema-seeded `inbox` default list remains only as a bootstrap/default-routing artifact.*
        ↓
Morning: you open the app (or ask your assistant) and start from a clean, curated briefing:
  "3 things to focus on today."
  1. Write intro section — 45m
  2. Confirm Barcelona hotel — 10m
  3. Review pull request — 30m
You approve, adjust if needed, and start working.
        ↓
Throughout the day: work from the app if you want to.
Work from Today's Focus, check off tasks, defer, and inspect your week.
Menu bar and quick capture stay available for low-friction moments.
        ↓
When you invoke the AI assistant, it maintains the system through Lorvex's MCP tools.
It recomputes priorities, flags risks, and prepares your weekly review inside explicit assistant sessions.
You never have to think about "maintaining" your todo system.
```

Total time managing your productivity system: **near zero.**
The system is maintained by user-invoked AI assistant work. How much time you spend in the app is up to you: it should be excellent for a 30-second glance and equally usable as an all-day workspace.

**Current alpha operating model:** AI maintenance is session-driven (assistant invoked via MCP), not an always-on autonomous daemon.

---

## The Simplicity Thesis

This is the most important design insight, and I arrived at it late:

> **In a traditional todo app, the UI is complex because the human is making decisions. In an AI-native app, the UI can be radically simple because the AI has already made the decisions.**

Why does a full-featured traditional task manager have priority dropdowns, tag editors, date pickers, drag-to-reorder, sort options, filter bars, multiple view modes, and an Eisenhower Matrix view? Because the human needs all that information and those controls to manage their task system.

Why does this app NOT need most of that? Because:
- AI set the priority -> default AI-curated views do not need a priority dropdown in every row
- AI assigned the list -> default AI-curated views do not need a list picker in every row
- AI ordered the tasks → you don't need sort controls
- AI chose today's focus → you don't need to scan a long list
- AI estimated duration → you don't need a form field

Current-product exception: AI-managed priority remains canonical, while human override and power-user controls are shipped correction affordances. Quick Capture, task detail, full-list browsing, filters, and move-to-list flows can expose priority/list controls because they are correction and inspection surfaces, not the default execution surface.

**The AI-native UI shifts effort away from clerical work and toward execution:**
1. A curated briefing (what to do today)
2. Minimal actions per task (complete, defer, done)
3. A way to browse everything when curious (search, full list)
4. Fast human tools when thinking matters more than automation (today's focus, calendar views)
> *Note: The Inbox UI/review surface was removed; the conversation with the AI assistant is now the review layer for AI proposals. The schema-seeded `inbox` default list remains only as a bootstrap/default-routing artifact.*

No unnecessary clerical surfaces. No form-heavy workflow as the default. No requirement to manually maintain the system just to keep it usable. But the app is still a real tool: people should be able to browse, edit, think, and execute comfortably inside it for as long as they want.

---

## The Todo ↔ Calendar Relationship

Across the productivity-tool categories, here's the clearest model:

### Three Distinct Data Types

1. **Tasks** — commitments you need to fulfill. Flexible timing. AI-managed.
2. **Calendar Events** — time-bound appointments. Fixed constraints. Stored as lightweight event records in Lorvex when needed (human or AI can add/edit/delete).
3. **The Schedule** — AI's synthesis of #1 and #2. Which tasks to do today, mapped into time slots around your calendar events.

### Why We Still Avoid Becoming a Calendar App
We support a minimal event layer because schedule quality depends on accurate fixed commitments. But Lorvex is not trying to replace dedicated calendar software with full account sync, invitations, attendee workflows, and complex calendar operations. Our domain remains planning/execution decisions around tasks + constraints.

### The Schedule as AI's Primary Output
The schedule is what the daily briefing is built from. AI reads:
- Your calendar (what time is already committed)
- Your task database (what needs doing, with priorities and deadlines)
- Your energy patterns (when you do best work)
- Your completion history (what you've finished and when)

AI produces: a proposed plan for the day — which tasks, in what order, fitted into available time slots.

The app displays this plan. The human approves or adjusts. The plan becomes their working reference for the day.

### Implication: The Primary View Is "Today's Plan," Not "Today's Tasks"

"Today's tasks" is the pool of tasks planned for today or due today (`planned_date <= today OR due_date <= today`). It answers: "what's on my plate?"
"Today's Focus" is the AI-curated subset with ordering and briefing. It answers: "what should I work on right now?"

Today's Plan is the more valuable view. It's the AI-native view. Today's Tasks is the fallback/traditional view that still exists for those who prefer it.

(For MVP: start with Today's Tasks as a simple list. Add the time-blocked plan view as a fast-follow. But the architecture should assume the plan is the eventual default.)

---

## AI Error Handling — The Intent Problem

The user's critical insight: **AI doesn't make typos. AI makes intent errors.**

In a human-operated app, errors are: forgot to capture, wrong priority, stale list.
In an AI-native app, errors are:
- **Misinterpretation:** "Deal with the hotel" → AI creates "Cancel hotel" when you meant "Confirm hotel"
- **Wrong granularity:** You mention a project → AI creates one task when it should be five
- **Over-extraction:** You muse "it would be nice to learn Spanish" → AI creates a task
- **Wrong attribution:** "We should do X" → AI assigns it to you when it was someone else's job
- **Missing context:** AI schedules deep work after 6 hours of meetings

### Design Implications

> *Note: The Inbox UI/review surface was removed. The conversation with the AI assistant is now the review layer. These design principles still apply through conversation rather than a separate Inbox view; the schema-seeded `inbox` default list remains only as a bootstrap/default-routing artifact.*

**1. Correction must be as cheap as creation.**
If creating a task costs 0 effort (just mention it in conversation), but correcting an AI error costs 5 clicks and a form, the system is net negative. Inline editing in task detail and real-time correction in conversation make this possible.

**2. Show AI's interpretation alongside the original input.**
For every AI-created task, the raw input is stored and visible. The human can see the mapping from what they said to what AI understood. Mismatches are visible in conversation and in the task detail view.

**3. Conversational review prevents the worst errors.**
- High confidence (explicit request) → create directly in list
- Medium confidence (extracted from context) → confirm with user in conversation
- Low confidence (vague implication) → AI asks for clarification instead of creating

**4. Transparent reasoning builds trust over time.**
Every AI decision has a viewable reason — never a black box:
- "Marked as high priority because it blocks 3 tasks with a Friday deadline"
- "Scheduled for morning because your writing sessions are 2x faster before noon"
- "Created with lower confidence because I wasn't sure if 'we should look into this' was an action item for you"

Users who see the reasoning learn to trust the AI. Users who don't understand the AI's logic lose trust, regardless of accuracy.

---

## The AI Global Context Advantage

This is the core capability that makes AI scheduling qualitatively superior to human scheduling:

When you plan your day manually, you work with:
- What you remember (lossy, biased toward recent/emotional)
- What's visible in your calendar (doesn't include task metadata)
- Your gut sense of what's important (unreliable under stress)

When AI plans your day, it works with:
- **Complete task database** with all metadata, history, and relationships
- **Calendar events** (all meetings, appointments)
- **Deadline landscape** — cross-project view of what's due when
- **Deferral patterns** — what you keep avoiding (signal of either low importance or hidden blockers)
- **Completion history** — what you've finished and when
- **Dependency graph** — what needs to happen before what
- **Your stated context** — what you told AI assistant you're focused on this week

**Concrete things only AI with global context can do:**

1. **Cross-project load balancing:** "Monday and Tuesday are light. Wednesday has 5 deadlines across 3 projects. I've moved 2 of Wednesday's tasks to Monday."

2. **Proactive gap filling:** "You have 90 free minutes tomorrow afternoon. From your backlog: read the paper Sarah recommended (30m), research Japan flights (45m). Want me to schedule one?"

3. **Deferral pattern detection:** "You've deferred 'clean photo library' 6 times over 3 months. Either it's not important (archive it?) or there's a hidden blocker (what's stopping you?)."

4. **Deadline risk awareness:** "Your paper deadline is Friday. The intro isn't written and the experiments section needs revision. At your historical pace, this is ~6 hours of work. You have 3 free hours remaining this week. This is at risk."

5. **Context continuity:** "Last time you worked on the grant proposal was 2 weeks ago. You left off at the budget section. Related document is in your Drive folder."

No human does this analysis manually every morning. No existing tool does it either. This is the genuine innovation.

---

## The Life Trajectory — AI That Actually Knows You

Here is something none of the existing tools have thought about: **the database is a permanent record of your life.**

Every task you create is a commitment. Every completed task is an accomplishment. Every deferred item reveals avoidance. Every someday list item shows an aspiration. Every list you shape over time is a chapter.

Over time, the database accumulates:
- **What you've done** — completed tasks, finished work, resolved blockers
- **What you're doing now** — open tasks, active lists, today's focus
- **What you plan to do** — scheduled tasks, goals, someday items
- **What you keep avoiding** — deferred items, stalled lists
- **Your patterns** — morning energy, deferral tendencies, completion cadence

When AI assistant reads this database at the start of a session, it doesn't just see a task list. It sees **a longitudinal record of who you are and how you operate.** This is profoundly different from any other AI assistant interaction.

### What This Enables

**Better assistance in every conversation.** AI assistant that knows your history doesn't need you to re-explain your context. "I'm working on the grant" is enough — AI assistant already knows the grant is due March 15, that you last worked on it 5 days ago, and that you're blocked on the budget section.

**Genuine personalization.** Not "personalization" as a buzzword, but: AI assistant has observed hundreds of your tasks and can say with data what you tend to defer, what you tend to avoid, and what you tend to prioritize. These observations compound over time.

**Proactive pattern surfacing.** "You've taken on 8 new projects this month, the most in 6 months. Your completion rate drops historically when you're at this load level." No AI assistant that resets every session can do this.

### The Scope Expands Beyond Tasks

Once you realize the database is a life record, the scope of what belongs there expands naturally. Users might store:
- Goals and long-horizon targets ("get to B2 Spanish by December")
- Reading and learning queues (books, courses, articles)
- Media watchlists
- Journal entries (what happened today, how it felt)
- Project retrospectives

The current schema handles many of these as task variants (someday items, notes, tags). As the product matures, the question is not whether to support this broader scope — it's how to model it cleanly.

**Design principle:** A task without a deadline is a wish. A wish worth keeping is still worth storing. The AI can help determine which wishes to act on and when.

---

## The Dual-Surface Philosophy

There is a fundamental tension in AI-native software: **where should the work actually happen?** Most products pick one of two extremes:

- the app tries to remain the only "real" interface, so AI becomes a gimmick layered on top
- or the app is demoted into a thin database viewer while all meaningful work moves into chat

Lorvex is deliberately built to be excellent at both layers:

- **AI-native operations layer:** conversation + MCP are where high-cost maintenance, planning, review prep, and restructuring happen
- **Human workspace layer:** the app is where you can execute, browse, inspect, capture, reflect, and stay oriented all day if you want to

The goal is not "make the app unnecessary." The goal is **remove maintenance overhead while keeping the app genuinely good enough to live in.**

Here is the interaction model we actually want:

```
Normal day:

8:45 AM — you open Lorvex or ask your assistant: "What's on today?"
           You get the same plan either way: today's focus, schedule shape, and why it matters.

10:00 AM — you work from the app.
           Today's Focus and the calendar grid are there because
           execution and thinking still need good human tools.

During the day — you tell AI assistant things:
           "I finished the intro. Hotel confirmed. That takes 2 things off."
           AI assistant marks them complete, updates priorities and the plan.

During the day — you also use the app directly:
           browse lists, update a task, check the next block, pin a note, jot a quick idea,
           or review what changed.

Evening — you mention offhand: "I should really read that Feynman book"
           AI assistant creates a someday item: "Read Surely You're Joking" [Reading]

Friday — AI assistant messages you: "Weekly review is ready. 11 tasks completed.
          3 projects stalled. 2 things deferred 4+ times worth deciding on."
```

This is the product working as designed: **AI does the maintenance work, and the app remains a strong place to do human work.**

### Why Most Companies Can't Build This

A company optimizing for engagement often ships maintenance-heavy UX because manual interaction is what their system is built around. A company obsessed with "AI magic" often swings too far the other direction and turns its app into a thin monitor for chatbot actions.

Lorvex has no reason to make either tradeoff. The measure of success is not DAU or session length — it's **whether your important work happened, nothing fell through the cracks, and both the AI workflow and the app workflow feel excellent.**

### Design Implications

1. **The app is a first-class workspace, not just a viewer.** Creating, updating, completing, reviewing, capturing, and reflecting should all feel good in the app. What disappears is the clerical burden of manually maintaining the whole system.

2. **The MCP interface is also a first-class product.** The tools AI assistant uses to interact with the database are as important as the app UI. They must be excellent.

3. **Make movement between the two surfaces easy.** Lorvex should make it easy to trigger AI help from inside the app and easy to return to the app after an AI operation. The user should never feel forced to choose one interface forever.

4. **Data portability is a feature, not a liability.** Since users interact primarily through AI assistant, the database should be fully inspectable and exportable. Users should never feel locked in. Trust is the product.

### AI/Tool Co-Evolution Loop

Lorvex should explicitly treat assistant feedback as a product input channel, not incidental support chatter.

The assistants (Claude Desktop, Claude Code, Codex, and future MCP clients) are power operators of the MCP layer. When they repeatedly surface missing tools, tool friction, or bugs, that is direct evidence of product-level friction. The development loop should be:

1. Assistant encounters friction in real workflows
2. Assistant opens or links a concrete GitHub Issue
3. Developer ships tool/schema/UI fix
4. Assistant re-runs the workflow and validates the fix
5. The next iteration starts from a stronger baseline

This creates a compounding effect: better tools improve assistant execution quality, and better assistant execution reveals higher-order opportunities. The system should evolve by closing this loop continuously.

---

## Positioning Summary

| vs. AI auto-schedulers | We're transparent (show reasoning). We capture via conversation (not forms). We do the full loop (capture → organize → schedule), not just schedule. |
|---|---|
| **vs. calendar-defense tools** | We manage tasks, not just defend calendar time. We have a visual dashboard, not just calendar overlays. We capture and organize, not just schedule. |
| **vs. guided planning rituals** | We do the planning work for you. The ritual is valuable but manual; ours keeps the reflective ritual while removing most of the clerical prep. |
| **vs. traditional task managers** | We maintain the system for you. Power features go unused because maintaining them is work. Our AI does the maintaining. |
| **vs. semi-automatic schedulers** | We pick WHICH tasks go on today, not just pack them sequentially. We schedule with reasoning (energy, dependencies, context), not a greedy algorithm. |

---

## The Name Question

Launch display name: Lorvex. Naming criteria used:
- Short (1-2 syllables)
- Evokes clarity, intelligence, or calm — not productivity hustle
- Pronounceable, memorable
- Not already a major product name
- Works as a macOS app icon label

Directions to explore:
- Clarity/vision: Lucid, Lorvex, Lens, Clear
- Guidance/flow: Cadence, Drift, Flow, Tempo
- Human assistant: Aide, Sage
- Abstract: Aria, Nova, Ora

Naming is finalized for launch as Lorvex.

---

## Beyond Todo -- Structured Life Memory

Lorvex is not just a todo app. It is a structured, user-owned, AI-native data store for life.

The task database already accumulates a rich picture of who you are: your commitments, your patterns, your history. But tasks are only one type of structured life data. The natural evolution is to support multiple data modules, each with its own schema, MCP tools, and optional minimal UI:

**Planned Modules:**

| Module | Description | Status |
|---|---|---|
| Tasks | Commitments, actions, projects, backlog | Phase 1 (current) |
| Journal | Daily entries, reflections, mood tracking | Phase 2 |
| Goals | Long-horizon targets with milestones and progress | Phase 2 |
| Knowledge/Learning | Reading queue, notes, course progress, bookmarks | Phase 3 |

Each module follows the same architecture pattern:
- **Schema**: SQLite tables with UUIDs, timestamps, soft deletes
- **MCP tools**: Full CRUD + domain-specific queries (e.g., `get_journal_entries_for_week`)
- **First-class UI**: strong views in the Tauri app for execution, browsing, reflection, and quick capture, alongside conversational AI operations

The UI can be conversational: "AI assistant, show me my journal entries from last week" or "What progress have I made on my Spanish goal?" AI assistant queries the local database and renders the answer.

This reframes the value proposition. Lorvex is not "an AI todo app." It is **your AI's structured planning system. You own it.** Every module is exportable, optional sync remains user-controlled, and the AI gets more useful as Lorvex accumulates richer context about your life — not just tasks, but goals, reflections, and learning.

**Phasing:**
- Phase 1: Tasks (done). Ship, validate, learn.
- Phase 2: Journal + Goals. Natural extensions that deepen AI context.
- Phase 3: Knowledge store. Reading lists, learning progress, reference material.

This philosophy extends to the dashboard itself. AI assistant can control which sections appear on the Today/Dashboard view and in what order, using the `dashboard_layout` preference key. The app reads this layout and dynamically composes the view so the default experience stays relevant without constant manual curation. Layout changes are kept infrequent to preserve spatial stability, so the dashboard feels familiar rather than volatile.

---

## Cross-Platform and Distribution

Tauri 2 gives us macOS, Windows, and Linux from day one. The same codebase produces native-feeling apps on all three desktop platforms. This is a genuine advantage over SwiftUI-only approaches.

**Distribution strategy:**
- **Primary Tauri launch**: direct Windows and Linux desktop distribution through signed artifacts. This covers the early adopter audience who uses MCP clients and is comfortable with direct-install tooling.
- **macOS Tauri build**: developer/reference build for contributors who only have a Mac. The future customer-facing Apple path is the Swift app in `apps/apple`.
- **Follow-on convenience channel**: Homebrew Cask for macOS can follow after the direct-distribution launch is stable; it is not part of the primary launch path.
- **Store channels**: Mac App Store, iOS, and iPadOS belong to the Swift app. Windows Store remains a later secondary channel for the Tauri line.
- **Publish a verifiable public core when the release policy is ready.** The MCP server, schema, migrations, and data-path logic are already source-backed in the private development repository. The public trust claim becomes inspectable only after the public core exists and is linked from the product docs. The Tauri app frontend may become public or source-available depending on business model decisions.

Publishing a public core once it exists is not altruism -- it is a product decision. When your value proposition is "you own your data and AI operates on it locally," the user must be able to verify that claim against real source URLs and documented runtime behavior.

---

## What Success Looks Like

If this product works:

1. **You never maintain a todo system again.** The system maintains itself. You provide intent and context; AI handles the rest.

2. **You always know what to do next.** Open the app → it's already decided. No scanning, no prioritizing, no agonizing.

3. **Nothing falls through the cracks.** AI tracks deadlines, dependencies, and deferral patterns. At-risk items surface automatically.

4. **Your days are planned before you start work.** AI proposes a schedule built from your tasks, calendar, and energy patterns. You review and adjust only when needed.

5. **Weekly review takes 15 minutes.** AI pre-populated everything. You make decisions; AI executes.

6. **Conversation is a primary automation surface, and the app is a primary human surface.** You can ask the assistant to do expensive planning work, and you can stay in the app to execute, browse, capture, and reflect.

7. **AI assistant knows who you are.** Over months, the database accumulates a detailed picture of your work, your patterns, your history. AI assistant doesn't ask you to re-explain your context. It already knows. It gets more useful the longer you use it.

8. **You never spend energy maintaining the system just to keep it useful.** Whether you dip in briefly or keep Lorvex open all day, the product has won if the system stays current and the app remains a pleasure to use.

This is not incremental improvement over existing tools. This is a different product category.
