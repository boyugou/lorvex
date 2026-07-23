# Product Pitch (English)
---

## The Problem Everyone Has

You've tried the popular task managers and note apps. Every time it's the same story: you set it up, you maintain it for two weeks, life gets busy, and the system starts rotting. Your task list becomes a graveyard of stale items that makes you feel worse, not better, every time you open it.

The root cause: **the system requires more energy to maintain than it gives back.** GTD's weekly review is 90 minutes. Time blocking is daily re-planning. The irony: the moment you need the system most (when life is chaotic) is exactly when you stop maintaining it.

---

## What We're Building

**An AI-native planning system where your AI assistant is your chief of staff.**

**How it works today:** this is conversation-triggered — you talk to an MCP-capable assistant (like Claude), and it runs Lorvex's MCP tools to manage your tasks, calendar, and schedule. A fully autonomous background mode is future scope.

You don't manage tasks manually. You mention things to your AI assistant in conversation — "I need to finish the paper intro by Friday," "remind me to call the hotel" — and your AI assistant creates, organizes, prioritizes, and schedules everything. Then you use Lorvex however you want: morning briefing, today's focus, calendar, weekly review, or quick inline edits.

Open the app and you see a clean briefing:

```
Friday, February 28

Focus
───────────────────────────────────
○  Write intro section           45m
○  Confirm Barcelona hotel       10m
○  Review PR #287                30m

"The intro is your top priority — it unblocks Friday's deadline.
 After that, knock out the hotel booking (10 min, time-sensitive)."
```

That's it. 3-5 things. AI already did the expensive sorting. You review, you approve, you work.

**Total time managing the system: near zero.**
Time in the app is not the metric. The app should be excellent for a quick glance and equally good as an all-day planning and execution tool.

---

## Why This Doesn't Exist Yet

There are roughly 5 categories of productivity tools:

| Category | What's Wrong |
|---|---|
| Human-operated task managers | YOU do all the work |
| AI auto-schedulers | Black box, no trust, still requires manual metadata entry |
| Semi-auto schedulers | Human still picks what goes on today; algorithm just packs them sequentially |
| Guided planning rituals | Beautiful but 15 min/day of manual work |
| AI meeting tools | Capture work, but don't plan it |

**We're Category 6: an AI-native planning system.** No existing product does the full loop — capture, organize, prioritize, schedule, review — automatically. Every tool automates one step and leaves the rest to you.

We'll return to the semi-automatic scheduler category with a direct side-by-side once the operating model is clear.

---

## Six Core Differentiators

### 1. Radically Simple UI — Because It Can Be

Traditional apps need priority dropdowns, sort controls, filter bars, drag-to-reorder... because the HUMAN is making decisions. In Lorvex, AI-managed priority remains canonical; human override and power-user controls are shipped correction affordances in capture/detail/browse surfaces, not the default task row.

So a task row is just: `○  Task title    45m`. That's it. No metadata noise. The daily view is a clean briefing over saved focus state, not a spreadsheet-style management grid.

But also — click a list in the sidebar, and you can browse ALL tasks with full metadata (due date, priority, duration). **AI-curated views are minimal. Browsing views are complete.** Two modes, each serving its purpose.

### 2. Transparent AI — The Opposite of a Black Box

The #1 complaint about opaque schedulers: "I don't know WHY it rescheduled my tasks."

Every decision our AI makes has a visible reason:

> "Raised priority on 'Book flights' — group discount expires in 5 days"
> "Scheduled for morning — your writing sessions are 2x faster before noon"
> "Deferred 4 times. Either archive it or address the blocker?"

Trust is earned through transparency. Users who see the reasoning learn to trust. Users who don't see it lose trust, regardless of accuracy.

### 3. Conversation Is the Trust Layer

> *Note: The Inbox UI/review surface was removed. The conversation with the AI assistant is now the review layer. The schema-seeded `inbox` default list remains only as a bootstrap/default-routing artifact.*

AI aggressively creates tasks. But you're always in control. The conversation with your AI assistant is where review happens: the AI proposes tasks, explains its reasoning, and you confirm or correct in real-time. High-confidence tasks (you explicitly asked) are created directly. Uncertain ones are discussed first.

**Correction is as cheap as creation.** The AI shows what it understood alongside what you said. Mismatches are instantly visible and fixable in the conversation or via inline editing in the app.

### 4. AI Global Context No Human Can Match

When you plan your day, you work from memory and gut feeling. When AI assistant plans your day, it works with:
- Your complete task database with all deadlines and dependencies
- Your calendar (what time is already committed)
- Deferral patterns (what you keep avoiding)
- Your completion history (what you've finished and when)
- The dependency graph (what blocks what)

Things only AI assistant can do:
- *"Monday/Tuesday are light, Wednesday has 5 deadlines across 3 projects. I've moved 2 to Monday."*
- *"Your paper deadline is Friday. 6 hours of work left, 3 hours of free time. This is at risk."*
- *"You've deferred 'clean photo library' 6 times. Archive it?"*

No human does this analysis. No existing tool does it either.

### 5. The Database Is a Record of Your Life — And AI assistant Knows It

Most AI assistants reset between sessions. Every conversation starts from scratch. You re-explain your context, your projects, your situation.

Lorvex's SQLite database is a permanent, growing record. Every completed task is an accomplishment. Every deferred item reveals an avoidance pattern. Every someday item is an aspiration on record. Over months, the database accumulates:

- What you've done (completed work, closed projects)
- What you're doing now (active tasks, this week's focus)
- What you keep avoiding (deferred items, stalled lists)
- Your patterns (deferral tendencies, morning energy, load tolerance)

