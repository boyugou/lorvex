# UX Design
---

## The Core UX Insight

In a traditional todo app, the UI must be complex because the human is making decisions — scanning lists, comparing priorities, deciding what to do, organizing structure. All of that requires visual information, controls, and navigation.

In an AI-native app, the AI has already made those decisions. The UI's job is to present the AI's output cleanly and let the human act on it with minimal friction.

**This means we can strip away most of what traditional todo apps display:**
- No priority dropdowns in default task rows (AI set it; Quick Capture and task detail can expose correction controls)
- No sort controls in the default briefing flow (AI ordered it; browsing views can expose scoped sort controls)
- No filter bars in the default briefing flow (AI curated it; full-list views can expose filters for inspection)
- No mandatory Inbox or uncategorized lane in normal task creation
- No permanent sidebar full of navigation (you mostly look at one view)
- No complex forms as the primary creation path (optional metadata controls stay secondary/collapsible)

Current-product exception: AI-managed priority remains canonical, while human override and power-user controls are shipped correction affordances. The daily briefing stays sparse; Quick Capture, task detail, context menus, filters, and browsing views may expose priority/list controls to correct or inspect AI output.

What remains: **a clean reading experience with occasional taps.**

---

## Design Language

### Aesthetic DNA

The app should feel like a **well-designed morning briefing from a trusted assistant** — not a database management interface.

What we want:
- **Calm, focused task design.** Generous whitespace, typography-driven hierarchy, a quiet feel.
- **Confident density when it earns its place.** Dark mode first; monochrome with selective color.
- **An editorial, personal, reflective tone** for review and journaling surfaces.
- **Information hierarchy through layout and type, not chrome** — visually calm even when data-dense.

What we avoid:
- Heavy chrome and visual noise that crowds out the content.
- A blank, un-opinionated canvas that leaves the user to do all the structuring.
- A purely utilitarian look with no warmth.
- A non-native feel — the app should feel at home on its platform, not like a wrapped web page.

### Typography-First Hierarchy

With fewer controls and less chrome, typography carries the entire information hierarchy:

```
24pt Semibold        Date / primary heading
17pt Medium          Section titles ("Today's Focus", "Due Today")
15pt Regular         Task titles
13pt Regular 50%     Supporting text (AI reasoning, metadata)
11pt Regular 40%     Timestamps, counts, tertiary info
```

Font: SF Pro (system font). Use SF Mono only for AI-generated content to create subtle visual distinction.

### Color Philosophy

Color should be **meaningful, not decorative.** In an interface this simple, every bit of color carries signal:

- **App accent:** A single calm color — indigo or deep teal. Not red, not orange. This isn't urgent; it's intelligent.
- **Priority dots:** The only place multiple colors appear. Small (8pt), unobtrusive.
- **AI-authored content:** Subtle background tint (indigo at 5% opacity). Just enough to distinguish from human content.
- **Overdue indicators:** System red, but small — a dot or text color, not a screaming banner.
- **Everything else:** Monochrome. Black/white text on neutral backgrounds.

### Dark Mode First

Most productive knowledge workers prefer dark mode for extended use. Design in dark mode first, then verify light mode works. Not the other way around.

---

## Layout: Collapsible Sidebar + Content

The layout balances two needs:
1. **Today view should feel clean and focused** — minimal chrome when you're just checking what to do
2. **Humans need to browse all their tasks** — by list (Work, Personal, Paper), by timeframe, by status

Solution: **collapsible sidebar.** Visible by default (for navigation and browsing), but can be hidden to go full-width for the Today view.

```
┌──────────────────────────────────────────────────────────────┐
│  Toolbar: [◀▶]  Today                              [⌘K]     │
├──────────────┬───────────────────────────────────────────────┤
│              │                                               │
│  SIDEBAR     │   MAIN CONTENT                                │
│  (collapsible│                                               │
│   ~200pt)    │   Friday, February 28                         │
│              │                                               │
│  ○ Today [5] │   Today's Focus                                │
│  ○ Next 7d   │   ○  Write intro section              45m    │
│  ○ All Tasks │   ○  Confirm Barcelona hotel          10m    │
│  ───────     │   ○  Review PR #287                   30m    │
│  ○ AI Log    │                                               │
│  ───────     │   Today Tasks                              │
│  Lists:      │   ○  Team sync prep                   30m    │
│  ● Work [12] │   ○  Submit expense report            15m    │
│  ● Personal  │                                               │
│  ● Paper [4] │   ⚠ 2 overdue                           [▸]  │
│  ● Spain     │                                               │
│  + New List  │                                               │
│              │                                               │
└──────────────┴───────────────────────────────────────────────┘
```

