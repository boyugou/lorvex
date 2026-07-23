# AI assistant's Operating Model
This document defines HOW AI assistant actually uses the MCP tools to manage the task system. The other docs describe the features and data model. This doc describes the **operational playbook** — the patterns AI assistant follows when interacting with the system.

This matters because AI assistant behavior is part of the product experience. On capable desktop runtimes, Lorvex's AI-native promise lives or dies by how well assistants use MCP. At the same time, these operating assumptions should never imply that the standalone app is secondary or fake.

---

## The Mental Model: AI assistant as Chief of Staff

AI assistant operates the task database the way a brilliant chief of staff operates a leader's schedule:

1. **Observe** — Get full situational awareness before acting
2. **Decide** — Apply judgment (deadlines, dependencies, patterns, user context)
3. **Act** — Make changes to the database
4. **Explain** — Every action has a human-readable reason in the changelog

AI assistant NEVER acts blindly. AI assistant should load enough context for the task at hand: use `get_session_context()` when broad context matters, or narrower reads when the task is already focused.

---

## Intelligence write contract (MCP today, on-device models later)

Lorvex has two intelligence directions that share one write contract: the MCP
host — an external assistant operates Lorvex — today, and, as a later
availability-gated enhancement, Apple's on-device Foundation Models / Private
Cloud Compute, where Lorvex itself invokes a model. Both obey the same rules, so
adding the second direction needs no schema or sync change:

1. **The model is never an authorization principal.** Task text, calendar text,
   search results, imported files, and any server/model response are untrusted
   input that may carry prompt injection. Authorization tiers and destructive
   confirmation live in the deterministic commit layer (`LorvexCoreServicing`),
   never in the model or its prompt.
2. **Read → propose → commit are separate layers.** Privacy-bounded reads return
   typed facts; a model returns typed *proposals*; deterministic commands
   authenticate, validate, confirm, and commit. There is no hidden path from a
   read-only assistant to a mutation.
3. **Only confirmed writes reach the schema, through existing fields.** An
   accepted proposal writes ordinary domain fields via the typed core ops. Raw
   transcripts, prompts, reasoning, embeddings, and provider objects are never
   synced; provenance, if any, is local-only. See invariant 8 in
   `SCHEMA_OPTIMALITY.md`.

---

## Common Operational Patterns

### Pattern 1: Task Capture from Conversation

**Trigger:** User mentions something actionable in an MCP client

```
User: "I need to finish the paper intro by Friday. Also, remind me to call
       the Barcelona hotel — the group booking expires soon."

AI assistant's internal reasoning:
- Two tasks identified
- "finish paper intro by Friday" → clear deadline, clear action, high certainty
- "call Barcelona hotel" → clear action, urgency ("expires soon"), high certainty
- Both are explicit requests → create directly in lists

AI assistant's MCP calls:
1. get_overview()  →  understand current lists, workload
2. batch_create_tasks([
     {
       title: "Finish paper intro section",
       list_id: <paper-list-id>,
       due_date: "2026-03-06",
       priority: 2,
       estimated_minutes: 120,
       raw_input: "I need to finish the paper intro by Friday",
       ai_notes: "User explicitly requested. Deadline is firm (Friday).",
     },
     {
       title: "Call Barcelona hotel to confirm group booking",
       list_id: <personal-list-id>,
       due_date: "2026-03-03",
       priority: 1,
       estimated_minutes: 15,
       raw_input: "remind me to call the Barcelona hotel — the group booking expires soon",
       ai_notes: "Time-sensitive: group discount expiration. Set earlier deadline to provide buffer.",
     }
   ])
```

**Key behaviors:**
- AI assistant picks the list based on context ("paper" → Paper list, "Barcelona hotel" → Personal)
- AI assistant infers urgency from language ("expires soon" → earlier deadline with buffer)
- AI assistant estimates duration based on task type (phone call = 15m, writing = 2h)
- AI assistant writes `ai_notes` explaining its reasoning
- AI assistant stores `raw_input` for human verification
- Explicit request → created directly in appropriate list

### Pattern 2: Ambiguous Extraction

**Trigger:** User says something that MIGHT be a task

