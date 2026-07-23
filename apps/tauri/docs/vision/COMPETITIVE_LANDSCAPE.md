# Product Category Landscape
A map of the productivity-tool categories Lorvex operates among, and the design lessons we take from each. The point is not to rank other products — it is to state, on their own merits, the design decisions that define Lorvex's position.

---

## Market Map

Two axes describe the space:

- **Vertical** — how much the tool treats *time/duration* as first-class, from pure todo lists at the bottom to calendar/schedule-centric tools at the top.
- **Horizontal** — how much *the AI does* versus *the human does*, from manual on the left to autonomous on the right.

```
                    AI does more →
                    ┌─────────────────────────────────────┐
                    │                                     │
      Calendar/     │   calendar-defense   AI auto-       │
      Schedule      │   tools              schedulers     │
      focused       │                                     │
          ↑         │              ★ THIS APP ★           │
          │         │   (AI operates + human reviews +    │
          │         │    conversation-first + transparent) │
          │         │                                     │
      Task+Time     │   semi-automatic     [empty space]  │
      unified       │   schedulers                        │
          │         │   guided planning rituals           │
      Task/Todo     │                                     │
      focused       │   manual todo apps   AI-assisted    │
                    │                      todo apps      │
                    │                                     │
                    └─────────────────────────────────────┘
                    ← Human does more
```

The semi-automatic scheduler category occupies a useful middle position: it takes time/duration seriously (unlike pure todo apps) and offers auto-scheduling (unlike guided rituals), but its intelligence is algorithmic, not AI. It is the closest category to our spirit — we take its core insight (duration matters) and elevate it with contextual AI reasoning.

We sit in the upper-right quadrant where no product exists yet: **high AI autonomy + unified task and schedule management + transparency.**

---

## Design Lessons by Category

### AI Auto-Schedulers

**What this category does well:**
- Aggressive auto-scheduling that fits tasks into the calendar automatically.
- Dynamic rescheduling when the calendar changes, re-running many times a day.
- Combining task management, calendar, and project management in one place.
- Task chunking (splitting a long task into shorter blocks).

**Failure modes we must avoid:**
- **Black box.** Users don't know WHY the AI scheduled something where it did. No reasoning, no audit trail. This is the dominant complaint about the category.
- **Loss of agency.** Tasks get bumped without warning. Users who want suggestions plus final control feel frustrated.
- **Metadata burden.** You must manually enter priority, deadline, duration, and chunking rules for every task. The AI only automates placement, not understanding.
- **No conversation.** The interface is forms. No way to say "move everything to tomorrow, I'm sick."
- **Missed deadlines handled poorly.** When you miss a deadline, the task is often pushed far into the future instead of the next available slot.
- **Steep learning curve.**

**Our decisions:** Transparent reasoning. Conversation-first input. The full capture-to-schedule loop. AI that understands context, not just metadata.

### Calendar-Defense Tools

**What this category does well:**
- Progressive defense (task events start as free time and flip to busy as the deadline approaches).
- Habit-defense (protecting recurring routines on the calendar).
- A user-controlled slider for how aggressively the AI defends time.
- Non-invasive operation as a calendar overlay rather than a replacement.
- A strong free tier.

**Failure modes we must avoid:**
- **Limited task management.** Not a real task manager — only schedules what you manually define.
- **Weak alerts.** When deadlines are missed or tasks pushed, there is no strong escalation.
- **Rigid hierarchy** (meetings outrank habits, which outrank tasks, which outrank focus time) means focus time always loses.
- **No context.** Treats all one-hour tasks identically.

**Our decisions:** We are a full task management system, not just a calendar overlay. We understand context and the relationships between tasks.

### Guided Planning Rituals

**What this category does well:**
- A structured daily planning ritual (morning planning plus evening shutdown).
- Anti-burnout design with capacity warnings when you overcommit.
- Breadth of integrations, pulling tasks from many external tools.
- A calm, focused aesthetic.
- Duration estimation as a core concept.