**Key decisions:**
- Sidebar shows smart views (Today, Next 7 Days) + user lists with task counts
- Lists represent real categories the human wants to browse: Work, Personal, Paper, Spain Trip, etc.
- Sidebar is collapsible (⌘⇧L or a toggle button) for full-width mode
- ⌘K command palette works regardless of sidebar state
- Overdue count badge in sidebar provides at-a-glance risk awareness

**Today view** is the default and is curated (see below). But the human can click any list in the sidebar to see ALL tasks in that category — this is a **full browsing view**, not AI-curated.

### Two Modes of Task Display

**Curated views (Today):** AI has already filtered and ordered. Task rows are minimal — checkbox + title + duration. No metadata noise.

**Browsing views (List view, All Tasks, Next 7 Days):** Human is scanning and reading. Task rows show more context — checkbox + title + due date + duration + status. Still clean, but enough metadata to orient yourself when reading through 20+ tasks.

This distinction matters. The simplification applies to AI-curated views. Browsing views need enough information for the human to understand their landscape.

---

## Today View (AI-Curated)

The default view. Shows tasks where `planned_date <= today` OR (`planned_date IS NULL` AND `due_date <= today`). This is where radical simplicity lives.

```
Friday, February 28

Today's Focus
───────────────────────────────────────────
○  Write intro section                 45m
○  Confirm Barcelona hotel booking     10m
○  Review PR #287                      30m

Today Tasks
───────────────────────────────────────────
○  Team sync prep                      30m
○  Submit expense report               15m

⚠ 2 overdue                              ▸
```

