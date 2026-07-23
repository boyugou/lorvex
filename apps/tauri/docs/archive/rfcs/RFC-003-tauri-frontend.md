# RFC-003: Tauri Frontend Architecture

> Archived historical document. Preserved for reference only; not part of the current implementation contract.


*Status: IMPLEMENTED — 76 IPC commands, 24 components, 13 views*

---

## Problem

Design the Tauri app's internal architecture so that:
1. The React frontend stays simple and focused on display
2. SQLite access is owned by the Rust backend (not exposed raw to the WebView)
3. The app stays responsive while Claude writes to the DB via MCP
4. State management is predictable and doesn't fight with polling
5. Component structure matches the view hierarchy in UX.md

---

## IPC Architecture: Tauri Commands (Rust → JS boundary)

The React frontend NEVER does raw SQL. All data access goes through named Tauri commands implemented in Rust. This is the security boundary.

```
React Component → invoke('command_name', args) → Rust handler → rusqlite → response
```

### Command List (Rust side)

```rust
// Tasks
get_tasks(filter: TaskFilter) -> Vec<Task>
get_task(id: String) -> Option<Task>
complete_task(id: String) -> Task
defer_task(id: String, defer_to: String) -> Task
update_task(id: String, patch: TaskPatch) -> Task
cancel_task(id: String) -> ()
permanent_delete_task(id: String) -> ()
create_task_quick(title: String) -> Task    // Quick capture: raw title → inbox

// Lists
get_all_lists() -> Vec<ListWithCount>
get_list_tasks(list_id: String) -> Vec<Task>

// Views
get_todays_view() -> TodayView             // Due today + overdue + current focus if it exists
get_upcoming_view(days: i32) -> Vec<DayGroup>

// Inbox
get_inbox() -> Vec<Task>
accept_inbox_task(id: String, patch: TaskPatch) -> Task
dismiss_inbox_task(id: String) -> ()

// AI Changelog
get_changelog(limit: i32, offset: i32) -> Vec<ChangelogEntry>
undo_changelog_entry(entry_id: String) -> ()

// Preferences
get_preferences() -> HashMap<String, Value>
```

**Why Rust commands own the SQL, not tauri-plugin-sql:**
- tauri-plugin-sql exposes arbitrary SQL to the WebView — this is a wide attack surface
- Our Rust commands expose specific, typed operations — much smaller surface
- Rust commands can enforce business rules (e.g., always recompute urgency_score on update)
- Better error typing: Rust returns typed errors, not just SQL error strings

---

## State Management: TanStack Query (React Query)

