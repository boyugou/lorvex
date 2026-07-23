# Ideas Log

> Archived historical document. Preserved for reference only; not part of the current implementation contract.


> Historical record only. Entries capture past brainstorming and may use superseded terminology or architectures.
>
> Current source of truth:
> - product/data model: `docs/design/*`
> - execution status: `ROADMAP.md` and `docs/execution/*`

A running record of brainstormed ideas, user insights, and design evaluations. Each entry captures the idea, critical analysis, and outcome.

---

## #001 — Windows/Linux Portability
**Source:** User brainstorm
**Idea:** Ship on Windows and Linux, not just macOS.
**Evaluation:** Correct and already partially addressed. Tauri 2.x is cross-platform by default. The main blocker was the MCP server's hardcoded macOS DB path — fixed by adding platform-specific resolution (`process.platform` switch for darwin/win32/linux). Remaining work: test actual builds on Windows/Linux, handle platform-specific UX quirks (menu bar behavior, window chrome).
**Status:** Accepted. DB path fix shipped. Full cross-platform testing deferred to pre-release.

---

## #002 — Export/Import with Forward Compatibility
**Source:** User brainstorm
**Idea:** Users must be able to export all data and import into future versions, even if schema evolves.
**Evaluation:** Critical for trust and user ownership. Implemented `export_all_data` MCP tool using JSONL format with versioned manifest and per-entity `_type` + `_version` fields. This enables future importers to handle schema evolution gracefully.
**Status:** Shipped. Both `export_all_data` and `import_from_export` MCP tools implemented.

---

## #003 — Open Source / Monetization / Distribution
**Source:** User brainstorm
**Idea:** Consider open source model, monetization strategy, and distribution.
**Evaluation:** These are separate decisions that interact with each other. Open source builds trust and community. Distribution affects packaging, updates, support, and platform review constraints. For the Tauri line, the durable decision is direct desktop distribution for Windows/Linux, with macOS retained as a developer/reference build rather than a customer App Store channel.
**Status:** Superseded for Tauri. Apple App Store distribution belongs to the Swift app under `apps/apple`.

---

## #004 — MCP-First, Then OpenAI/China AI Compatibility
**Source:** User brainstorm
**Idea:** Start with Claude/MCP but design for future compatibility with OpenAI, Chinese AI providers, etc.
**Evaluation:** Agree on the principle, disagree on the urgency. MCP is our protocol. If OpenAI adopts MCP (likely given industry direction), we get compatibility for free. Building a "provider abstraction layer" now is YAGNI — the MCP server doesn't call any AI API, it exposes tools. Any AI that speaks MCP can connect. If a provider uses a different protocol, we'd write an adapter at that point, not now.
**Status:** Accepted in principle. No code changes needed — architecture is already protocol-agnostic.

---

## #005 — Calendar Integration via Claude-as-Agent
**Source:** User brainstorm
**Idea:** Integrate Google Calendar / iOS Calendar, but through Claude reading calendar data and writing to Lorvex — not direct API integration in the app.
**Evaluation:** This is the right pattern. Claude-as-agent means Lorvex never needs OAuth flows, API keys, or calendar SDKs. Claude reads your calendar in conversation context and uses that to inform scheduling via MCP tools. Zero infrastructure cost. The constraint: Claude Desktop must have calendar access (via MCP or other means). We don't control that timeline.
**Status:** Accepted. No implementation needed on our side — this is a Claude Desktop capability dependency.

---

## #006 — Beyond Todo: Life Planning, Free-Form Writing, Budgeting
**Source:** User brainstorm
**Idea:** Lorvex should evolve beyond todo into a structured life memory system — free-form writing, goals, finance, health tracking.
**Evaluation:** The vision is compelling ("Your AI's structured memory. You own it.") but the execution risk is enormous. Each new module (free-form writing, finance, goals) is essentially a new product. Finance especially has regulatory and security implications. Recommendation: todo + goals + free-form writing for v2, finance deferred to v3+ at earliest. The reframing from "todo app" to "structured life memory" is a positioning insight, not a feature request. Started RFC-004 for the life data model.
**Status:** Partially accepted. Free-form writing + goals on roadmap (v2). Finance deferred. RFC-004 drafted.

---

## #007 — AI-Controlled Dashboard Layout
**Source:** User insight
**Idea:** Let AI decide how to arrange the dashboard — like a shopkeeper deciding how to arrange items on shelves. Claude should control which sections appear, in what order, and with what limits.
**Evaluation:** Brilliant and immediately actionable. This is a zero-infrastructure feature — we already have `set_preference` and `get_preference`. Just define a `dashboard_layout` preference schema and make TodayView read it dynamically. Implemented same day: 8 composable section types, DashboardSectionRenderer, "✦ AI layout" indicator, default fallback layout.
**Status:** Accepted and shipped.

---

## #008 — Privacy Granularity for Life Trajectory Data
**Source:** User brainstorm
**Idea:** Some users will be scared of AI knowing everything. Make AI data access configurable per module — full access, summary-only, write-only, title-only, sealed.
**Evaluation:** Important and nuanced. Three distinct concerns: privacy fear (emotional), data exposure risk (security), judgment avoidance (psychological). A write-only private writing pattern is especially clever — therapeutic for user, optionally useful for AI. Key design principle: per-module privacy levels with sensible defaults, NOT a wall of checkboxes. Also need a separate "behavioral patterns" toggle (whether Claude comments on procrastination/habits) distinct from data access.
**Status:** Accepted. Design approach documented. Implementation deferred to when life modules are built (v2).

Proposed privacy model:
| Module | Default | Options |
|--------|---------|---------|
| Todo | full | (core function, always full) |
| Journal | write_only | write_only, summary_only, full |
| Goals | full | summary_only, full |
| Finance | title_only | title_only, summary_only, full |
| Behavioral patterns | on | on, off |

---