**Lesson we take:**
A structured daily planning moment is genuinely valuable — users love the ritual. But the ritual takes 10-15 minutes because the work is manual. Our version keeps the reflective ritual while removing most of the clerical setup: AI pre-populates today's focus, surfaces risks, and prepares decisions.

**Our decisions:** AI does the planning work. The human keeps the judgment, but not the repetitive setup burden.

### AI Meeting Assistants

**What this category does well:**
- Strong design and aesthetics — using these tools feels joyful.
- Bot-free meeting recording (local audio capture, no bot joining the call).
- A meeting-to-action-item pipeline (meetings generate tasks).
- Adjustable split views (e.g. a calendar/tasks slider).

**Cautionary patterns:**
- Drifting focus — pivoting toward meeting notes while calendar/todo features stagnate.
- Sync reliability problems (tasks disappearing between devices) are a trust killer.
- No auto-scheduling.

**Lesson we take:** Aesthetics genuinely matter in productivity tools. "Joy" is not a frivolous quality. When the tool feels good, you use it more consistently.

### Full-Featured Traditional Todo Apps

These set the benchmark for what "full-featured" means in the human-operated category.

**What to take:**
- Smart views (Today, Next 7 Days) as core navigation.
- A rich metadata model.
- Menu bar quick capture.
- Multiple view modes (list, calendar, timeline, Kanban, Eisenhower).

**What to reject:**
- Everything is manual (organization, prioritization, scheduling).
- UI clutter from feature accumulation.
- Cross-platform design compromise.

### Semi-Automatic Schedulers

The closest category to our time-blocking vision.

**What to take:**
- Duration as a required field (a todo without duration is a wish).
- A day-as-timeline view.
- Auto-schedule from a start time.
- Fast batch selection and rescheduling.
- A native platform aesthetic.

**What to reject:**
- The human still does all selection and ordering (auto-schedule is just sequential packing).
- No learning.
- No context awareness.
- Weak project/backlog management.

---

## Where Existing Tools Universally Fall Short

These gaps represent our biggest opportunities:

1. **No transparency.** Few tools explain their AI decisions. Users are left guessing.
2. **No conversation.** Most tools use forms/GUI for task input. None treat natural language as a first-class planning and automation surface.
3. **No context awareness.** AI scheduling tools treat tasks as metadata (priority + deadline + duration). None understand what the task IS, how it relates to other work, or what the user's current life context is.
4. **No full-loop automation.** Tools automate one step (scheduling) but leave capture, organization, prioritization, and review to the human.
5. **No learning feedback.** No tool visibly improves based on user behavior. You can't tell the AI "this was a bad decision" and have it learn.
6. **Mobile runtime gap.** Mobile experiences in this space are often weak afterthoughts. This is a major opening. Our goal is not secondary access to a desktop product, but a genuinely good reduced-capability mobile peer runtime.

---

## Business Model Context

AI-powered productivity tools typically use subscription models; native desktop apps tend toward one-time purchase. Lorvex ships under Apache-2.0 with a local MCP server and operator surface — there is no Lorvex subscription; intelligence costs flow to whichever external MCP-capable assistant the user is already paying for.

---

## Key Takeaway

No existing product does what we're building. The closest would be if you combined:
- **The semi-automatic scheduler's** core philosophy (duration matters, time is real, auto-schedule) — but with AI picking WHICH tasks belong today, not just packing the ones you chose.
- **The AI auto-scheduler's** ambition (but made it transparent, not a black box).
- **The guided ritual's** daily planning moment (but had AI do the prep work).
- **The traditional todo app's** task management depth (but with AI maintaining the system).
- **An AI assistant's** conversational intelligence (as a first-class automation surface, not just form input).

The semi-automatic scheduler category is our closest spiritual ancestor. We adopt its most important insight — a task without duration is a wish — and solve its biggest limitation: the human still has to do all the thinking. Our "auto-schedule" isn't a greedy packing algorithm. It's AI assistant reasoning about your deadlines, dependencies, energy patterns, and life context to propose a plan.

That combination doesn't exist yet. That's the product.