When AI assistant reads this database, it doesn't see a task list. It sees a longitudinal picture of how you operate. This compounds:

> "You've taken on 8 new projects this month — the most in 6 months. Historically, your completion rate drops at this load level."

No AI assistant that resets every session can say that. No other productivity tool tracks it. This is what genuine personalization looks like: not a preference setting, but observed data about a real person over time.

The scope naturally expands beyond tasks. Reading queues, learning goals, journal entries, project notes — all become part of the life record AI assistant can access and reason over.

### 6. Weekly Review in 15 Minutes, Not 90

AI assistant pre-populates everything:
- 14 tasks completed this week (feel good)
- 2 projects stalled (need decisions)
- 1 task deferred 5 times (archive or break down?)
- Someday items that became relevant

You make decisions in conversation. AI assistant executes via MCP. Three sentences from you → entire review complete.

---

## The Contrarian Bet: AI-Native Without Downgrading the App

Most software companies force a false choice:

- either the app is the only "real" interface, so AI can only be a thin helper
- or AI becomes the whole story, and the app collapses into a passive dashboard

Lorvex is built around a better split:

- **AI-native operations:** capture, organization, prioritization, schedule generation, review prep, pattern detection
- **Human-native tools:** today's focus, full task browsing, quick edits, calendar views, daily/weekly review

Here is what a normal day looks like for a power user:

```
8:45 AM — open Lorvex or ask AI assistant: "What's on today?"
           Same plan either way: 3 focused items, schedule shape, and why they matter.

During the day — work from Lorvex.
           Today's Focus keeps you moving. The calendar keeps the day legible.

During the day — "I finished the intro. Hotel confirmed."
           AI assistant marks them complete, adjusts priorities, updates the plan.

Evening — "I should really read that Feynman book."
           AI assistant creates a someday item: "Read Surely You're Joking" [Reading]

Friday — AI assistant: "Weekly review ready. 11 tasks completed.
          3 projects stalled. 2 items deferred 4+ times."
```

This is the product working as designed. **AI removes the maintenance work, while the app remains a genuinely good place to think and execute.**

The measure of success is not session length or DAU. It's whether your important work happened, nothing fell through the cracks, and both interfaces feel strong. Lorvex should never require tedious maintenance — but it should absolutely reward being opened when a human wants to use it.

Conversation is a primary automation surface. The app is a primary human workspace. Most companies only optimize one of those layers. We intend to make both excellent.

---

## vs. Semi-Automatic Schedulers — Our Closest Spiritual Ancestor

Now that the model is explicit, here's the direct boundary with the closest existing category.

The semi-automatic scheduler gets the most important thing right: **duration is real, not optional.** We adopt this fully. But:

| | Semi-Auto Scheduler | This App |
|---|---|---|
| Picks today's tasks | You pick manually | AI picks from your full backlog |
| Scheduling logic | Sequential packing ("first fit") | Contextual reasoning (energy, dependencies, deadlines) |
| Duration estimates | You set manually | AI estimates from task context |
| When plan breaks | Manual drag | "I'm sick, move everything to tomorrow" |
| Backlog management | Weak (flat lists) | Full multi-list + AI-maintained + weekly review |
| Cross-project awareness | None | Knows all deadlines across all projects |

A semi-automatic scheduler auto-schedules what you've already chosen. We auto-schedule what you should be doing.

---

## The Architecture Is Clean

The app itself contains **zero AI**. No Anthropic SDK. No LLM. It's:
- A beautiful planning app and workspace across multiple runtimes
- Plus an MCP server that exposes the database to AI assistants on capable desktop runtimes

All intelligence comes from external MCP-capable assistant clients.

```
Assistant Client (Claude Desktop / Claude Code / Codex) → MCP Server → SQLite ← Tauri App (what you see)
```

This means:
- **Works without an assistant** — a strong planner in its own right
- **With an assistant → 10x better** — but not broken without it
- **Direct-distribution friendly** — no bundled AI dependency in the Tauri app
- **Trust by design** — user-owned data + source-backed architecture with a planned public core

Mobile runtimes should be strong standalone peers for capture, planning, and execution — with MCP remaining the best operator experience on capable desktop runtimes, not the only meaningful way to use Lorvex.

---

## The Emotional Design

Most productivity apps create anxiety. This app creates **calm confidence:**

- Morning: 3-5 focus items → "I've got this"
- Overdue: collapsed by default, subtle indicator — no screaming red badges
- Empty state: "All clear for today." — not "No tasks! Add some!"
- Completion: smooth animation, quiet acknowledgment — no confetti
- Menu bar: a glance shows your next task

The feeling over weeks: nothing falls through the cracks. The system has your back.

---

## What Success Looks Like

1. You never maintain a todo system again
2. You always know what to do next
3. Nothing falls through the cracks
4. Your days are planned before you start work
5. Weekly review takes 15 minutes
6. Conversation is a primary automation interface, and the app is a primary execution interface
7. Your assistant knows who you are — and gets more useful the longer you use it
8. You never have to maintain the system manually just to keep it trustworthy

This is not incremental improvement. This is a different product category.
