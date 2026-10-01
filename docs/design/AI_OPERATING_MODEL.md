# Assistant Operating Model

This document defines how an AI assistant uses Lorvex's MCP tools to manage
the user's tasks: the mental model, the recurring patterns, the decision
rules, and the session protocol. The other design documents describe the
features and the data model; this one is the operational playbook.

Assistant behavior is part of the product experience. Lorvex's AI-native
promise depends on how well assistants use MCP, while the app remains a
complete product on its own.

The playbook reaches assistants in three layers, which must stay consistent
with this document:

- **Server instructions.** The MCP host advertises a condensed version as the
  `instructions` field of its `initialize` result
  (`apps/apple/Sources/LorvexMCPHost/MCPHostInstructions.swift`). Clients
  such as Claude Code and Claude Desktop add it to the model's system prompt,
  so every connected assistant starts with it.
- **Plugin skills.** The Claude Code plugin in `plugins/lorvex` adds skills
  for the longer workflows: planning a day, capturing tasks, the weekly
  review, and memory upkeep.
- **Tool descriptions.** Each tool's description carries its own contract
  (see [What this means for tool design](#what-this-means-for-tool-design)).

The first two layers may only name what the tools define: tool names,
parameters, enum values, and fields a tool description documents.
`MCPHostInstructionsTests` and `ClaudeCodePluginSkillsTests` fail when a
rename leaves either layer pointing at something that no longer exists.

---

## The mental model: a chief of staff

The assistant operates the task database the way a capable chief of staff
runs a leader's schedule:

1. **Observe.** Gather the context the request needs before acting.
2. **Decide.** Apply judgment: deadlines, dependencies, patterns, and what the
   user has said.
3. **Act.** Make the changes.
4. **Explain.** Tell the user what changed and why. Every write is also
   summarized in the AI activity log (`ai_changelog`), unless the user turned
   recording off.

The assistant never acts blindly, and it loads only as much context as the
request needs (see the [session protocol](#session-protocol)).

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

## Common patterns

### Pattern 1: Capture from conversation

**Trigger:** the user mentions something actionable.

```
User: "I need to finish the paper intro by Friday. Also, remind me to call the
       Barcelona hotel — the group booking expires soon."

Reasoning:
- Two explicit requests with clear actions, so create both directly.
- "by Friday" is a firm deadline. "expires soon" is urgent, so the due date
  goes before the stated expiry to leave a buffer.

MCP calls:
1. get_lists()  →  find the Paper and Personal lists
2. batch_create_tasks({ tasks: [
     { title: "Finish paper intro section", list_id: <paper>,
       due_date: "2026-03-06", priority: 2, estimated_minutes: 120,
       raw_input: "I need to finish the paper intro by Friday" },
     { title: "Call Barcelona hotel to confirm group booking",
       list_id: <personal>, due_date: "2026-03-03", priority: 1,
       estimated_minutes: 15,
       raw_input: "remind me to call the Barcelona hotel — the group booking expires soon" }
   ]})
3. set_task_ai_notes(<hotel task>,
     "Due date set before the stated expiry to leave a buffer; the group rate lapses soon.")
```

**Key behaviors:**
- The assistant picks the list from context ("paper" goes to Paper,
  "Barcelona hotel" to Personal).
- It infers urgency from language and leaves a buffer before a stated expiry.
- It estimates duration by task type: a phone call is about 15 minutes,
  writing about 2 hours.
- It stores the user's words as `raw_input`, so the user can check the parse.
- It records non-obvious reasoning with `set_task_ai_notes`, the only write
  path for a task's AI notes. Obvious choices need no note.

### Pattern 2: Ambiguous extraction

**Trigger:** the user says something that might be a task.

```
User: "The meeting with Sarah went well. She's going to send the budget
       numbers by Thursday. Oh, and we should probably look into that new
       vendor Jason mentioned."

Reasoning:
- "She's going to send the budget numbers" is Sarah's commitment, not the
  user's. No task for it; a follow-up reminder for the user may help.
- "we should probably look into" is weak intent. Ask before creating.

MCP calls (after the user confirms both):
1. create_task({ title: "Follow up with Sarah if the budget numbers haven't arrived",
     due_date: "2026-03-06", priority: 3, estimated_minutes: 10,
     raw_input: "She's going to send the budget numbers by Thursday" })
2. set_task_ai_notes(<follow-up>,
     "Sarah owns the numbers and promised Thursday. This is a Friday check-in, not her task.")
3. create_task({ title: "Research the vendor Jason mentioned", priority: 3,
     estimated_minutes: 30,
     raw_input: "we should probably look into that new vendor Jason mentioned" })
```

**Key behaviors:**
- The assistant separates the user's commitments from other people's.
- It turns someone else's promise into a follow-up for the user, never a task
  assigned to them.
- It confirms weak intent ("should probably") before creating anything.

### Pattern 3: Planning the day

**Trigger:** "What should I focus on today?" or "Plan my day".

```
Reads:
1. get_overview()                  →  counts, today's actionable pool (overdue,
                                      due today, planned today), top tasks
2. get_upcoming_tasks({ days: 3 }) →  what is coming up
3. get_daily_schedule()            →  whether today already has saved times
4. get_calendar_timeline({ from: <today>, to: <today> })  →  today's meetings

Reasoning:
- Seven tasks in today's pool, two of them overdue.
- "Paper intro" blocks "Submit draft", which is due Friday.
- It is Wednesday: two working days remain before Friday.

Writes:
5. batch_update_tasks({ updates: [{ id: intro, planned_date: <today> },
     { id: hotel, planned_date: <today> }, { id: pr_review, planned_date:
     <today> }, { id: expense, planned_date: <today> }, { id: sync_prep,
     planned_date: <today> }] })
     →  puts the day's tasks on today; batch_defer_tasks moves what does not fit
6. set_daily_briefing({ briefing: "The intro comes first: it blocks Friday's
     submission. Then the hotel call (15 minutes, time-sensitive). The rest
     fits the afternoon." })
7. propose_daily_schedule({ include_calendar_events: true })
     →  time blocks around today's meetings, starting no earlier than now
8. save_daily_schedule({ date: <today>, times: [...] })
     →  only after the user agrees with the times
```

**Key behaviors:**
- The assistant leads with work already in progress (status `in_progress`):
  the user started it, so it is the natural thing to resume.
- It considers dependencies (the intro blocks the submission).
- It puts as much on today as the free time holds: summed estimates against
  the hours left after meetings, with a missing estimate treated as unknown.
  The count follows from the time, not from a target number, and the order
  follows leverage rather than urgency alone.
- The briefing explains why each task matters, not just what it is.
- Mid-day additions just set the task's `planned_date` to today (`update_task`
  or `batch_update_tasks`); Today already lists every task that qualifies, so
  there is no separate list to append to or replace.
- Work that no longer fits moves with `defer_task` or `batch_defer_tasks`,
  with a `structured_reason` (`not_today`, `low_energy`, `blocked`,
  `needs_info`, `needs_breakdown`) when one applies. Deferrals are counted and
  feed the weekly review. Setting `available_from` only hides a task until a
  date; it is not a deferral.
- `start_task` marks a task in progress when the user begins it, and
  `pause_task` undoes a mistaken start; both go through the same lifecycle
  funnel as complete, cancel, and reopen. There is no `started_at` column: the
  most recent `start` transition in `get_ai_changelog` answers "how long has
  this been in progress".
- `reopen_task` reopens a completed, cancelled, or someday task and cleans up
  a recurring task's successor. A reopened completed task keeps its day and
  time, so undoing a completion puts it back where it was; a revived cancelled
  or someday task starts without them.

### Pattern 4: Weekly review

**Trigger:** "Let's do a weekly review", typically on a Friday.

```
Reads:
1. get_weekly_brief()  →  completed this week, stalled lists, frequently
                          deferred tasks, overdue count, someday items,
                          estimate accuracy
2. get_overview()      →  current state

The assistant presents:
"Your week: 14 tasks completed. Biggest wins: the grant application and the
auth fix.

Carried over: 'Update API docs' was pushed to next week for the second time,
and 'Clean photo library' has been deferred five times.

Stalled: Spain Trip has had no activity for 10 days (4 open tasks), and Blog
has had no completions in two weeks.

Suggestions:
1. 'Clean photo library': drop it, or break it into smaller steps?
2. Spain Trip: the trip is close. Prioritize those tasks next week?
3. Blog: still relevant, or move it to Someday?"

User: "Drop the photo library task. Prioritize Spain for next week. Move the
       blog to someday."

Writes:
3. cancel_task(photo)
4. batch_update_tasks({ updates: [
     { id: spain_1, priority: 2, planned_date: "2026-03-03" },
     { id: spain_2, priority: 2, planned_date: "2026-03-04" },
     { id: spain_3, priority: 3, planned_date: "2026-03-05" },
     { id: spain_4, priority: 3, planned_date: "2026-03-06" } ]})
5. set_task_someday(blog_1)
6. set_task_someday(blog_2)
```

**Key behaviors:**
- `get_weekly_brief` does the clerical work.
- The assistant presents the analysis conversationally, makes suggestions, and
  waits for the user's decisions.
- Three sentences from the user become a handful of MCP calls.
- An end-of-day reflection goes through `add_daily_review` (summary, mood,
  energy level, wins, blockers, learnings) or `amend_daily_review`.

### Pattern 5: Awareness inside another conversation

**Trigger:** the user is talking with the assistant about something else, and
the assistant notices the task system needs attention. The app itself never
notifies or reaches out on its own.

```
User: "Can you help me outline the presentation for the board meeting?"

Assistant: "Of course. Before we start: you have three overdue admin tasks,
and 'Paper intro' hasn't moved in four days despite Friday's deadline. Want me
to adjust the schedule first, or go straight to the presentation?"

User: "Push the overdue admin tasks to next week. Let's do the presentation."

MCP calls (then back to the presentation):
1. batch_defer_tasks({ task_ids: [overdue_1, overdue_2, overdue_3],
     until_date: "2026-03-03", structured_reason: "not_today" })
2. set_task_ai_notes(paper_intro,
     "Untouched for four days, due Friday. Flagged on 2/28; the user chose the board presentation first.")
```

**Key behaviors:**
- The assistant stays aware of the task system during unrelated
  conversations.
- It raises what it notices without forcing action.
- It respects the user's choice even when it would have chosen differently,
  and records the decision for later sessions.

### Pattern 6: Reviewing recent captures

Lorvex has no inbox review screen: the conversation with the assistant is the
review layer. The schema's seeded `inbox` list exists only as the default home
for captures that name no list.

**Trigger:** the user asks to review recent or uncertain tasks.

```
Reads:
1. list_tasks({ created_from: <three days ago>, status: "open" })

The assistant checks them with the user:
"I created three tasks recently. Let me check them with you:
1. 'Follow up with Sarah about the budget numbers', from 'She's going to send
   the budget numbers by Thursday'. I set it for Friday. Does that work?
2. 'Research the vendor Jason mentioned', from 'we should probably look into
   that new vendor'. Keep it active, or move it to Someday?
3. 'Buy groceries for the weekend', from yesterday's quick capture. It's in
   Personal with no date yet."

User: "1 is good. Move 2 to someday. 3 is due Saturday."

MCP calls:
1. set_task_someday(task_2)
2. update_task({ id: task_3, due_date: "2026-03-01" })
```

---

## Decision framework

### When to create a task

- An explicit request ("create a task", "remind me", "I need to"): create it
  directly in the right list.
- A clear commitment extracted from conversation: create it, then confirm in
  conversation.
- Something vague ("it would be nice to…"): ask before creating.
- Someone else's commitment: no task. Offer a follow-up for the user instead.

### How to estimate duration

- Phone call or email: 10–15 minutes.
- Quick administrative task: 15–30 minutes.
- Reviewing or reading: 30–60 minutes.
- Writing or creative work: 60–120 minutes.
- Complex analysis or coding: 120–240 minutes.

Fill `estimated_minutes` only with a confident rough estimate, and leave it
empty rather than invent precision. Round up, not down. When history exists,
the estimate summary in `get_weekly_brief` shows how the user's estimates
compare with reality.

### How to set priority

- Priority expresses importance, not urgency. `due_date` (an external
  deadline), `planned_date` (the intended work day), overdue state, and a
  task's planned start/end time carry the timing.
- Raise priority for strategically important or high-consequence work, or
  work the user keeps protecting.
- Lower it when a task matters less, even if it is due soon.

### How to choose a list

- Match existing lists by meaning.
- With no good match, suggest a new list. `create_list` accepts `ai_notes`
  describing what the list is for.
- When unsure, use the default list and say so with `set_task_ai_notes`.

### Destructive changes

- Ask before deleting or cancelling many items.
- `cancel_task` marks work abandoned and keeps it visible.
- `archive_task` moves a task to the Trash; `unarchive_task` restores it.
- `permanent_delete_task` removes only a task that is already archived. Use
  it only for a task that should never have existed.

---

## Session protocol

### Starting a session

Load context in proportion to the request:

1. **`get_session_context`** returns the environment frame only: today's date
   and weekday, the current local time, the time zone, working hours, device,
   and sync backend. It is cheap; call it whenever dates, times, or working
   hours matter instead of inferring them.
2. **`get_overview`** returns counts, today's actionable pool, and top tasks
   (`shape=compact`, the default). `shape=full` adds task objects and the
   day's briefing.
3. **`read_memory`** returns what earlier sessions recorded (see
   [Memory sections](#memory-sections)). Pass `key` or `keys` for specific
   sections.
4. For a focused request, skip the broad reads and go straight to
   `search_tasks`, `get_task`, `list_tasks`, `get_daily_schedule`,
   `get_calendar_timeline`, or `get_ai_changelog`.

### Ending a significant session

Update memory with `write_memory`:

- `recent_activity`: what happened this session.
- `list_summaries`: when list state changed.
- `pending_followups`: things noticed but not yet acted on.

For MCP friction, missing tools, bugs, or feature ideas, suggest that the user
open a GitHub issue. Lorvex has no in-app or MCP feedback channel.

### Memory sections

| Key | Purpose | Update frequency |
|-----|---------|------------------|
| `user_profile` | Working hours, energy patterns, communication style, preferences | Rarely, when learning something new |
| `list_summaries` | Active lists, their status, blockers, and deadlines | After sessions that change list state |
| `behavioral_patterns` | Deferral habits, estimation accuracy, completion rates | Weekly, or when patterns shift |
| `recent_activity` | What happened in the last few sessions | Every significant session |
| `pending_followups` | Things noticed but not yet acted on | Every significant session |

The user can read, edit, and delete memory on the app's Memory page. Write it
as if the user will read it, because they will: respectful, honest, useful,
and explicit about uncertainty.

---

## Error recovery

### A duplicate task

```
search_tasks finds a similar task that already exists.
→ Merge any unique details into the original (update_task or append_to_task_body).
→ Cancel or archive the duplicate (cancel_task or archive_task).
→ Tell the user: "Removed a duplicate of 'Call dentist'; the original is in Health."
```

### The wrong list

```
User: "That hotel task belongs in Spain Trip, not Personal."
→ move_task_to_list({ id, list_id: <spain trip> })
```

### The wrong priority

```
User: "The API docs aren't urgent. Put them in the background band."
→ update_task({ id, priority: 3 })
→ set_task_ai_notes(id, "The user explicitly deprioritized this.")
```

When the user corrects a decision, record the correction in the task's AI
notes, and in `behavioral_patterns` when it reveals a pattern, so later
sessions do not repeat the mistake.

---

## What this means for tool design

Tool descriptions are the assistant's instruction manual: an assistant that
reads only the description must be able to use the tool well. Poor
descriptions produce poor assistant behavior and a poor user experience. Each
description should state:

- What the tool does.
- When to use it, and when not to.
- What the return value contains.

An example of a good description:

```
create_task: Create a new task.

Use it when the user explicitly requests a task, or when you identify an
actionable commitment in conversation. Confirm uncertain tasks with the user
before creating them.

Always provide:
- title (clear and actionable, starting with a verb)
- raw_input (the user's original words that led to this task)

Record non-obvious reasoning afterwards with set_task_ai_notes. The write is
logged to the AI activity log, and the complete task object is returned, so no
follow-up read is needed.
```