```
User: "The meeting with Sarah went well. She's going to send the budget
       numbers by Thursday. Oh and we should probably look into that new
       vendor Jason mentioned."

AI assistant's internal reasoning:
- "She's going to send budget numbers" → this is SARAH's task, not the user's.
  Don't create a task. But maybe a follow-up reminder if Sarah doesn't send?
  Medium certainty.
- "we should probably look into that new vendor" → vague commitment.
  "we should probably" is weak intent. Lower certainty. Ask the user before creating.

AI assistant's MCP calls (after confirming with user in conversation):
1. create_task({
     title: "Follow up with Sarah if budget numbers not received",
     due_date: "2026-03-06",  // Friday, one day after Sarah's Thursday promise
     priority: 3,
     estimated_minutes: 10,
     raw_input: "She's going to send the budget numbers by Thursday",
     ai_notes: "Sarah promised to send by Thursday. Created follow-up reminder for Friday in case she doesn't. Not creating a task for Sarah — she's the owner.",
   })

2. create_task({
     title: "Research vendor Jason mentioned",
     priority: 3,
     estimated_minutes: 30,
     raw_input: "we should probably look into that new vendor Jason mentioned",
     ai_notes: "Weak intent signal ('should probably'). User confirmed this is an action item in conversation.",
   })
```

**Key behaviors:**
- AI assistant distinguishes between the user's tasks and someone else's tasks
- AI assistant interprets "she'll send by Thursday" as a follow-up trigger, not a user task
- AI assistant recognizes weak intent ("should probably") and confirms with the user before creating
- AI assistant's ai_notes explain the reasoning for each decision

### Pattern 3: Morning Briefing / Today's Focus

**Trigger:** User asks "What should I focus on today?" or "Plan my day"

```
AI assistant's MCP calls (sequential):
1. get_overview()                    →  full situational awareness, incl. today's
                                        actionable pool (overdue + due-today + planned-today)
2. get_upcoming_tasks(3)             →  next 3 days for context
3. get_current_focus()               →  check if today's focus already exists
                                        (date defaults to today)

AI assistant's reasoning:
- 7 tasks in today's pool, 2 overdue
- "Paper intro" blocks "Submit draft" which is due Friday
- "Board presentation" is in 10 days but needs 3 prep sessions
- User completed 4 tasks yesterday → good momentum
- It's Wednesday → 2 working days until Friday deadline

AI assistant's MCP calls:
5. set_current_focus("2026-02-28", [
     task_id_intro,        // highest leverage — blocks Friday deadline
     task_id_hotel,        // quick win, time-sensitive
     task_id_pr_review,    // blocks a teammate
     task_id_expense,      // quick administrative task
     task_id_sync_prep     // needed for afternoon meeting
   ], briefing: "The intro section is your top priority — it blocks Friday's submission deadline. After that, knock out the hotel booking (10 min, time-sensitive). The rest fits into your afternoon.")

6. set_task_ai_notes(task_id_intro,
     "This is your highest-leverage task today. It blocks 'Submit draft' (due Friday). At your historical pace, writing sections take ~2x your estimate. Budget extra time.")
```

**Key behaviors:**
- AI assistant considers the dependency graph (intro blocks submission)
- AI assistant factors in historical patterns (writing takes 2x estimate)
- AI assistant writes a briefing that explains the WHY, not just the WHAT
- AI assistant picks 5 focus tasks for today (not 3, not 10 — calibrated to a realistic day)
- AI assistant orders by leverage, not just urgency
- When adding tasks to an existing plan mid-day, use `add_to_current_focus()` (append semantics) instead of `set_current_focus()` (replace semantics) to avoid wiping the existing plan
- When a user asks to reopen a completed or cancelled task, use `reopen_task()` — it handles recurring task successor cleanup automatically
- Surface in-progress work first: a task the user already started (status `in_progress`) is the natural thing to resume, so lead the briefing with it before proposing new focus tasks. Maintain the marker in conversation with `start_task()` when the user begins something and `pause_task()` when a started task turns out to be a mis-click; both flow through the same lifecycle funnel as complete/cancel/reopen. There is no `started_at` column — to answer "how long has this been in progress", read the timestamp of the task's most recent `start` transition in `get_ai_changelog()`.

### Pattern 4: Weekly Review

**Trigger:** User says "Let's do a weekly review" (typically Friday)

```
AI assistant's MCP calls:
1. get_weekly_brief()         →  pre-populated review data
2. get_overview()              →  current state

AI assistant presents to the user:
"Here's your weekly review:

Completed this week: 14 tasks
- Biggest wins: Submitted grant application, fixed auth module

Carried over: 3 tasks
- 'Update API docs' has been pushed to next week (2nd time)
- 'Clean photo library' — deferred 5 times total

Stalled projects:
- Spain Trip list: last activity 10 days ago. 4 open tasks.
- Blog list: no tasks completed in 2 weeks.

Suggestions:
1. 'Clean photo library' — archive it or break it into smaller steps?
2. Spain Trip — deadline approaching. Want me to prioritize those tasks?
3. Blog project — still relevant, or move to Someday?"

User: "Archive the photo library task. Prioritize Spain trip tasks for next
       week. Move blog to someday."

AI assistant's MCP calls:
3. cancel_task(photo_id)
4. batch_update_tasks([
     {id: spain_1, priority: 2, due_date: "2026-03-03"},
     {id: spain_2, priority: 2, due_date: "2026-03-04"},
     {id: spain_3, priority: 3, due_date: "2026-03-05"},
     {id: spain_4, priority: 3, due_date: "2026-03-06"}
   ])
5. set_task_someday(blog_1)
6. set_task_someday(blog_2)
```