React Query manages all server state (= SQLite data). It handles:
- Caching (so re-renders don't re-fetch)
- Background polling (stay in sync with MCP writes)
- Optimistic updates (complete a task → it disappears immediately, confirm in background)
- Error states

```typescript
// Polling for changes from MCP (every 2 seconds)
const { data: todayView } = useQuery({
  queryKey: ['today'],
  queryFn: () => invoke<TodayView>('get_todays_view'),
  refetchInterval: 2000,
  staleTime: 1000,
});

// Optimistic complete
const completeMutation = useMutation({
  mutationFn: (id: string) => invoke<Task>('complete_task', { id }),
  onMutate: async (id) => {
    // Cancel ongoing refetch
    await queryClient.cancelQueries({ queryKey: ['today'] });
    // Optimistically remove task from view
    queryClient.setQueryData(['today'], (old: TodayView) => ({
      ...old,
      focus: old.focus.filter(t => t.id !== id),
      due_today: old.due_today.filter(t => t.id !== id),
    }));
  },
  onSettled: () => {
    // Always refetch to get actual state
    queryClient.invalidateQueries({ queryKey: ['today'] });
    queryClient.invalidateQueries({ queryKey: ['lists'] });
  },
});
```

**Why React Query over Zustand/Jotai:**
- SQLite is the source of truth, not JS memory. React Query models this correctly.
- Built-in polling with stale-time prevents over-fetching
- Optimistic updates are first-class (we need this for completion feel)
- Zustand would require manual cache invalidation on every Rust command response

---

## Component Hierarchy

```
App
├── AppShell                      # Layout: sidebar + main content
│   ├── Sidebar (collapsible)
│   │   ├── SidebarNav            # Today, Next 7d, Inbox, AI Log
│   │   └── SidebarLists          # User lists with task counts
│   └── MainContent               # View outlet
│       ├── TodayView
│       │   ├── DailyBriefing     # AI's note (from current_focus.briefing)
│       │   ├── FocusSection      # AI-curated focus tasks
│       │   ├── DueTodaySection   # Other tasks due today
│       │   └── OverdueSection    # Collapsed by default
│       ├── ListView              # Tasks in a specific list
│       ├── NextSevenView         # Tasks grouped by day
│       ├── InboxView
│       │   └── InboxCard         # Inline-editable, shows raw_input
│       ├── AILogView
│       │   └── ChangelogEntry    # With undo button
│       └── AllTasksView
│
├── TaskDetailPanel               # Floating panel (right side or popover)
│   ├── TaskHeader                # Title (inline editable)
│   ├── TaskMeta                  # Due date, duration, list, tags
│   ├── TaskBody                  # Markdown body (view/edit toggle)
│   ├── AINotes                   # Visually distinct block, read-only
│   └── TaskActions               # Complete, Defer, Delete
│
├── QuickCapturePanel             # NSPanel near menu bar
├── CommandPalette                # ⌘K overlay
└── UndoToast                     # Bottom of screen, auto-dismiss 30s
```

---

## Data Flow: A Complete Example

User clicks "Complete" on a task in Today view:

1. `TaskRow` calls `completeMutation.mutate(task.id)`
2. `onMutate`: optimistically remove task from cached `today` data → task disappears immediately (feels instant)
3. React Query fires `invoke('complete_task', { id })` to Rust
4. Rust: updates status='completed', completed_at=now, recomputes urgency_score, writes to ai_changelog
5. Rust returns updated Task object
6. `onSettled`: invalidate `today`, `lists` queries → they refetch from DB
7. `UndoToast` appears: "Completed 'Write intro section' [Undo] ⬛⬛⬛⬛⬛⬛⬛⬛⬛⬛" (30s bar)
8. After 30s: toast auto-dismisses

Total perceived latency: ~0ms (optimistic update fires immediately)

---

## Tauri Window Configuration

### Main Window
```json
{
  "label": "main",
  "title": "Lorvex",
  "width": 900,
  "height": 700,
  "minWidth": 500,
  "minHeight": 400,
  "decorations": true,
  "vibrancy": "sidebar",      // macOS frosted sidebar effect
  "transparent": false,
  "resizable": true,
  "fullscreenable": true,
  "titleBarStyle": "overlay"  // traffic lights only, no title text
}
```

### Quick Capture Panel
```json
{
  "label": "quick-capture",
  "type": "panel",
  "width": 400,
  "height": 60,
  "decorations": false,
  "alwaysOnTop": true,
  "skipTaskbar": true,
  "transparent": true,
  "resizable": false
}
```

## Styling: Tailwind CSS with Dark Mode First

```typescript
// tailwind.config.ts
export default {
  darkMode: 'class',  // toggle by adding 'dark' to <html>
  theme: {
    extend: {
      colors: {
        // Core palette
        accent: {
          DEFAULT: '#4F46E5',  // indigo-600 — the app's single accent color
          subtle: '#4F46E508', // 5% opacity for AI Notes backgrounds
        },
        // Surface hierarchy (dark mode)
        surface: {
          0: '#0F0F0F',  // window background
          1: '#1A1A1A',  // sidebar, panels
          2: '#242424',  // cards, list items
          3: '#2E2E2E',  // hover states
        },
        // Text hierarchy
        text: {
          primary: '#F5F5F5',
          secondary: '#A0A0A0',
          tertiary: '#606060',
        },
      },
      fontFamily: {
        sans: ['-apple-system', 'BlinkMacSystemFont', 'SF Pro Text', 'sans-serif'],
        mono: ['SF Mono', 'Menlo', 'monospace'],  // for AI-generated content
      },
    }
  }
}
```

---

## Key Decisions Made

**Q: vibrancy / translucency for the sidebar?**
A: Yes, use Tauri's `vibrancy: 'sidebar'` for the macOS frosted glass effect on the sidebar. It's one of the details that makes the app feel native. Conditionally apply — falls back gracefully on non-macOS.

**Q: Should we use Tauri's built-in global shortcuts or handle them in React?**
A: Tauri Rust side registers global shortcuts (⌘⇧Space for Quick Capture). In-app shortcuts (⌘K, ⌘⏎, ⌘D) handled in React with event listeners.

**Q: How to handle the task detail panel — popover or slide-in?**
A: Slide-in panel from the right. Appears within the app window, doesn't create a new OS window. The main content compresses slightly to accommodate.

**Q: Font rendering?**
A: Use `-apple-system` which resolves to SF Pro on macOS. This is the highest quality font rendering possible on macOS. No external font downloads needed.

---

## What This RFC Deliberately Excludes

- iOS/iPadOS layout adaptation (separate RFC when iOS work begins)
- Keyboard navigation implementation details (covered in UX.md)
- Animation specifics (implementation-level detail)
- Accessibility tree / VoiceOver (v2 feature)