- "Today's Focus" = the ordered subset from `current_focus`, set by AI assistant via MCP
- "Today Tasks" = other tasks in the today pool not in today's focus
- Overdue collapsed by default
- Task rows are minimal: checkbox + title + duration
- If AI assistant has written a briefing note (via the `set_current_focus` MCP tool's `briefing` field), it appears as light text above Today's Focus

**Important: the "Today's Focus" section shows tasks from `current_focus`, set by AI assistant via the `set_current_focus` / `add_to_current_focus` MCP tools.** The app doesn't decide what's in focus — it reads the `current_focus` table. The rest of the Today view is populated by the `planned_date`/`due_date` query.

---

## List Browsing View (Human Reading)

When the user clicks a list (e.g., "Work") in the sidebar, they see ALL tasks in that list. This is a full reading view.

```
Work                                           12 tasks
───────────────────────────────────────────────────────

Open (8)
○  Write intro section          Mar 1    45m    ●●
○  Review PR #287               Today    30m    ●●
○  Send Q4 report draft         Overdue  —      ●●●
○  Team sync prep               Today    30m    ●
○  Submit expense report        Today    15m    ●
○  Update API docs              Mar 5    2h     ●
○  Prepare board presentation   Mar 10   —      ●●
○  Refactor auth module         —        —      ○

Completed recently (3)
✓  Fix login bug                         Feb 26
✓  Write unit tests                      Feb 25
✓  Review Q3 budget                      Feb 24
```

- More metadata per row: title + due date + duration + priority indicator
- Grouped by status (open / completed)
- Completed tasks shown with completion date
- This is a browsing/reading view — the human wants to see everything in their Work category
- Still no complex controls in the default reading flow. AI ordered these by priority; browsing and correction surfaces can expose scoped sort/filter/priority/list controls without making the task row a management console.
- Right-click on any task for context menu (Complete, Defer, Open Detail, etc.)

---

## Next 7 Days View

```
Next 7 Days
───────────────────────────────────────────────────────

Today — Friday, Feb 28                          5 tasks
○  Write intro section                Work     45m
○  Confirm hotel booking            Personal   10m
○  Review PR #287                     Work     30m
○  Team sync prep                     Work     30m
○  Submit expense report              Work     15m

Tomorrow — Saturday, Mar 1                      2 tasks
○  Grocery shopping                 Personal    30m
○  Call parents                     Personal    20m

Monday, Mar 3                                   3 tasks
○  Prepare for standup                Work     15m
○  Follow up with Jason               Work     10m
○  Start grant budget section         Paper     2h

Wednesday, Mar 5                                1 task
○  Update API docs                    Work      2h
```

- Tasks grouped by day
- List badge shown (because tasks span multiple lists, need context)
- Days with many tasks get a subtle background to signal load
- Empty days can be hidden or shown as "— Nothing scheduled"

---

## Why Minimal Metadata on Task Rows

In the earlier UX doc, task rows had: checkbox, title, list badge, priority dots, duration. That's 5 elements per row.

Revised: **checkbox + title + duration.** That's it.

Why? Because the metadata was there to help the HUMAN make decisions about the task. But the AI already made those decisions. The list badge told you "this is a Work task" — but you don't need that to complete it. The priority dot told you "this is high priority" — but AI already put it in the Today's Focus section.

The human's question when looking at the briefing is not "what priority is this?" It's "should I do this next?" And the answer is yes, because AI already selected it.

If you want to see the full metadata, click the task → detail popover appears.

**Exception: when browsing All Tasks or a specific List.** In these views, some metadata is useful for orientation (list name, due date, status). These views restore a few metadata columns. But the daily briefing view is stripped to essentials.

---

## Task Interaction

### Click/Tap a Task → Detail Popover

Not a full side panel (too heavy for the minimal layout). A popover or sheet:

```
┌──────────────────────────────────────┐
│  Write intro section                  │
│  ──────────────────────────────────  │
│  Due: Friday, Mar 1    Duration: 45m │
│  List: Paper           Created: Feb 26│
│                                      │
│  Notes                               │
│  Cover: motivation, related work,    │
│  contributions. See outline doc.     │
│                                      │
│  ┌ AI Notes ────────────────────┐    │
│  │ Blocks "Submit draft" (Mar 4)│    │
│  │ Deferred twice. This is your │    │
│  │ highest-leverage task today. │    │
│  └──────────────────────────────┘    │
│                                      │
│  [Complete ✓]  [Defer →]  [···]      │
└──────────────────────────────────────┘
```

- Opens as a floating popover near the clicked task
- Dismiss by clicking outside or pressing Escape
- Lightweight — doesn't feel like navigating to a new screen
- AI Notes visually distinguished (subtle tinted background)
- Actions at the bottom: Complete, Defer, and overflow menu (Delete, Edit)

### Actions Per Task (Exhaustive List)

| Action | How | Where |
|---|---|---|
| Complete | Click checkbox (anywhere) or ⌘⏎ | Any view |
| Defer | Swipe left or right-click → Defer | Any view |
| See details | Click title | Any view |
| Edit title | Double-click title | Any view |
| Delete | Right-click or via detail popover | Any view |

**That's the entire human action set.** 6 actions. Nothing else. Everything else is AI assistant's job via MCP.

---

## The Inbox [CUT]

The Inbox UI/review surface was removed. The conversation with the AI assistant is the review layer, and tasks are created directly as `open` status with proper list assignment. The schema-seeded `inbox` default list remains only as a bootstrap/default-routing artifact.

---

## AI Activity (`ai_changelog`)

A dedicated view showing what AI assistant has done. Critical for trust.

```
┌─────────────────────────────────────────────────────────┐
│  [≡]  AI Activity                              [⌘K]    │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  Today                                                  │
│                                                         │
│  09:14  Created 3 tasks from Spain trip planning   [↩] │
│         Book hotel · Confirm dentist · Follow up Sarah  │
│                                                         │
│  09:22  Raised priority on "Book flights"          [↩] │
│         Group discount expires in 5 days                │
│                                                         │
│  Yesterday                                              │
│                                                         │
│  16:30  Marked "Review Q3 budget" complete         [↩] │
│                                                         │
│  16:28  Moved "Write blog post" to Someday         [↩] │
│         Postponed 4 times, no deadline pressure         │
│                                                         │
│  This week                                              │
│                                                         │
│  12 tasks completed · 3 postponed · 5 new tasks created│
│                                                         │
└─────────────────────────────────────────────────────────┘
```

- Grouped by time period
- [↩] undo on hover (for recent entries)
- Plain English descriptions, not technical logs
- Weekly summary at the bottom
- Clicking any entry navigates to the related task

---

## Quick Capture (Menu Bar)

```
         [icon in menu bar]
              ↓ click
┌──────────────────────────────────────┐
│                                      │
│  ▌ finish the intro before friday    │
│                                      │
│                          [⏎ Create]  │
└──────────────────────────────────────┘
```

- Appears as a floating field near the menu bar
- Shortcut: ⌘N (main-window scope; registered via the native app menu, not a global hotkey)
- Just a text field. Nothing else.
- Press Return → creates a task directly in the selected list (or default list) with the raw text as the title
- **No AI processing happens here.** The app has no AI inside it. It just saves the text.
- The user can also tell AI assistant in an MCP client "create a task for X" — which is the AI-powered creation path with full metadata

---

## Daily Experience Map

What does using this app feel like hour by hour?

**7:30 AM — Wake up**
Notification on lock screen (optional): "3 tasks for today. Intro section is the priority."

**8:00 AM — Morning review**
Open the app. See the briefing. AI's note: "The intro is your highest-leverage task — it unblocks Friday's deadline." Review the 3 focus items. Adjust if needed. Start working.

**8:15 AM — Start working**
"Write intro section" is the top of Today's Focus. Work on it.

**9:45 AM — Done**
Check it off. Task completes. "Confirm Barcelona hotel" is next. Do it in 5 minutes.

**10:00 AM — Quick capture**
On a call, someone mentions a follow-up. ⌘N → "follow up with Jason about the API integration" → Return. Done. AI assistant handles the rest.

**12:00 PM — Quick glance during lunch**
Open the app. Two tasks captured this morning are already in their lists. Everything looks right.

**3:00 PM — Stuck on something**
Open your MCP client. "What should I work on this afternoon? I have about 2 hours." AI assistant queries MCP, looks at your remaining tasks, suggests 2 items. You say "schedule those." Done.

**6:00 PM — End of day**
Glance at the app. 4 of 5 tasks completed. One deferred to tomorrow. Close laptop.

**There is no target "minimum app time."** Some days this is a few quick check-ins; some days you keep Lorvex open for hours, working from Today's Focus and the calendar. The important part is that AI assistant did the maintenance work.

**Friday afternoon — Weekly review (15 minutes)**
Open weekly review. AI has pre-populated: 12 tasks completed, 3 carried over, 2 projects stalled, 1 suggestion ("archive the photo library task — deferred 6 times"). You make a few decisions, AI executes. Done.

---

## Keyboard Shortcuts

| Action | Shortcut |
|---|---|
| Quick Capture | ⌘N |
| Command palette | ⌘K |
| Complete selected task | ⌘⏎ |
| Defer selected task | ⌘D |
| Task detail | ⏎ or Space |
| Navigate tasks | ↑↓ |
| Open navigation | ⌘⇧L |
| Search | ⌘F |

---

## Animation & Motion

- Task completion: checkbox fills smoothly (0.2s), row fades gently (not a big celebration)
- Popover/detail: appears with subtle scale (0.15s)
- Navigation panel: slides from left (0.2s)
- Toast notifications: slide from bottom, auto-dismiss 3s
- Undo toast: countdown bar animation

Philosophy: **motion confirms actions; it does not celebrate them.** This is a work tool, not a game. No confetti, no badges, no leaderboards. Lightweight progress indicators (completion streaks, habit streaks) are acceptable as informational context — they help users notice patterns, not chase rewards.

---

## Open Design Questions (Revised)

1. **Launch display name** — finalized as `Lorvex`.

2. **How dense should the "Today Tasks" section be?** Collapsed with a count? Always expanded? Probably: expanded if ≤5 items, collapsed if more.

3. **Should AI's contextual note at the top be dismissible?** Probably yes — once you've read it, it's served its purpose. But it should return on next app open.

4. **What happens when there's nothing to do?** Empty state should feel good, not anxious. Something like: "All clear for today. Enjoy your day." Not: "No tasks! Add some!" We're not trying to create work.

5. **Should the detail popover support Markdown editing for notes?** Probably yes for body field, but make it view-mode by default, edit on tap. Most of the time you're reading, not writing.

6. **Calendar integration for Today's Plan view** — how prominent should calendar events be in the briefing? They provide context (you can see your free windows) but they're not tasks. Consider: show them as subtle time markers between focus items, not full blocks.