**Key behaviors:**
- AI assistant uses `get_weekly_brief()` to do the clerical work
- AI assistant presents analysis in conversational, human-readable format
- AI assistant makes suggestions but waits for user decisions
- User gives natural language instructions → AI assistant executes via MCP
- Three user sentences → a handful of MCP calls → entire review complete

### Pattern 5: In-Conversation System Awareness

**Trigger:** User is already chatting with AI assistant about anything; within that conversation the assistant notices the task system needs attention (the app itself never reaches out on its own)

```
User: "Can you help me outline the presentation for the board meeting?"

AI assistant: "Of course. Before we start — I noticed you have 3 overdue tasks
and your 'Paper intro' hasn't been touched in 4 days despite a Friday
deadline. Want me to adjust your schedule, or should we focus on the
presentation first?"

User: "Defer the overdue admin tasks to next week. Let's do the presentation."

AI assistant's MCP calls (before helping with presentation):
1. batch_update_tasks([
     {id: overdue_1, due_date: "2026-03-03"},
     {id: overdue_2, due_date: "2026-03-03"},
     {id: overdue_3, due_date: "2026-03-04"}
   ])
2. set_task_ai_notes(paper_intro_id,
     "User has not worked on this for 4 days. Deadline is Friday. Flagged during 2/28 conversation. User chose to prioritize board presentation instead.")

[Then continues helping with presentation outline]
```

**Key behaviors:**
- AI assistant is context-aware even during unrelated conversations
- Within that conversation, the assistant can surface issues it notices, but doesn't force action (and the app never notifies or reaches out on its own)
- AI assistant respects user's choice of priority even when it disagrees
- AI assistant logs the user's decision in ai_notes for future context

### Pattern 6: Conversational Task Review

> **Note:** The Inbox UI/review surface was removed; the conversation with the AI assistant is now the review layer. This pattern replaces the former "Inbox Processing" pattern. The schema-seeded `inbox` default list remains only as a bootstrap/default-routing artifact.

**Trigger:** User asks for a review of recent or uncertain tasks

```
AI assistant's MCP calls:
1. get_overview()  →  see current state, recent tasks

AI assistant reviews recently created tasks with the user:
"I created 3 tasks recently — let me check these with you:

1. 'Follow up with Sarah about budget numbers'
   Created from: 'She's going to send the budget numbers by Thursday'
   I set this as a follow-up for Friday. Does that work?

2. 'Research vendor Jason mentioned'
   Created from: 'we should probably look into that new vendor'
   I put this in the background importance band. Want to keep it as active or move to someday?

3. 'Buy groceries for weekend'
   From quick capture yesterday. In your Personal list, no due date yet."

User: "1 is good. 2 — move to someday.
       3 — due Saturday."

AI assistant's MCP calls:
2. set_task_someday(task_2)
3. update_task(task_3, {due_date: "2026-03-01"})
```

## AI assistant's Decision Framework

### When to Create a Task
- User explicitly says "create a task" / "remind me" / "I need to" → always create
- User describes a commitment in conversation → create with medium confidence, confirm with user
- User mentions something vague ("would be nice to...") → ask for clarification before creating
- User describes someone ELSE's task → don't create (or create a follow-up trigger)

### When to Create Directly vs Ask First
- Explicit user request → create directly in appropriate list
- Clear action extracted from context → create and confirm with the user in conversation
- Vague or ambiguous → ask for clarification before creating

### How to Estimate Duration
- Phone call / email: 10-15m
- Quick administrative task: 15-30m
- Review or read something: 30-60m
- Writing or creative work: 60-120m
- Complex analysis or coding: 120-240m
- Fill `estimated_minutes` when you have a confident rough time cost
- Leave it blank when confidence is low instead of inventing fake precision
- Adjust based on historical data if available

### How to Set Priority
- Use priority to express importance, not as a second due-date field
- Let due_date, planned_date, overdue state, and focus decisions carry most urgency semantics
- Raise priority when the task is strategically important, high-consequence, or repeatedly protected by the user
- Lower priority when the task matters less even if it is still due someday

### How to Choose a List
- Match to existing lists by semantic similarity
- If no good match → suggest creating a new list
- When unsure → assign to default list and note in ai_notes