## #009 — AI Time Estimation and Healthy Schedule Planning
**Source:** User brainstorm
**Idea:** AI should estimate task durations, plan healthy daily schedules (including rest), and give per-item suggestions/reminders.
**Evaluation:** Good features but most are already possible with zero new code. Duration estimation: Claude can set `estimated_minutes` via `update_task`. Schedule with rest: Claude can describe this in the daily briefing text. Per-item tips: Claude can write to `ai_notes`. The risk is brainstorming endlessly instead of shipping. Recommendation: update Claude Operating Model to teach Claude these behaviors, rather than building new infrastructure.
**Status:** Accepted via operating model update (no new code). Calendar-aware scheduling requires future calendar integration (#005).

---

## #010 — AI Memory / Summary Module
**Source:** User insight
**Idea:** AI can't read 100K entries every session. Design an LLM-friendly summary module — a "notebook" where Claude maintains its own compressed notes about the user, updated incrementally after each session rather than re-reading everything.
**Evaluation:** See detailed analysis below.
**Status:** Accepted and shipped. `memories` table + 3 MCP tools (read/write/delete) + session protocol in Claude Operating Model.

### Analysis of #010

This is architecturally significant. The problem is real: as Lorvex accumulates data (thousands of tasks, daily reviews, notes, financial records), Claude cannot read everything in a single context window. Current `get_overview` helps but is a fixed snapshot, not a learning memory.

**What this actually is:** A `claude_memory` system — structured, topic-based notes that Claude maintains about the user. Not raw data, but Claude's *understanding* of the data. Updated incrementally.

**Concrete design:**

```sql
CREATE TABLE memories (
  key       TEXT PRIMARY KEY,    -- topic key, e.g. 'user_patterns', 'list_summaries', 'energy_profile'
  content   TEXT NOT NULL,       -- Claude's notes (markdown or structured text)
  updated_at TEXT NOT NULL
);
```

MCP tools:
- `read_memory(key?)` — read one section or all sections
- `write_memory(key, content)` — create or overwrite a section

Claude's workflow:
1. Start of session: `read_memory()` to load compressed context
2. During session: operate normally, read detailed data as needed
3. End of session (or after significant operations): `write_memory()` to update relevant sections

**Example memory sections:**
- `user_profile` — working hours, energy patterns, preferences
- `list_summaries` — active lists, their status, blockers
- `behavioral_patterns` — deferral habits, completion rates, time estimation accuracy
- `recent_activity` — what happened in the last few sessions
- `pending_followups` — things Claude noticed but hasn't acted on yet

**Why this is better than just reading the DB:**
- 100K tasks compressed into a few KB of understanding
- Claude's observations are higher-level than raw data ("user consistently underestimates writing tasks by 2x")
- Persists across sessions without re-analysis
- Works within context window limits

**Risks:**
- Memory can become stale or wrong — needs a "refresh from source" mechanism
- Could create a feedback loop where Claude's biased notes reinforce themselves
- Privacy concern: these are AI's *opinions* about the user, not raw data

**Mitigation:** Memory should be visible to the user in the UI (read-only "What Claude knows about you" view). User can request a memory reset.

---

## #011 — Calendar Events as First-Class Entities
**Source:** User brainstorm
**Idea:** Support calendar-like events natively — meetings with time, recurrence (biweekly), timezone, location, attendees. Users should be able to tell Claude "I have a meeting next Friday 1-3pm" and have it stored and used for scheduling.
**Evaluation:** This is the right direction but needs careful scoping. There's a spectrum:

Option A: **Events as enriched tasks.** Add time_start/time_end, location, attendees fields to the existing task model. A "meeting" is just a task with a concrete time block. Pros: simple, no new tables. Cons: conflates tasks (things to do) with events (things that happen to you).

Option B: **Separate events table.** Dedicated `events` table with proper calendar semantics: start/end datetime, timezone, recurrence (iCalendar RRULE format), location, attendees, all-day flag. Tasks and events are related but distinct entities. Pros: clean model, can later sync with external calendars. Cons: more infrastructure.

**Recommendation:** Option B is the right long-term answer. Events and tasks have fundamentally different semantics:
- Tasks are *to-do items* you complete. They have status, urgency, deferral.
- Events are *time blocks* that exist on a timeline. They have start/end, recurrence, attendees.

The connection: tasks can be *scheduled into* time blocks, and events can *generate* tasks (e.g., "prepare for Friday meeting" created automatically before a recurring meeting).

For iCalendar recurrence support, use RRULE format — it's the industry standard and handles biweekly, monthly, etc. Timezone should be stored as IANA timezone string (e.g., "America/New_York"). This gives us future interop with Google Calendar, Apple Calendar exports.

**Key design insight:** We don't need to BUILD a calendar UI. Claude can manage events via MCP tools. The app shows a timeline/schedule view that includes both events and scheduled tasks — but the events are created and managed conversationally, not through a calendar widget.

**Status:** Accepted in principle. Data model design needed (add to RFC-004 or new RFC). Implementation deferred — todo features are the priority. Events table schema should be designed now to inform scheduling features.

Proposed schema sketch:
```sql
CREATE TABLE events (
  id            TEXT PRIMARY KEY,
  title         TEXT NOT NULL,
  description   TEXT,
  start_at      TEXT NOT NULL,     -- ISO 8601 with timezone
  end_at        TEXT NOT NULL,     -- ISO 8601 with timezone
  timezone      TEXT NOT NULL,     -- IANA timezone
  is_all_day    INTEGER NOT NULL DEFAULT 0,
  location      TEXT,
  attendees     TEXT,              -- JSON: [{name, email?}]
  recurrence    TEXT,              -- iCalendar RRULE string
  linked_task_ids TEXT,            -- JSON: string[]
  ai_notes      TEXT,
  source        TEXT,              -- 'manual' | 'claude' | 'calendar_sync'
  created_at    TEXT NOT NULL,
  updated_at    TEXT NOT NULL
);
```

---

## #012 — Continuous Reflection and Insight Accumulation
**Source:** User meta-instruction
**Idea:** Always reflect on both macro-level and micro-level design decisions. When new insights emerge during development, accumulate them rather than discarding them.
**Evaluation:** This is more of a working norm than a feature. Already partly addressed by the IDEAS_LOG itself and the "Working Norms" section in CLAUDE.md. The practical implication: after each implementation session, pause to consider whether any architectural patterns or user-facing behaviors suggest a design improvement worth documenting. This is already how good engineering teams work — the difference is making it explicit.
**Status:** Accepted as a working norm. Already operational.

---

## #013 — macOS Menu Bar Icon and Widgets
**Source:** User brainstorm
**Idea:** Add a menu bar (system tray) icon that, when clicked, shows a compact view of the most valuable information — today's focus tasks, upcoming deadlines, stats. Also consider macOS desktop widgets (WidgetKit) showing glanceable data.
**Evaluation:** Both are high-value, low-distraction access points that align perfectly with the "comfortable backend" philosophy. The menu bar popover is especially important — it's how users interact with the app without "opening" it. Should show:
- Today's top 3 focus tasks with checkboxes
- Quick capture field
- Next deadline
- One-line AI briefing

For widgets, WidgetKit requires a separate Swift extension target. Possible widgets:
- **Small:** Task count + next deadline
- **Medium:** Today's focus list (3-5 tasks)
- **Large:** Daily schedule with time blocks

**Implementation notes:** Tauri 2.x supports system tray via `tauri-plugin-system-tray`. The popover is a separate small window. WidgetKit requires native Swift code — it reads directly from SQLite, NOT through Tauri. This means the widget extension needs its own SQLite reader, but since the DB is just a file, this is straightforward.

**Status:** Accepted. Menu bar popover is Phase 2 (after core views are solid). macOS widgets are Phase 3 (requires native Swift extension).

---

## #014 — Asymmetric Configuration Surface: AI Gets More Knobs Than Humans
**Source:** User insight
**Idea:** In an AI-native app, the AI assistant should have access to more configuration options than what appears in the human settings UI. The human settings page should be deliberately simpler — some things are better left to AI and shouldn't clutter the human interface. But humans must still have a settings entry point for the things they care about.
**Evaluation:** This is already implicitly true in our architecture, but making it explicit is valuable. Today's reality:

**AI-only configuration (via MCP, no human UI):**
- `dashboard_layout` — which sections appear, in what order
- `ai_notes` on tasks — AI writes, human reads (not editable)
- `sort_order` on lists — AI arranges list display order, human sees the result

**Human-accessible settings (needs UI):**
- Working hours / energy preferences
- Default list for new tasks
- Notification preferences (when to interrupt)
- Privacy/data access levels (when life modules ship)
- Theme / appearance
- Export data

**Shared (both can set, human overrides AI):**
- `is_pinned` — human says "don't touch this task's priority"
- Task due dates — AI proposes, human can override
- List assignment — AI assigns, human can move

The design principle: **the human settings page is an "executive override" panel, not a full control panel.** It surfaces only the things where human judgment is required or where personal preference matters. Everything else, AI handles — and the human can see what AI decided (via the dashboard, AI memory view, changelog) without needing to configure it.

The risk: users feeling out of control. Mitigation: transparency (changelog, memory view, "AI layout" indicator) + override mechanisms (pin, manual edit) + trust built through accuracy over time.

**Status:** Accepted as a design principle. No immediate implementation needed — this is a philosophy that shapes future settings UI design. Added to Design Philosophy doc below.

---

## #015 — Distribution Strategy: Direct Tauri Releases
**Source:** User brainstorm
**Idea:** Start as a GitHub open source project with downloadable packages. Each release must be installable and updatable while preserving all local data.
**Evaluation:** This is the right sequence. Analysis of each component:

**Packaging:** Tauri 2.x produces `.dmg` for macOS, `.msi`/`.exe` for Windows, `.AppImage`/`.deb` for Linux. GitHub Releases is the natural distribution channel for v1. Homebrew cask formula can be added for macOS convenience (`brew install --cask lorvex`). The Tauri updater plugin (`@tauri-apps/plugin-updater`) supports auto-updates from GitHub Releases with delta updates — this is the right approach.

**Data preservation on update:** Non-issue architecturally. The SQLite DB lives at `~/Library/Application Support/Lorvex/db.sqlite` (macOS) which is outside the app bundle. Tauri updates replace the app binary but never touch Application Support. The DB migration system (`001_initial_schema.sql` with `IF NOT EXISTS`) already handles schema evolution safely. Future migrations should follow the same pattern (numbered, idempotent, additive).

**Sync:** The Tauri line must not depend on iCloud or CloudKit. Multi-device sync for Windows/Linux/Android should use a provider-neutral backend when that product work exists. For now, the DB stays local and export/import remains the supported backup and transfer path.

**Status:** Accepted for Tauri direct distribution. App Store and iCloud/CloudKit paths are retired from the Tauri line.

---

## #016 — Claude-Guided Interactive Setup
**Source:** User brainstorm
**Idea:** Provide a Claude-accessible MCP action (e.g., `setup_wizard` or `initial_setup`) that enables Claude to guide the user through first-run configuration interactively. Instead of a traditional onboarding UI, Claude asks questions: nickname, preferred language, working hours, energy patterns, what kind of work the user does, existing commitments.
**Evaluation:** This is a genuinely novel onboarding pattern that plays to the AI-native paradigm. Instead of a static form, Claude learns about the user through conversation and writes the configuration via MCP. Analysis:

**What Claude should configure during setup:**
- User display name / nickname (stored in `preferences`)
- Preferred language for AI communication
- Working hours (start/end times)
- Energy pattern (when user is most focused vs drained)
- Key project areas (creates initial lists)
- Immediate commitments or deadlines (creates initial tasks)
- Notification preferences (how much Claude should surface)
- Any existing task system to migrate from (context for Claude's approach)

**Implementation:** No new infrastructure needed. The `set_preference` and `create_list`/`create_task` MCP tools already exist. What's needed is:
1. A `get_setup_status` MCP tool that tells Claude whether setup has been completed
2. A `complete_setup` MCP tool that marks setup as done (sets a preference flag)
3. Instructions in the Claude Operating Model for how to conduct the setup conversation
4. The app showing a first-run state when setup hasn't been completed (empty dashboard with "Chat with Claude to get started" prompt)

**Why this is better than a traditional onboarding wizard:** Traditional onboarding is a fixed sequence of screens. Claude's setup is adaptive — if the user mentions they're a student, Claude asks about course deadlines. If they're a project manager, Claude asks about team commitments. The setup experience is personalized before the app is even configured. This is the "chief of staff" metaphor in action from the very first interaction.

**Risk:** Cold start problem — the user needs Claude Desktop + MCP configured before they can even set up Lorvex. Mitigation: clear installation instructions, and the app should be usable (with sensible defaults) even without completing the Claude setup.

**Status:** Accepted and shipped. `get_setup_status`, `complete_setup` MCP tools added to preferences.ts. `is_setup_complete` Rust IPC command added. First-run welcome state in TodayView showing 3-step getting started guide.

---

## #017 — Performance, Launch on Startup, and App Polish
**Source:** User brainstorm
**Idea:** Focus on performance optimization. Enable launch-on-login (auto-start). Consider broader polish items for a production-ready app.
**Evaluation:** Multiple distinct items here:

**Launch on startup:** Tauri 2.x supports this via `tauri-plugin-autostart`. This adds the app to macOS Login Items, Windows Startup, or Linux autostart. Important for the "comfortable backend" paradigm — Lorvex should always be running in the background. Implementation: add the plugin dependency and a user preference toggle in Settings.

**Performance:** Several considerations:
- **SQLite**: Already using WAL mode (good). Could add connection pooling, but single-connection-with-mutex is fine for a single-user desktop app. Index coverage looks complete.
- **React bundle size**: Tauri uses a webview, so bundle size matters less than for web apps. But tree-shaking and code splitting are still good practices.
- **TanStack Query polling**: 2-second default polling interval means background DB queries every 2s. This is fine for SQLite (sub-ms queries) but could be optimized for views that are rarely active.
- **Memory**: React + webview overhead is fixed. The main variable is how many tasks are loaded in memory. Current LIMIT 200 on `get_all_tasks` is a good safeguard.

**Broader polish for production:**
- Error boundaries in React (crash one view, not the whole app)
- Accessibility: keyboard navigation, screen reader labels
- Window state persistence (remember size/position between launches)
- Graceful handling of DB corruption
- Crash reporting (opt-in)

**Status:** Launch-on-startup accepted for immediate implementation. Performance is already reasonable; optimizations are maintenance items. Polish items tracked for pre-release.

---

## #018 — Open Source Preparation
**Source:** User brainstorm
**Idea:** Prepare the repository for public GitHub open source release. Needs proper licensing, CI/CD, contributing guidelines, and documentation.
**Evaluation:** Several deliverables needed:

1. **LICENSE**: MIT or Apache-2.0 for the core (MCP server, shared types). The app could be same or more restrictive (BSL, SSPL) if commercial protection is desired. Recommendation: MIT for everything in v1 to maximize adoption and trust.
2. **CONTRIBUTING.md**: Contribution guidelines, development setup, PR process.
3. **GitHub Actions CI**: Automated builds for macOS/Windows/Linux, TypeScript type checking, Rust compilation. Tauri has a well-documented GitHub Actions workflow.
4. **README.md**: Compelling project description, screenshots, installation instructions, MCP setup guide.
5. **.github/**: Issue templates, PR templates, FUNDING.yml.
6. **CHANGELOG.md**: User-facing changelog for each release.
7. **Release workflow**: GitHub Actions to build and publish releases with auto-updater support.

**Status:** Shipped. LICENSE, README, CONTRIBUTING, GETTING_STARTED, CI workflow (`.github/workflows/ci.yml`), and release workflow (`.github/workflows/release.yml`) are all in place.

---

## #019 — License Choice: AGPL-3.0
**Source:** User discussion
**Idea:** Choose an open source license that builds personal influence while preventing commercial repackaging of the work.
**Superseded:** project license switched to Apache-2.0.
**Options considered:**

1. **MIT**: Maximum adoption, zero protection. Anyone can repackage and sell.
2. **AGPL-3.0**: OSI-approved open source. Strong copyleft — anyone distributing modifications (including network services) must open-source under AGPL. Used by Grafana, Mastodon, Nextcloud, Signal.
3. **BSL 1.1**: Source-available, not open source (OSI does not recognize). Restricts production use. Used by Sentry, CockroachDB, HashiCorp.
4. **PolyForm Noncommercial**: Explicit non-commercial. Clear intent but low community adoption.

**Decision: AGPL-3.0.** Key reasoning:
- Lorvex has an MCP server component (a network service), so AGPL's network clause is directly relevant — unlike a purely local app where it would be weaker.
- AGPL is real open source (OSI-approved), which matters for credibility and community building.
- Commercial repackaging is economically unviable under AGPL because the repackager must also release their source.
- Compatible with dual-licensing if needed in the future.
- Well-proven license for open infrastructure projects (Grafana, Mastodon, Plausible).

**Status:** Historical decision; later superseded by Apache-2.0.

---

## #020 — Shopping Lists, Gift Planning, and Everyday Life Data
**Source:** User brainstorm
**Idea:** Support everyday planning beyond work tasks — shopping lists (Target runs, Costco runs, must-buy vs optional items), gift ideas for people, and similar personal life data.

**Evaluation:** This is a great validation of the "structured life memory" vision. The question is: should this be a separate module or can the existing task system handle it?

**Analysis:**

The current task system can already handle most of this with good AI orchestration:
1. **Shopping lists**: A list called "Target" or "Costco" with tasks like "Buy paper towels" works today. Tags could distinguish `must-buy` vs `optional`. Claude can manage this naturally via MCP — "add to my Costco list: almond milk, must-buy."
2. **Gift ideas**: A list called "Gift Ideas" or tagged per person. Claude can maintain `ai_notes` with context like "she mentioned wanting this on Feb 14."
3. **Recurring needs**: Tasks with `recurrence` field (already in schema) — "Buy laundry detergent" that reappears when completed.

What the current system does NOT handle well:
- **Quantity/structured fields**: "Buy 2 gallons of milk" is just a title string today. No structured quantity, price, or category fields.
- **Store-specific grouping at checkout**: When you're AT Target, you want a filtered view of just Target items, ideally grouped by aisle/category.
- **Shared lists**: Shopping lists are often shared with a partner. Lorvex is single-user today.

**Recommendation:** Do NOT build a separate shopping module. Instead:
1. Use the existing list + task system. Claude is smart enough to organize shopping items into per-store lists with appropriate tags.
2. Add a `context_ref` convention: tasks with `context_ref = "store:target"` or `context_ref = "person:friend"` let Claude filter contextually.
3. The `context_ref` field already exists in the schema — it was designed exactly for this kind of contextual grouping.
4. If structured shopping features are needed later (quantities, categories, shared lists), that becomes a Phase 2 module alongside Journal and Goals.

The key insight: Lorvex's value is that Claude handles the organization. The user says "I need to buy paper towels at Costco, and also get a birthday gift for Sarah, maybe that book she mentioned." Claude creates two tasks in the right lists with the right context. No special UI needed.

**Status:** Accepted as a natural use case for the existing system. No new module needed — Claude's MCP orchestration handles it. Document `context_ref` conventions in the operating model.

---

## #021 — Dark/Light Mode with System Auto-Follow
**Source:** User brainstorm
**Idea:** Support dark mode, light mode, and automatic system-following theme switching.

**Evaluation:** Essential UX feature for a modern desktop app. The current app is dark-only (the Tailwind color tokens in `tailwind.config.js` use dark palette values). Implementation plan:

1. **Tailwind dark mode**: Use `darkMode: 'class'` strategy. Define both light and dark values for all semantic tokens.
2. **System detection**: Use `window.matchMedia('(prefers-color-scheme: dark)')` to detect system preference.
3. **Three modes**: "Light", "Dark", "System" (auto-follow). Store choice in preferences.
4. **CSS variables approach**: The current design uses CSS custom properties for colors (defined in `index.css`). Adding a light theme means defining a second set of variable values under a `.light` class or `:root` without `.dark`.

**Technical note:** The existing color token system (`surface-0`, `surface-1`, `text-primary`, etc.) is already semantic — it doesn't hardcode "dark gray" or "white." This means adding a light theme is mostly about defining new RGB values for the same token names, not restructuring components.

**Status:** Shipped. CSS variables defined for dark/light themes. ThemeProvider with system auto-follow. Theme picker in Settings.

---

## #022 — AI-Driven Onboarding: Claude IS the Tutorial
**Source:** User insight
**Idea:** Instead of writing static tutorials, getting-started guides, and example walkthroughs, leverage Claude as the onboarding agent. Claude detects new users, walks them through setup conversationally, explains features in context as they become relevant, and can generate visual artifacts (diagrams, interactive HTML) to illustrate concepts. "You ARE the tutorial. Don't point users to docs."
**Evaluation:** This is the logical extension of the AI-native philosophy. If Claude is the primary interface, Claude should also be the primary teacher. Benefits:
- No static docs to maintain (they rot)
- Onboarding adapts to each user (student vs PM vs freelancer)
- Features are explained when relevant, not dumped upfront
- Claude can generate visual explanations using artifacts

**Implementation:** Added `get_guide` MCP tool that returns contextual guidance based on current app state. Auto-detects what the user needs (new user → getting started, no current focus → current focus guidance, inbox full → triage). The README should be minimal: install → connect MCP → talk to Claude.

**Status:** Shipped. `get_guide` tool with 10 topic areas and auto-detection.

---

## #023 — Timezone Awareness
**Source:** User insight
**Idea:** Auto-detect the user's timezone and handle timezone-related scheduling correctly. Consider: some things are timezone-relative (meetings at 3pm local time), some are timezone-absolute (a global deadline at a specific UTC moment). Allow Claude to specify which interpretation a task uses.
**Evaluation:** Important for correctness. The browser gives us `Intl.DateTimeFormat().resolvedOptions().timeZone`. Key design decisions:
- Store detected timezone as a preference on first launch
- Due dates/times in the DB should be timezone-aware or stored with context
- When user travels (timezone changes), Claude should detect and ask whether to adjust
- Working hours are always local time (relative to current timezone)
- Some deadlines are absolute (conference submission at midnight UTC)

**Status:** Accepted. Detect and store timezone on launch. Full timezone-aware scheduling deferred to when time-blocking features ship.

---

## #024 — AI-Expanded Configuration Surface
**Source:** User insight
**Idea:** Since AI handles configuration via MCP, we can expose far more settings than a traditional app — the human never has to navigate a complex settings menu. Claude configures things conversationally. "I prefer mornings for deep work" → Claude sets `energy_peak.morning = true` and adjusts scheduling.
**Evaluation:** Already implicitly true (see #014 Asymmetric Configuration), but the insight goes further: the *number* of configurable things can be much larger than traditional apps because the UX cost of adding a setting is near-zero (it's just another preference key Claude knows about). Traditional apps must balance "more options" vs "settings UI complexity." We don't have that tradeoff.

**Status:** Accepted as a design principle. Continue adding preference keys freely without worrying about settings UI bloat.

---

## #025 — Private-First Development Model
**Source:** User decision
**Idea:** Keep the repo private initially. Don't open-source the code yet. Allow others to submit ideas/suggestions but not code PRs. The coding agent workflow means PRs are low-value — ideas are the valuable input, and the agent implements them.
**Evaluation:** This makes sense for the current phase:
- The agent workflow means external PRs add review overhead without proportional value
- Keeping code private preserves creative control during rapid iteration
- Ideas/suggestions can flow through GitHub Discussions or Issues
- Open sourcing can happen later when the product is stable

**Status:** Accepted. Private repo with idea-only contributions for now.

---

## #026 — Retired Mac App Store Sandbox Evaluation
**Source:** User observation
**Idea:** Mac App Store sandbox restrictions may conflict with the shared-SQLite architecture between the Tauri app and the MCP server.
**Evaluation:** Historical evaluation only. The sandbox gives the app its own container directory, while an MCP host process launched by an external assistant may run outside that sandbox. This confirmed that the old Tauri App Store path was the wrong ownership boundary.

**Status:** Retired for Tauri. Direct distribution is the Tauri path; Apple App Store work belongs to the Swift app under `apps/apple`.

---

## #027 — Inbox Behavior: Intent-Based Routing *[SUPERSEDED — inbox removed]*
**Source:** User insight
**Idea:** The "Inbox as intent verification" pattern creates friction when the user explicitly asks Claude to create tasks. If you ask Claude to "create 100 tasks for my project," they should go directly to `open`, not require approval.
**Evaluation:** Correct. The original design assumed all AI-created tasks are proposals. But there's a clear distinction:
- **Explicit request** (user asks Claude to create tasks) → direct to `open`
- **Proactive suggestion** (Claude identifies tasks the user didn't ask for) → `inbox` for review
- **Ambiguous intent** (low certainty) → `inbox`

This is already supported by the schema — `create_task` has both `status` and `to_inbox` fields. The change is behavioral: update tool descriptions to guide Claude on when to use each. Also add a user preference `ai_default_to_inbox` for users who want all AI tasks to go through review.

**Status:** Shipped. Updated `create_task` and `batch_create_tasks` tool descriptions with intent-based routing guidance.

---

## #028 — Task Dependencies + Kanban View
**Source:** User brainstorm
**Idea:** Leverage the existing `depends_on`/`blocks` fields to show dependency visualization, possibly a Kanban board.
**Evaluation:** The action space already supports dependencies — `create_task` and `update_task` both handle `depends_on` and `blocks` arrays with bidirectional sync and urgency recalculation.

For visualization, two approaches:
1. **Lightweight (v1):** Show dependency chain in TaskDetail panel — "Blocked by: [task name]" / "Blocks: [task name]" with clickable links. Simple, low effort, high utility.
2. **Full Kanban (v2):** Board view with columns (e.g., Backlog → In Progress → Done) and dependency lines between cards. Significant UI effort but visually powerful for project planning.

Recommendation: Start with (1) in TaskDetail. The Kanban board is a v2 feature that pairs well with project/list-level views.

**Status:** Accepted. Dependency display in TaskDetail for v1. Kanban board deferred to v2.

---

## #029 — AI-Driven Smart Reminders
**Source:** User insight
**Idea:** Support notifications/reminders where Claude sets the reminder strategy per task. Different task types get different reminder patterns — e.g., a girlfriend's birthday gets reminded days in advance with gift suggestions, a meeting gets reminded 15 minutes before, a weekly report gets reminded the morning of.
**Evaluation:** The schema already has `reminder_at` (ISO 8601 datetime). But the current design is "one reminder per task." A smarter approach:

**What Claude should configure:**
- `reminder_at`: the primary reminder time
- `ai_notes`: include reminder context ("Buy flowers + dinner reservation")
- Preference key `reminder_defaults`: per-context reminder lead times
  - `birthday` → remind 7 days and 1 day before
  - `meeting` → remind 15 min before
  - `deadline` → remind 1 day and 2 hours before
  - `recurring_chore` → remind morning of

**What the app needs:**
1. A notification daemon (Tauri sidecar or background process) that polls `reminder_at` and fires native notifications
2. Support for multiple reminders per task (schema extension: `reminders` JSON array instead of single `reminder_at`)
3. Claude sets reminders contextually during task creation — no human configuration needed
4. Notification content includes Claude's `ai_notes` (not just the task title)

**The AI-native insight:** Traditional apps have a fixed reminder dropdown (5 min, 15 min, 1 hour, 1 day). We don't need that UI. Claude decides the right reminder strategy based on task context, and the user can override via conversation ("remind me earlier about that").

**Status:** Accepted. Schema supports single reminder. Multi-reminder and notification daemon are v1.5 features.

---

## #030 — Habit Tracking / Streak Reminders
**Source:** User insight
**Idea:** Support habit formation through recurring tasks with streak tracking and gentle reminders. E.g., "Meditate for 10 minutes" every morning, with a streak counter ("7 days in a row!") and a nudge if you miss.
**Evaluation:** This fits naturally within the existing system:

**Already supported:**
- `recurrence` field on tasks (JSON rule: `{"freq":"daily","byday":["MO","TU","WE","TH","FR"]}`)
- Tasks auto-recreate on completion (Claude can manage this via MCP)

**What to add:**
1. **Streak tracking:** A `streak_count` field or `ai_notes` tracking consecutive completions. Claude can compute this by querying completed instances.
2. **Habit reminders:** These are time-sensitive — "meditate at 7am" needs a push notification at 7am, not just a task in the list. Ties into #029's notification daemon.
3. **Streak visualization:** A small flame/streak icon on habit tasks in the UI. Simple but motivating.
4. **Break detection:** Claude notices when you miss a day and adjusts — "You missed meditation yesterday. Want to restart or adjust the schedule?"

**The AI-native approach:** Traditional habit trackers are manual check-in UIs. Ours is Claude-managed:
- Claude creates the recurring task based on conversation ("I want to start meditating")
- Claude sets the reminder time based on your schedule
- Claude tracks the streak and adjusts the approach if you're struggling
- Claude celebrates milestones ("21 days in a row — habit research says this is the formation threshold!")

**Status:** Accepted as a natural extension of the recurring task system. Detailed design deferred to when notification daemon ships (#029).

---

## #031 — Plugin System via MCP
**Source:** User brainstorm
**Idea:** Make features modular through a plugin system. E.g., finance/accounting as a plugin, habit tracking as a plugin. Users choose which features to include.
**Evaluation:** Lorvex's architecture naturally supports this because the intelligence layer IS MCP:

**How it works:**
- Each "plugin" is an additional MCP server that connects to the same SQLite DB
- A "Finance" plugin adds `create_expense`, `get_budget_summary`, `set_budget` tools
- A "Journal" plugin adds `write_entry`, `search_entries`, `get_mood_trend` tools
- Claude discovers available tools automatically — no plugin configuration UI needed
- Each plugin gets its own DB tables (prefixed: `finance_*`, `journal_*`)

**Benefits:**
- No marketplace needed initially — install by adding MCP server config
- Core stays lightweight; power users add what they need
- Third-party plugins possible without touching core code
- Plugin authors write MCP tools, not UI — lower barrier

**Challenges:**
- UI components: each plugin may need its own view/section on the dashboard
- Data isolation: plugins sharing a DB need careful schema namespacing
- Discovery: users need to find and install plugins

**Status:** Accepted as v2+ architecture direction. Core task system is the foundation; plugins extend it.

---

## #032 — Persistent AI Agents (OpenClaw) and Lorvex's Position
**Source:** User strategic insight
**Context:** OpenClaw (234K GitHub stars, OpenAI-backed) is an always-on AI agent daemon that runs continuously on your machine. It can execute cron jobs, manage workflows across apps, and act proactively without user prompting.

**Strategic analysis for Lorvex:**

**Lorvex is the structured data layer that agents need.** Without structured data, persistent agents are just chatbots running in loops. Lorvex provides:
1. A task/project/life schema that gives agents actionable structure
2. An MCP interface that any agent platform (Claude Desktop, OpenClaw, future agents) can connect to
3. A human dashboard for oversight of what agents are doing
4. A trust infrastructure (inbox, changelog, AI memory) for human-AI collaboration

**Positioning in an agent world:**
- OpenClaw = execution engine (the "always-on brain")
- Claude Desktop = conversation & planning interface
- **Lorvex = structured life memory** (the "filing cabinet" all agents read/write)
- These are complementary, not competitive

**Design implications:**
1. **Multi-agent support:** Lorvex should support multiple agents writing to it. The `initiated_by` field in `ai_changelog` already tracks which agent made changes. Extend this to track agent identity.
2. **Agent-agnostic MCP:** Keep MCP tools generic (not Claude-specific). Any MCP-compatible agent should work.
3. **Always-on reminders:** An OpenClaw agent could replace the polling-based reminder system with proactive, scheduled notifications.
4. **The dashboard matters more, not less:** With multiple agents operating, the human needs a single place to see what's happening. Lorvex's UI IS that place.

**Tagline evolution:** "Your AI's structured memory" → "The structured memory layer for your AI agents"

**Status:** Accepted as strategic direction. No immediate implementation changes — the MCP-first architecture already supports this. Document agent-agnostic design as a principle.

---

## #033 — Daily Review / Structured Life Ledger
**Source:** User insight
**Idea:** At the end of each day, you tell Claude your daily summary and reflections. Claude stores it in a structured form that links back to actual tasks, learning plans, and events from that day — creating a coherent record over time, not just a task list.

**Why this is different from the generic free-form writing module (#006):**
The free-form writing module (#006) is unstructured writing. This is a **structured daily review** with *relationships*: what was planned vs what happened, which tasks were completed or blocked, mood/energy, what was learned. The value is in those links and the longitudinal patterns they enable.

**The natural interaction:**
User doesn't open a review app. They just talk to Claude at day-end. Claude already knows the day's current focus (from `get_current_focus`), so it can conduct a diff-aware review — "you planned X, Y, Z; what actually happened?" Claude extracts structure from conversation, links to known tasks, and writes it. The app shows the record.

**Proposed data model:**
```sql
CREATE TABLE daily_reviews (
  date             TEXT PRIMARY KEY,  -- YYYY-MM-DD
  summary          TEXT NOT NULL,     -- user's reflection, written by Claude from conversation
  mood             INTEGER,           -- 1-5, optional
  energy_level     INTEGER,           -- 1-5, optional
  linked_task_ids  TEXT,              -- JSON string[] — tasks explicitly mentioned
  linked_list_ids  TEXT,              -- JSON string[] — projects/lists mentioned
  wins             TEXT,              -- what went well (Claude extracts)
  blockers         TEXT,              -- what got in the way
  learnings        TEXT,              -- explicit learnings or insights
  ai_synthesis     TEXT,              -- Claude's pattern observations across recent reviews
  created_at       TEXT NOT NULL,
  updated_at       TEXT NOT NULL
);
```

**Proposed MCP tools:**
- `add_daily_review(date, summary, mood?, energy_level?, linked_task_ids?)` — Claude writes after day-end conversation
- `get_daily_review(date?)` — fetch a specific day (defaults to today)
- `get_review_history(since?, limit?)` — recent reviews for context loading
- `get_review_insights()` — Claude reads patterns: energy trends, plan vs actual, recurring blockers

**Why the linkage matters:**
- `linked_task_ids` lets future queries like "which tasks caused the most friction?" surface real answers, not just AI guesses
- `linked_list_ids` lets project-level health be tracked over time ("every time I work on Project X, energy drops")
- `wins` / `blockers` / `learnings` as separate fields let Claude query them independently — "what have you learned in the last 30 days?"

**Relationship to existing modules:**
- Extends `memories` concept (Claude's understanding of you) with timestamped, linkable entries
- Feeds into weekly review (`WeeklyReviewView`) — reviews from the past 7 days inform the weekly summary
- Complements the free-form writing module (#006) — daily reviews are structured/operational, free-form writing is unstructured/personal

**Critical questions to resolve before implementation:**
1. **Privacy**: daily reviews are highly personal. Default access: `summary_only` for AI reads unless user grants `full`?
2. **Granularity**: one review per day, or per-session? (User may talk to Claude multiple times per day)
3. **Correction**: user should be able to amend a review after the fact ("I forgot to mention I finished X")
4. **AI synthesis cadence**: Claude should periodically re-synthesize patterns (weekly? after every 7 entries?), not on every write

**Evaluation:**
Compelling and well-differentiated. No other tool does this — AI-mediated structured daily review linked to actual tasks is genuinely novel. The implementation is lightweight (one new table, 3-4 MCP tools). The UX is zero-friction for the user because Claude conducts the review conversationally.

The risk is scope creep into therapy/journaling territory. Keep it operationally focused: plans vs actuals, energy, blockers, learnings. Not a diary.

**Status:** Accepted. Schema designed. Implementation deferred to Milestone 3 alongside the free-form writing module — they share privacy and schema concerns that should be designed together.


---

## #034 — Habit Tracking Integrated with Daily Review
**Source:** User insight
**Idea:** During the daily review, Claude could check in on habit completion — "did you take your vitamins, exercise, study vocabulary today?" — as a habit check-in woven into the conversational review process instead of a separate UI screen.

**Why this fits Lorvex's model:**
Traditional apps treat habit tracking as a standalone module: a screen with checkboxes you tap manually. Lorvex's model is different — Claude conducts the review conversationally, so habit check-in happens naturally in that context. The user doesn't tap checkboxes; they mention "I didn't exercise today" and Claude records it. Zero additional friction for the user.

**Design options:**

Option A: **Habits as a lightweight preference**. Store a `habits` preference as a JSON array of habit names (e.g., `["vitamins", "exercise", "vocabulary"]`). During daily review, Claude reads the preference and asks about each one. Habit completions recorded as fields in `daily_reviews.habits_completed` (JSON string[], the ones done).

Option B: **Habits as a first-class table**. `habits` table with name, frequency (daily/weekly), streak tracking, history. More powerful but significantly more infrastructure. Supports streaks, skip reasons, long-term stats.

Option C: **Habits as a tag on tasks**. Recurring tasks with tag `#habit`. When you complete them, they're just task completions. History is in the task completion log. Simple, zero new infrastructure, but no streak tracking.

**Critical evaluation:**
Option C (habits as recurring tasks) is the most elegant from an infrastructure standpoint — it's "free" since recurring tasks already exist. The downside is that habits have different semantics from tasks: you don't "defer" a habit, you track its streak. Mixing them into the task model dilutes both.

Option A (preference + daily_review fields) is the right MVP. It's:
- Zero new tables (add a `habits_completed` field to `daily_reviews`)
- Claude reads habits from preferences and checks in during review
- History is in `daily_reviews.habits_completed` — queryable
- No streak UI needed initially (Claude can compute and report streaks in conversation)

Option B is v2 — when users want a visual streak board, dedicated habit analytics, skip reasons.

**Proposed minimal implementation (v1 — MVP):**
1. Add `habits_completed` (JSON string[], habits done) and `habits_skipped` (JSON string[], with optional reasons) fields to `daily_reviews` table
2. `add_daily_review` already upserts — just add these two fields to the schema
3. Claude reads `habits` preference (user sets this via MCP) and includes check-in in daily review conversation
4. In `DailyReviewView`, show a simple habits row if `habits_completed` is present

**Habit check-in UX (conversational):**
> Claude: "Quick habit check — vitamins, exercise, vocabulary. How'd you do today?"
> User: "Vitamins yes, skipped exercise, did vocab."
> Claude: calls `add_daily_review` with `habits_completed: ["vitamins", "vocabulary"]`, `habits_skipped: ["exercise"]`

The UI shows these as simple dots/pills in the daily review card. Streaks are computed by Claude on demand.

**Status:** Accepted as MVP. Schema extension is trivial (two new fields). Implementation target: Milestone 2, after daily review ships.

---

## #035 — Generative UI Endgame: Database-First Architecture
**Source:** User insight
**Idea:** "The future is generative UI — everyone will get on-the-fly custom interfaces. So the app should primarily be a great database and AI interface, not a great UI. Users might choose to interact entirely through Claude without ever opening the app."
**Evaluation:** This is the correct long-term bet. The value of Lorvex isn't the sidebar or the task cards — it's the structured data, the life trajectory, and the MCP contract. The UI is a convenience layer, not the product. This aligns with our "comfortable backend" design philosophy: the app succeeds when it's opened rarely. The MCP server is the primary interface; the app is the dashboard.

Implications:
1. **MCP completeness is more important than UI completeness.** Every feature must be Claude-accessible first, UI second.
2. **Schema clarity matters more than UI polish.** Data portability and a canonical, trustworthy model are product features.
3. **The DB is the moat.** The longer a user's history lives in Lorvex (tasks, daily reviews, habits, goals), the more irreplaceable it becomes — independent of which AI or UI layer sits on top.
4. **"Headless mode" is valid.** A user who never opens the app but uses Lorvex exclusively through Claude chat is a first-class use case.

**Status:** Accepted as core philosophy. Already reflected in design: MCP-first, UI as read layer. Worth surfacing more explicitly in README and VISION.md.

---

## #036 — Local-First + Privacy as a Product Pillar
**Source:** User insight
**Idea:** "Everything is local — privacy + security. But still powerful and smooth. This is a rare combination."
**Evaluation:** Correct and underappreciated. Most AI-powered productivity tools are cloud-dependent by design (the AI needs to call an API, the data lives on a server). Lorvex's architecture inverts this: Claude Desktop runs locally, connects to a local MCP server, reads/writes a local SQLite DB. Nothing leaves the machine.

This matters for several user segments:
- Privacy-conscious users who won't put personal planning data in the cloud
- Enterprises with data sovereignty requirements
- Users in regulated industries (healthcare, legal, finance) who can't use cloud AI on sensitive tasks
- Users in countries with restrictive data laws

The local-first constraint is not a limitation — it's a differentiator. It's worth making explicit in positioning: "Your AI assistant that knows you. Runs entirely on your machine."

The tradeoff: no sync across devices, no web app. These are acceptable for v1. Multi-device sync could be added in v2 via encrypted cloud backup of the SQLite file (user controls the encryption key).

**Status:** Accepted as product pillar. Add to README positioning. Sync deferred to v2.

---

## #037 — Issues as Contributions: Agent-Mediated Open Source
**Source:** User insight
**Idea:** In a project where coding agents can implement features from text descriptions, filing a well-written GitHub Issue is functionally equivalent to submitting a PR. The contribution barrier drops to "can you describe the problem/feature clearly?" rather than "can you write Rust/TypeScript?" Community members should be explicitly welcomed and credited for text-only contributions.

**Evaluation:** This is mostly a framing insight, not a technical design change. The infrastructure already exists:

- GitHub Issues already supports structured templates (bug report, feature request)
- Coding agents (Claude Code, Codex, etc.) already read issues via `gh` CLI
- The natural workflow is: community files issue → maintainer triages → agent implements → PR reviewed → merged
- `Closes #123` in PR descriptions already links issues to implementations

What's genuinely new is the **explicit acknowledgment and attribution**. In traditional open source, the code author gets credit. Here, the *idea author* is the creative contributor — the agent is just the translator. This should be reflected in:

1. **CONTRIBUTING.md** — Add a section explicitly welcoming text-only contributions (bug descriptions, feature ideas, UX feedback). Make clear that a well-written issue is a valued contribution.
2. **Attribution convention** — PRs generated from community issues should include `Suggested-by: @username` in the commit message or PR body, in addition to the standard `Closes #123`.
3. **Issue templates** — Ensure templates are structured for "agent readability": clear acceptance criteria, reproduction steps, scope constraints. This makes issues more actionable for both human and agent implementers.
4. **Issue labels** — `agent-ready` (clear enough for direct implementation) vs `needs-design` (requires architectural discussion first).

What we should NOT build:
- A separate "task board" — GitHub Issues IS the task board. Adding another layer creates the same drift problem we just fixed in ROADMAP.md.
- Complex triage automation — premature for a project at this stage.

The deeper philosophical point: this aligns perfectly with Lorvex's core thesis. Lorvex says "AI is the operator, human provides intent." Community contributions follow the same pattern — human provides intent (issue), AI operates (agent implements). The project's own development process mirrors its product philosophy.

**Status:** Accepted. Action items: (1) Update CONTRIBUTING.md to welcome text-only contributions. (2) Add `Suggested-by:` attribution convention. (3) Add `agent-ready` / `needs-design` labels. No new technical design needed — GitHub Issues + existing agent tooling covers it.

---

## #038 — AI/Tool Co-Evolution Loop as a Core Development Engine
**Source:** User insight
**Idea:** Lorvex's MCP tools and the AI assistants that use them should continuously co-evolve. The AI is the highest-frequency operator; when it hits missing tools, tool friction, or bugs, that signal should feed directly into development through GitHub Issues. After fixes ship, the AI's operational quality improves, which produces better future signal.

**Evaluation:** This is a strong and practical insight. It is not "nice-to-have feedback collection"; it is an iterative quality loop:

1. Assistant runs real workflows against MCP tools
2. Assistant emits structured friction feedback
3. Developer translates feedback into design/code changes
4. Assistant re-runs workflows on improved tools
5. Tooling quality and AI execution quality improve together

Why this is especially valid for Lorvex:
- MCP tools are the primary write path, so assistant-side friction is first-order product friction.
- Assistants observe edge cases faster than manual QA because they execute high-volume, real usage flows.
- Lorvex uses changelog history plus GitHub Issues / PR planning context to operationalize the loop.

Key risks if done carelessly:
- Overfitting to one assistant's behavior (Claude-only or Codex-only assumptions).
- Noise/false positives from low-quality feedback.
- Local optimization (patching symptoms) without addressing schema/tool design root causes.

Guardrails:
1. Require concrete evidence in GitHub Issues (tool call, params, observed error/result).
2. Keep product triage in GitHub labels/templates rather than app-local feedback categories.
3. Validate fixes across at least two assistant clients when possible.
4. Route repeated feedback to architecture-level fixes, not only one-off patches.

This insight also reinforces product positioning: Lorvex is not a static todo app. It is an AI-operated system whose operator layer and tool layer improve each other over time.

**Status:** Accepted as a core development principle. Keep this loop explicit in roadmap/operating docs and treat recurring AI feedback as roadmap input, not support noise.

---

## #039 — Assistant-Driven UI Control (Jarvis Interaction Layer)
**Source:** User insight
**Idea:** AI assistants should not only mutate data via MCP tools, but also directly steer the app UI when useful: enter focus mode, jump to a specific task, switch tabs/views. The target interaction is "talk to Jarvis" with minimal manual clicking.

**Evaluation:** Strong direction with immediate practical value. Today, assistants can create/update/schedule tasks, but the human still performs many "navigation clicks" manually. Adding a narrow UI-control bridge can reduce interaction friction without redesigning the app architecture.

Recommended scope (MVP):
1. `control_app_ui` MCP tool that writes a structured UI command into `preferences`.
2. App-side command consumer loop that polls and executes commands.
3. Supported actions: `enter_focus_mode`, `exit_focus_mode`, `switch_view`, `open_task`, `focus_task`.
4. `focus_task` should set a target task for Focus Mode so the focus window opens on the intended item when present in today's plan.

Why this approach:
- No new IPC transport or daemon protocol required.
- Works with current local-first shared SQLite architecture.
- Keeps command semantics explicit and auditable.

Risks and guardrails:
- **Risk:** command spam or stale commands reopening old UI states.
  - **Guardrail:** command IDs + handled ID acknowledgement.
- **Risk:** app not running when command is issued.
  - **Guardrail:** tool response should clarify best-effort semantics; command is queued for next poll.
- **Risk:** over-expanding into full remote-control complexity.
  - **Guardrail:** keep action set small and user-centric; no arbitrary script execution.

This is not a replacement for good UI. It is a second interaction layer that complements conversational control.

**Status:** Accepted and implemented as MVP (`control_app_ui` + app-side consumer + focus target handoff).

---

## #040 — Immersive macOS Title Bar Integration
**Source:** User UX feedback
**Idea:** The desktop app top title area feels detached ("gray strip" effect). Compared with well-integrated native apps, the title region should blend with app content through overlay/blur and visual continuity.

**Evaluation:** Correct. A detached title bar weakens spatial immersion and makes the app feel less native. On macOS, the right pattern is:
- use overlay title bar mode
- let content visually extend under the title area
- keep a lightweight drag region with subtle separation, not a hard visual block

Implementation notes:
1. Set main window to macOS title bar overlay style.
2. Keep native traffic lights and standard close/minimize/maximize behavior.
3. Add a thin in-app top blend layer (blur + gradient + drag region) so content and title area integrate.
4. Preserve mobile and utility windows behavior (no change for focus/popover unless explicitly redesigned).

Risks:
- Controls near the top can conflict with traffic-light hit zone.
- Too much blur/contrast can reduce readability.

Guardrails:
- reserve top inset consistently in desktop layout
- keep blend layer low visual weight
- maintain strong text contrast in all themes

**Status:** Accepted and implemented for main window (overlay title bar + integrated top blend layer).

---

## #041 — Design Quality Over Implementation Speed (Execution Principle)
**Source:** User feedback
**Idea:** UI/UX changes should prioritize coherent design quality over shipping speed. "Quick implementation" that weakens visual hierarchy or interaction clarity creates churn and rework.

**Evaluation:** Correct and actionable. Fast iteration is useful only when the loop includes deliberate design judgment. For Lorvex, where ergonomics and trust are core value props, rushed UI changes can degrade the product even if the feature technically works.

Operational interpretation:
1. Before coding a non-trivial UI change, define intent: what user friction it resolves.
2. Validate layout rhythm/hierarchy: spacing, contrast, alignment, information density.
3. Validate interaction ergonomics: expected behavior, error states, and recovery path.
4. Only then implement and verify.

Guardrails:
- Avoid purely cosmetic churn; each change must map to a user-facing problem.
- Prefer small coherent visual systems over one-off tweaks.
- If uncertainty remains, ship a narrower but more polished slice.

This principle complements #038 (co-evolution): assistant feedback drives what to fix; design rigor determines how to fix it.

**Status:** Accepted as an ongoing execution principle. Enforced via Operating System checklist.

---

## #042 — Life Module Use Cases: Books, Movies, Goals, Courses, Ideas
**Source:** User insight (#902)
**Idea:** Five concrete use cases the user wants Lorvex to serve well:
1. **Book reading goals** — track books to read, log completions with check-ins
2. **Movie/media tracking** — capture a watch-list and reviews
3. **Life goals** — short/medium/long-term goal recording and progress tracking
4. **Self-study courses** — track learning progress, similar to book/movie goals
5. **Random idea capture** — especially for researchers/PhD students, lightweight brainstorm idea pages, to be formalized later into proposals

**Evaluation:**
Use cases 1-4 share a common pattern: tracking items with a goal/target state and completion logging. They map naturally to the existing task model with:
- Lists per domain (Reading, Movies, Courses, Goals)
- Tags for categorization (genre, priority, time-horizon)
- AI conventions for how to manage each type (e.g., "when user finishes a book, log completion and ask for a brief review")
- Habit tracking integration for recurring engagement (daily reading, weekly course modules)


The deeper question is whether books/movies/goals should be first-class entity types with dedicated schema and UI, or should they be modeled as tasks with conventions. The VISION.md already identifies "Journal + Goals + Knowledge" as Phase 2-3 modules. The user's request validates this direction.

**Recommendation:**
- **Short-term:** Use existing task lists + AI conventions (create "Reading", "Watchlist", "Goals" lists; AI manages completion tracking and periodic review prompts)
- **Medium-term:** When habit tracking Phase 2 ships with Today view integration, books/movies can use habit-like daily check-ins
- **Long-term:** Goals module (RFC-004 life data model) would provide dedicated schema for long-horizon targets with milestones

**Status:** Accepted. Short-term approach works with existing architecture. Long-term dedicated modules tracked in Vision/ROADMAP Milestone 5.

---

## #043 — Settings Center Design for Growing Feature Set
**Source:** User insight (#926)

**Evaluation:**
Current approach: `sidebar_visible_modules` preference controls which views appear in sidebar. All modules are visible by default. Users can hide modules in Settings. This works but doesn't scale well — as module count grows, the sidebar becomes cluttered for users who only use a few views.

Deeper design question: should Lorvex have a "feature discovery" UX where users progressively enable modules, or should everything be available and users prune what they don't want? Given the AI-native philosophy ("AI handles complexity"), the answer is:

1. **Core modules always visible:** Today, Lists, Upcoming, All Tasks
2. **Advanced modules visible but collapsible:** Calendar, Weekly Review, Daily Review
4. **AI can suggest enabling modules** based on usage patterns ("You've been using dependencies in your tasks. Want to enable the dependency graph view?")

The settings center itself should use progressive disclosure: "Features" section with visual cards showing each module's icon, name, and one-line description, with toggles.

**Status:** Under design. Tracked in #926. Existing sidebar_visible_modules system provides the foundation.

---

## #044 — System Calendar Integration via Local OS APIs
**Source:** User insight (#937)
**Idea:** Read external calendar events from the OS-level calendar database (EventKit on macOS/iOS, Windows Calendar API) and display them alongside Lorvex's own calendar_events. This lets the AI see the user's real schedule without requiring direct Google Calendar API access, OAuth flows, or cloud service dependencies.

**Evaluation:**
This is architecturally brilliant. By reading from the system calendar instead of direct cloud APIs:
- No API quota concerns (local API, no rate limits)
- No OAuth complexity (OS handles authentication)
- No cloud dependency (works offline after OS sync)
- Covers ALL the user's calendars at once (Google, iCloud, Outlook, Exchange)

The implementation lives cleanly in `platform/calendar_bridge/` — macOS uses `objc2` bindings to EventKit, Windows uses `windows-rs` for AppointmentStore.

Key design decisions:
1. **One-way read only** — Lorvex never writes to system calendar. Avoids bidirectional sync complexity.
2. **Separate cache table** (`external_calendar_events`) rather than mixing with Lorvex `calendar_events`. Keeps sync pipeline clean.
3. **Deduplication** by `(title, date, start_time)` match with visual distinction (external badge).
4. **Privacy toggle** in settings to enable/disable system calendar access.
5. **MCP tools**: `get_external_calendar_events(from, to)` for AI schedule awareness, `check_schedule_conflicts()` for scheduling validation.

This aligns with the Vision doc: "Calendar Sync via AI assistant-as-Agent" — but is actually better because it doesn't require the AI to act as intermediary. The app itself shows the complete schedule.

**Status:** Accepted for implementation. Tracked in #937. Requires platform-specific native code (objc2 on macOS, windows-rs on Windows). Linux is low priority (no universal calendar API).

---

## #045 — Read System Reminders
**Source:** User exploration (#939)
**Idea:** Read tasks from the OS-level reminders/tasks app (on macOS/iOS via the platform's EventKit reminder store; on other platforms via the platform task API) so that tasks created via voice capture or system UI become visible in Lorvex, potentially allowing the AI to triage them into formal Lorvex tasks.

**Evaluation:**
The workflow described ("voice capture -> Lorvex reads -> AI triages into formal task") is genuinely compelling. It turns the system reminders app into a lightweight capture inbox that feeds Lorvex, which is aligned with the AI-native philosophy: the AI handles the organizational grunt work of processing raw captures.

However, there are significant concerns:

1. **Diminishing returns after calendar integration.** Issue #937 (system calendar integration, #044 above) already establishes the "read from OS" pattern. Reminders integration uses the same EventKit framework on macOS/iOS but adds a separate data pipeline, deduplication logic, and UI surface. The incremental value over calendar integration is modest.

2. **User behavior assumption is questionable.** Once a user commits to Lorvex with an MCP-capable AI assistant, they are unlikely to keep using the system reminders app as a parallel system. The primary capture path is conversation with the AI. Voice-created reminders are a niche scenario (e.g., driving, hands-free) and most of these are one-off grocery-list items, not the kind of tasks that benefit from Lorvex's planning intelligence.

3. **Some platform task services require network API access**, violating Lorvex's local-first principle. Only the on-device reminder-store path is truly local.

4. **Deduplication is harder than it looks.** Reminders lack the structured fields (due time, duration, project context) that make calendar event deduplication tractable. A reminder "buy milk" and a Lorvex task "Buy milk tomorrow" require fuzzy matching or AI intervention.

5. **Better alternative exists:** The AI assistant can simply ask the user "Do you have any voice-captured reminders to process?" during daily review and the user can relay them. This is zero-implementation-cost and preserves the conversational workflow.

**Status:** Deferred. Low ROI relative to implementation complexity. The calendar integration pattern (#937) is the right OS-bridge investment for now. If user research later shows significant Siri-capture usage patterns, revisit.

---

## #046 — System Focus / Do Not Disturb Mode Integration
**Source:** User exploration (#940)
**Idea:** Bidirectional integration between Lorvex's Focus Mode and macOS/iOS system Focus (Do Not Disturb) modes. When Lorvex enters Focus Mode, trigger system DND; when system enters Focus, Lorvex could adjust its behavior (suppress notifications, auto-enter focus mode).

**Evaluation:**
This sounds appealing in theory but falls apart under scrutiny:

1. **Lorvex Focus Mode and system Focus serve different purposes.** Lorvex Focus Mode is a UI mode that presents a single task in a distraction-free view. System DND is a notification-suppression mechanism. Conflating them creates a confusing coupling: the user enters Lorvex focus to concentrate on one task, and suddenly their phone calls are silenced. Or they enable DND for a meeting, and Lorvex assumes they are in deep-work mode.

2. **The "Lorvex -> system DND" direction is presumptuous.** A task manager should not unilaterally control system-level notification behavior. Users have carefully configured Focus modes with allowed contacts, app exceptions, and schedules. Lorvex overriding this is a trust violation.

3. **The "system -> Lorvex" direction has limited value.** If the user has DND on, Lorvex simply should not send notifications (which the OS already handles by suppressing them). There is no additional behavior adjustment needed.

4. **API limitations are real.** macOS does not expose a public API to programmatically activate Focus modes. `NSDoNotDisturbEnabled` is read-only and deprecated. Shortcuts integration could work but adds fragile indirect coupling. iOS Focus mode APIs are even more restricted for third-party apps.

5. **Overengineering risk.** This is the kind of feature that sounds good in a feature list but adds maintenance burden (platform-specific code paths, OS version compatibility) for a benefit that most users would never notice or configure.

**Status:** Rejected. The conceptual coupling is wrong (task focus != notification suppression), the APIs are limited, and the user value does not justify the platform-specific complexity. If users want this, they can create a personal Shortcut/Automation that triggers DND when Lorvex is frontmost.

---

## #047 — Index Tasks into Spotlight / System Search
**Source:** User exploration (#941)
**Idea:** Use Core Spotlight API (`CSSearchableItem`) on macOS to index Lorvex tasks into system-wide search, so users can find tasks via Spotlight. Investigate Windows Search equivalents.

**Evaluation:**
This is a reasonable discoverability feature, but several factors push it down the priority list:

1. **Lorvex already has Command Palette (Cmd+K)** with search across all tasks, lists, and actions. For users who have Lorvex open (which is most of the time for power users), this is faster and richer than Spotlight.

2. **The value proposition is "find a task when Lorvex is not open."** But Lorvex is a menubar/tray app that is always running. The popover window provides quick glance access. The scenario where a user reaches for Spotlight to find a Lorvex task instead of clicking the tray icon is narrow.

3. **Privacy concern is real.** Task titles and bodies entering the system search index means they are accessible to any app that reads Spotlight metadata. For a productivity tool that may contain sensitive project information, this is a meaningful privacy tradeoff that needs a settings toggle and careful scope control (index titles only? include body text?).

4. **Implementation is straightforward on macOS** (Core Spotlight is well-documented) but **Windows Search integration is significantly harder** (Windows Search Indexer protocol handlers are poorly documented and rarely used by modern apps). This creates a platform parity problem.

5. **Index maintenance adds overhead.** Every task create/update/delete needs to update the search index. For a write-heavy AI-operated database, this is non-trivial background work.

That said, Spotlight integration is a hallmark of well-integrated macOS apps. It signals quality and professionalism. For a productivity app, being findable system-wide is a reasonable expectation.

**Status:** Deferred to post-1.0. Nice polish feature for macOS, but not essential for the core experience. The Command Palette and tray popover already cover the primary search use cases. When implemented, scope to macOS only initially (Core Spotlight), with privacy toggle defaulting to off.

---

## #048 — Share Sheet Extension for Quick Task Creation
**Source:** User exploration (#942)
**Idea:** Register a Share Extension on iOS/macOS so users can share URLs, text, or images from any app directly into Lorvex as new tasks. Map shared content to task fields (URL -> `context_ref`, text -> `body`, etc.).

**Evaluation:**
This is one of the stronger ideas in this batch because it addresses a genuine gap in the mobile experience:

1. **On iOS without MCP, capture paths are limited.** The mobile companion app cannot rely on an AI assistant session for task creation. Share Sheet becomes one of the most natural input vectors: reading an article and sharing to Lorvex, seeing a recipe and sharing the link, forwarding a message as a task.

2. **Aligns with AI-native philosophy.** The shared content arrives as raw input; the AI (during next session) can then triage, tag, set due dates, and organize it. This is exactly the "capture first, organize later" pattern from GTD that the AI is supposed to automate.

3. **Technical complexity is high but bounded.** Share Extensions on iOS/macOS require a separate target in the Xcode project, written in Swift, with its own entitlements and App Group for data sharing. This is outside Tauri's direct control. For the iOS companion (which will likely be native Swift anyway), this is natural. For macOS Tauri app, it requires a separate native extension bundled alongside.

4. **Field mapping is well-defined:** URL -> `context_ref`, selected text -> `body`, page title -> task title. This covers 90% of share scenarios cleanly.

5. **Android equivalent (Intent Share) follows the same pattern** and would be implemented in the Android companion.

The main risk is timing: this depends on the mobile companion app existing, which is a Milestone 3+ item.

**Status:** Accepted for mobile companion milestone. Not implementable for desktop-only Tauri app in the current phase. When the iOS companion is built, Share Extension should be a launch feature, not a follow-up. Track as a requirement in the mobile companion design spec.

---

## #049 — Siri Shortcuts / App Intents Integration
**Source:** User exploration (#943)
**Idea:** Register App Shortcuts (iOS 16+ App Intents framework) so users can create tasks, check today's plan, complete tasks, or start focus mode via Siri voice commands or Shortcuts automations.

**Evaluation:**
This is conceptually strong but practically premature:

1. **Voice task creation is genuinely valuable.** "Hey Siri, add 'call dentist' to Lorvex" while driving or cooking is exactly the kind of friction-free capture that boosts system trust. This aligns with the AI-native vision: capture is effortless, organization happens later.

2. **App Intents framework (iOS 16+) is the right API.** It provides system-level integration including Spotlight suggestions, Siri, Shortcuts app, and Action Button. The older SiriKit Intents API is deprecated.

3. **Requires native Swift code.** App Intents are defined as Swift structs conforming to `AppIntent`. This cannot be bridged through Tauri's webview layer. For the iOS companion (likely native Swift), this is a natural fit. For macOS, Shortcuts.app integration is available but requires the same Swift AppIntent definitions.

4. **Scope should be minimal initially:** Create task (title only, AI organizes later) and "What's my next task?" query. Advanced operations (complete task, start focus) add complexity with entity resolution ("which task?") that requires careful UX.

5. **Depends on iOS companion existing.** Without a native iOS app, there is no host for App Intents.

6. **macOS Shortcuts integration is interesting as a standalone feature** even without iOS. Users could create Shortcuts automations like "Every morning at 8am, open Lorvex current focus." But the implementation cost is still native Swift code bundled with the Tauri app.

**Status:** Accepted for mobile companion milestone, same as #048. Siri Shortcuts and Share Sheet are complementary iOS integration features that should ship together with the companion app. For macOS, defer until the cost/benefit of bundling Swift AppIntent code with the Tauri app is evaluated.

---

## #050 — Import from Third-Party Productivity Tools
**Source:** User exploration (#944)
**Idea:** Build importers for common productivity tools (their CSV/JSON exports) to reduce migration friction for new users.

**Evaluation:**
Migration tooling is a classic "high strategic value, moderate engineering cost" investment. Analysis:

1. **The AI-assisted migration path already exists and is arguably better.** A user can export from their old tool (e.g. CSV), paste the data into a conversation with their AI assistant, and the AI can create tasks via MCP with intelligent field mapping, deduplication, and organization. This is more flexible than any hardcoded importer because the AI can handle edge cases, ask clarifying questions, and apply Lorvex-specific organization during import.

2. **Hardcoded importers are maintenance burdens.** Other tools change their export formats without notice. Each importer is a separate code path that rots over time. For an alpha-stage product, this is premature investment.

3. **The real migration barrier is not technical.** Users don't switch task managers because import is hard. They switch because the new tool is compelling enough to justify the effort. A smooth AI-assisted migration conversation ("Let's move your old tasks to Lorvex. Export your data and paste it here.") is actually a better onboarding experience than a silent bulk import, because the AI can explain how Lorvex works differently during the process.

4. **Generic format support (CSV, Markdown task lists) has better ROI** than tool-specific importers. The existing `import_from_export` MCP tool handles Lorvex's own format. Adding a `import_generic_tasks` tool that accepts a simple title/due_date/notes CSV would cover 80% of migration needs from any tool.

5. **If built, priority order should be:** generic CSV first (covers the broadest set of source tools), with tool-specific importers added only where a large share of incoming users come from one source.

**Status:** Deferred. The AI-assisted migration path is sufficient and arguably superior for alpha. A generic CSV/Markdown import MCP tool would be a reasonable low-cost addition. Tool-specific importers are a post-1.0 growth feature, not an alpha priority.

---

## #051 — Standard Format Export (.ics / Markdown / CSV)
**Source:** User exploration (#945)
**Idea:** Export Lorvex data in standard formats beyond the native JSON snapshot: .ics for calendar events, Markdown for task lists, CSV for spreadsheet analysis, printable daily/weekly plan format.

**Evaluation:**
Data portability is a trust signal, especially for an open-source local-first app. But the current state already covers the critical need, and the incremental formats have varying value:

1. **JSON export already exists** (`export_all_data` MCP tool with versioned JSONL). This is the "data sovereignty" guarantee: your data is never locked in. For the primary use case (backup, migration, portability), this is sufficient.

2. **.ics export is the strongest candidate.** Calendar events have a well-defined standard (RFC 5545), and users legitimately want to share their schedule with others or import into other calendar apps. The scope is narrow (only `calendar_events` table), the format is well-specified, and the implementation is straightforward (string templating, no external library needed).

3. **Markdown export is nice but the AI can already do this.** "Export my tasks as a Markdown checklist" is a trivial MCP operation: the AI reads tasks and formats them. Building this into the app adds UI complexity (export dialog, format selection) for something the AI does naturally in conversation.

4. **CSV export is similarly AI-achievable** and mainly useful for power users doing spreadsheet analysis, which is a niche scenario for a task manager.

5. **Printable current focus or focus schedule** is a charming idea but conflicts with the AI-native philosophy. The point of Lorvex is that the plan is dynamic and AI-managed. Printing it freezes a moment in time. That said, some users genuinely want paper day-plans, and it is a delightful touch.

6. **The AI can serve as the universal export adapter.** Rather than building N export formats into the app, lean into the AI's ability to transform data into any format the user requests. This is more flexible, requires zero app code, and naturally extends to any format.

**Status:** Partially accepted. .ics export for calendar events is worth building as a focused feature (small scope, clear standard, genuine need for calendar sharing). All other formats are better served by AI-assisted export via MCP conversation. Do not build a generic "export as..." dialog.

---

## #052 — Apple Watch Support
**Source:** User exploration (#946)
**Idea:** Build an Apple Watch app or complication showing today's task count, next task, habit completion progress, or other glanceable information.

**Evaluation:**
This is a "someday, maybe" feature that should not distract from the core product:

1. **Apple Watch app development is a significant, specialized investment.** It requires SwiftUI for watchOS, WatchConnectivity framework for phone-watch communication, WidgetKit for complications, and a separate watchOS app target. This is an entirely separate codebase with its own lifecycle, testing requirements, and OS compatibility matrix.

2. **Watch app usage data across the industry is sobering.** Most third-party watch apps have very low engagement after initial novelty. The primary value is complications (glanceable data on the watch face), not the full app experience.

3. **Depends on iOS companion existing.** A watchOS app communicates with its paired iPhone app. Without the iOS companion, there is no data source for the watch.

4. **The information density that fits on a watch is minimal.** "3 tasks today" or "Next: Call dentist 2pm" is about the maximum. This is the same information the iOS lock screen widget would show, making the watch app redundant with iOS widgets.

5. **WidgetKit complications (watchOS 9+) can be built as part of the iOS companion** without a full standalone watch app, which would be the minimum viable approach.

6. **Priority ordering should be:** iOS companion -> iOS widgets -> iOS lock screen widget -> Watch complication -> Watch app. Each step depends on the previous one being solid.

**Status:** Deferred to well after mobile companion ships. If the iOS companion proves successful and user demand materializes, a minimal WidgetKit complication (not a full watch app) would be the right first step. Do not invest in this during alpha or beta.

---

## #053 — Cross-Application Drag and Drop (Files/Links to Tasks)
**Source:** User exploration (#947)
**Idea:** Support dragging files from Finder, URLs from browsers, or text from other apps into Lorvex to create tasks or attach context. Map dropped content to task fields (file path -> `context_ref`, URL -> `context_ref`, text -> body).

**Evaluation:**
This is a solid quality-of-life feature for desktop power users:

1. **Aligns with the "effortless capture" philosophy.** Drag-and-drop is a natural, zero-friction interaction on desktop. Dragging a project brief PDF onto a task to attach it, or dragging an issue-tracker URL to create a linked task, reduces context-switching cost.

2. **Tauri 2.x has drag-and-drop support** via the `on_drag_drop_event` API on windows and webview. The frontend can handle `dragover`/`drop` events to receive files and URLs. This is not platform-specific native code; it works through standard web APIs that Tauri exposes.

3. **Implementation complexity is moderate.** The drop handler needs to: detect content type (file path, URL, text), determine the drop target (existing task to attach, empty area to create new task), and map to the appropriate field. The UI needs visual feedback (drop zones, hover highlights).

4. **Field mapping is clean:** File -> store path in `context_ref` (not the file itself; Lorvex is not a file storage system), URL -> `context_ref`, text -> `body` or task title for new tasks.

5. **Usage frequency is the main question.** In practice, how often do users drag things into their task manager? For some workflows (research, project management), frequently. For simple personal task management, rarely. But the implementation cost is low enough that even moderate usage justifies it.

6. **This is a desktop-only feature** and does not need mobile consideration.

**Status:** Accepted, low priority. Good desktop polish feature with moderate implementation cost. Should be picked up during a UX polish cycle after core features stabilize, not as a priority during alpha. The Tauri drag-and-drop API makes this feasible without platform-specific native code.

---

## #054 — Color Vision Deficiency Accessible Color Scheme
**Source:** User exploration (#948)
**Idea:** Provide accessible color schemes for users with color vision deficiencies (particularly red-green, affecting ~8% of males). Either independent high-contrast/CVD appearance profiles, or ensure all themes use non-color-only differentiation (icons, shapes, patterns as supplementary cues).

**Evaluation:**
This is an important accessibility concern, and the right approach matters more than the timing:

1. **The correct solution is "not color alone" universally, not a separate CVD theme.** WCAG 2.1 Success Criterion 1.4.1 (Use of Color) requires that color is not the sole means of conveying information. If Lorvex satisfies this criterion in its default themes, CVD-specific themes become unnecessary. This is cheaper and more robust than maintaining separate color profiles.

2. **Current Lorvex UI does partially rely on color alone.** The danger/warning/success semantic colors (red/yellow/green) are used for overdue badges, completion states, and priority indicators. If these elements only differ by color, they fail the WCAG criterion. Adding supplementary cues (icons, text labels, or shape differences) fixes this for everyone, not just CVD users.

3. **Practical fixes are straightforward:**
   - Overdue tasks: already show "overdue" text label alongside red color -- good.
   - Completion: checkmark icon provides non-color cue -- good.
   - Priority/urgency: if only conveyed by color gradient, add a numeric or text indicator.
   - Habit streak: if green-only, add a checkmark or count.
   - Calendar event coloring: use patterns or border styles in addition to fill color.

4. **A `prefers-contrast` media query response** is a nice addition but not the core fix. High contrast mode helps low-vision users but does not address CVD (which is about hue discrimination, not contrast).

5. **Implementation approach:** Audit all color-only information carriers, add supplementary non-color cues to each. This is a series of small, targeted UI changes rather than a new theme system.

**Status:** Accepted as a targeted accessibility audit, not a new theme feature. The fix is ensuring WCAG 1.4.1 compliance in default themes (non-color cues everywhere), not building alternative color profiles. Should be tracked as part of the WCAG accessibility review (#054 cross-ref with the continuous review loop). Priority is low for alpha but should be resolved before 1.0 release.

## Feature ideation — 2026-03-18

### User insight (from session observations)

**Observation:** During the CSS review, we found that the global `user-select: none` prevented all text copying. The fix was to selectively re-enable selection on content areas. This suggests a broader pattern: the app is designed as a "native app" but sometimes users need web-like behaviors (text selection, right-click → copy, etc.).

**Idea: "Copy to clipboard" buttons on key content areas** — Add small copy buttons (📋) next to task IDs, context refs, AI notes, and changelog entries. This is more discoverable than text selection and works even with user-select: none.

**Idea: Task ID display in task detail** — The task ID (UUID) is never shown to the user, but MCP tools reference tasks by ID. Showing a compact task ID (first 8 chars) in the task detail panel would help users cross-reference MCP tool output with the UI.

### Competitive insight

**Observation:** The habit tracking has a great heatmap visualization but no goal-setting beyond frequency type. Other habit trackers allow setting specific targets ("exercise 3x/week this month" as a goal, not just a frequency).

**Idea: Habit goal milestones** — Let users set time-bounded targets ("complete 20 workouts in March"). The AI could track progress and adjust encouragement based on pacing. This would be a natural extension of the existing habit system.

### Architecture insight

**Observation:** The `cancel_recurring_successors` function uses a title+recurrence heuristic to identify successors (#1000). This is fragile. The deeper issue is that the task table has no `spawned_from` foreign key to track parentage.

**Idea: `spawned_from` column migration** — Add a nullable `spawned_from TEXT REFERENCES tasks(id)` column to the tasks table. The recurrence spawner would set this when creating successor tasks. The successor cancellation logic would then use a precise `WHERE spawned_from = ?` query instead of the title heuristic.

🤖 Generated with [Claude Code](https://claude.ai/claude-code)