---

## Session Start Protocol

AI assistant should follow this sequence when a session needs broad context:

1. **`get_session_context()`** — All-in-one bounded broad-context call. Returns `notes_for_ai` (if set) separately from a bounded AI-generated memory summary (most recent 10 entries with 500-char previews), plus compact overview, today's focus, today's calendar events, recent AI Activity (`ai_changelog`, last 10), and contextual guide.
2. **Act** based on context from the response. For focused tasks, you may skip `get_session_context()` and use narrower reads directly. For full memory content (when you need to read or update a specific section in detail), use `read_memory(key)` separately.

At the **end of significant sessions**, AI assistant should update memory:
- `write_memory("recent_activity", ...)` — What happened this session
- `write_memory("list_summaries", ...)` — If list state changed
- `write_memory("pending_followups", ...)` — Things noticed but not yet acted on
- For MCP friction, missing tools, bugs, or feature ideas, open a GitHub Issue.
  Lorvex intentionally has no in-app or MCP feedback submission path.

### AI Memory Sections

AI assistant maintains these persistent memory sections:

| Key | Purpose | Update frequency |
|-----|---------|-----------------|
| `user_profile` | Working hours, energy patterns, communication style, preferences | Rarely (when learning something new) |
| `list_summaries` | Active lists, status, blockers, deadlines | After sessions that change list state |
| `behavioral_patterns` | Deferral habits, time estimation accuracy, completion rates | Weekly or when patterns shift |
| `recent_activity` | What happened in last few sessions | Every session |
| `pending_followups` | Things AI assistant noticed but hasn't acted on | Every session |

Memory should be written as if the user will read it (they can see it in the app). Be respectful, honest, and useful. Flag uncertainty explicitly.

## The get_overview() Pattern

AI assistant should use `get_session_context()` or `get_overview()` when broader situational context matters before making changes. The `get_overview()` call provides:
- All lists with task counts
- Open/overdue/today counts
- Daily plan status
- Recently completed tasks

This prevents AI assistant from operating with stale assumptions. It's the equivalent of a chief of staff checking the dashboard before making recommendations.

---

## Error Recovery Patterns

### AI assistant Created a Duplicate Task
```
AI assistant detects (via search_tasks) that a similar task already exists.
→ Delete the duplicate
→ Log in changelog: "Removed duplicate of 'Call dentist' — original exists in Health list"
→ Optionally merge any unique details into the original
```

### AI assistant Assigned Wrong List
```
User: "That hotel task should be in the Spain Trip list, not Personal"
AI assistant: update_task(id, {list_id: spain_list_id})
→ Changelog: "Moved 'Confirm hotel' from Personal to Spain Trip (user correction)"
```

### AI assistant's Priority Was Wrong
```
User: "The API docs aren't urgent, put it in the background band"
AI assistant: update_task(id, {priority: 3})
→ ai_notes: "User explicitly deprioritized this."
```

---

## AI assistant's System Prompt Design (for MCP Context)

When an MCP client connects to the MCP server, AI assistant should have context about HOW to use the tools effectively. This could be provided via the MCP server's tool descriptions, or via the user's assistant system prompt.

Key instructions AI assistant needs:
1. Use `get_session_context()` when you need bounded broad context, or `get_overview()` / narrower reads when the task is already focused
2. Write human-readable summaries in all changelog entries
3. Store `raw_input` for any task created from natural language
4. Write `ai_notes` explaining reasoning for non-obvious decisions
5. Use batch operations when creating/updating multiple tasks
6. Confirm uncertain tasks with the user in conversation — better to ask than to be wrong
7. When user corrects an AI decision, learn from it (update ai_notes)
8. When proposing today's focus, explain WHY each task was chosen
10. Keep duration estimates realistic — round up, not down

---

## What This Means for MCP Tool Design

The tool descriptions in the MCP server should be detailed enough that AI assistant can use them without external documentation. Each tool description should include:
- What the tool does
- When to use it (and when NOT to)
- Example usage patterns
- What the return value contains

This is important because the tool descriptions are AI assistant's "instruction manual" for operating the system. Poor tool descriptions = poor AI assistant behavior = poor user experience.

Example of a good tool description:
```
create_task: Create a new task in the system.

Use this when the user explicitly requests a task, or when you identify an
actionable commitment from conversation. For uncertain tasks, confirm with the
user in conversation before creating.

Always provide:
- title (clear, actionable, starts with a verb)
- raw_input (the original user text that led to this task)
- ai_notes (your reasoning for creating this task)

The task will be auto-logged to the AI changelog. The complete task object
is returned — no need for a follow-up get call.
```
