# macOS App Menu Bar — Design Spec

**Status:** Approved
**Lane:** Vision (UX native feel)

## Problem

Lorvex uses Tauri's default macOS menu bar, which provides only minimal items (About, Edit basics, Window basics). The Tauri macOS build is now a developer/reference build, but it should still expose comprehensive menus and keyboard shortcuts so Mac-only contributors can test a native-feeling desktop surface.

## Solution

Build a custom native macOS menu bar in Rust using Tauri 2's `Menu`, `Submenu`, `MenuItem`, and `PredefinedMenuItem` APIs. The menu exposes all navigation views, task actions, window management, and app lifecycle operations with proper accelerator shortcuts.

## Architecture

### New file

`app/src-tauri/src/desktop_shell/app_menu.rs` — single module that builds and returns the complete `Menu`. Exported via `desktop_shell/mod.rs`.

### Integration point

In `lib.rs` setup closure, call `build_app_menu(app)` and set it via `app.set_menu(menu)`. Register `on_menu_event` on the builder to handle custom menu item clicks.

### Event flow

Menu item click (native) -> `on_menu_event` callback in Rust -> emit Tauri event -> frontend listener dispatches action.

Frontend listens for:
- `menu://navigate` with `{ view: string }` payload -> calls `navigateToView()`
- `menu://quick-capture` -> opens quick capture overlay
- `menu://command-palette` -> opens command palette
- `menu://toggle-always-on-top` -> toggles always-on-top

Backend-only actions (no event needed):
- `check_updates` -> calls updater API directly
- `export_data` / `import_data` -> emits event for frontend dialog

## Menu Structure

### Lorvex (App Menu)

| Item | ID | Accelerator | Type |
|------|----|-------------|------|
| About Lorvex | — | — | PredefinedMenuItem::about |
| --- | | | separator |
| Check for Updates... | `check_updates` | — | MenuItem |
| --- | | | separator |
| Settings... | `settings` | `CmdOrCtrl+,` | MenuItem |
| --- | | | separator |
| Services | — | — | PredefinedMenuItem::services |
| --- | | | separator |
| Hide Lorvex | — | `CmdOrCtrl+H` | PredefinedMenuItem::hide |
| Hide Others | — | `Alt+CmdOrCtrl+H` | PredefinedMenuItem::hide_others |
| Show All | — | — | PredefinedMenuItem::show_all |
| --- | | | separator |
| Quit Lorvex | — | `CmdOrCtrl+Q` | PredefinedMenuItem::quit |

### File

| Item | ID | Accelerator | Type |
|------|----|-------------|------|
| New Task | `quick_capture` | `CmdOrCtrl+N` | MenuItem |
| --- | | | separator |
| Export Data... | `export_data` | — | MenuItem |
| Import Data... | `import_data` | — | MenuItem |
| --- | | | separator |
| Close Window | — | `CmdOrCtrl+W` | PredefinedMenuItem::close_window |

### Edit

| Item | ID | Accelerator | Type |
|------|----|-------------|------|
| Undo | — | `CmdOrCtrl+Z` | PredefinedMenuItem::undo |
| Redo | — | `Shift+CmdOrCtrl+Z` | PredefinedMenuItem::redo |
| --- | | | separator |
| Cut | — | `CmdOrCtrl+X` | PredefinedMenuItem::cut |
| Copy | — | `CmdOrCtrl+C` | PredefinedMenuItem::copy |
| Paste | — | `CmdOrCtrl+V` | PredefinedMenuItem::paste |
| Select All | — | `CmdOrCtrl+A` | PredefinedMenuItem::select_all |
| --- | | | separator |
| Find... | `command_palette` | `CmdOrCtrl+K` | MenuItem |

### View

Every permanent navigation destination has a derivable shortcut:
primary views on `⌘1`–`⌘4`, secondary views on `⌘5`–`⌘0` in sidebar
order, and the remaining modules on `⌘⇧`-letter.

| Item | ID | Accelerator | Type |
|------|----|-------------|------|
| Today | `view_today` | `CmdOrCtrl+1` | MenuItem |
| Next 7 Days | `view_upcoming` | `CmdOrCtrl+2` | MenuItem |
| All Tasks | `view_all` | `CmdOrCtrl+3` | MenuItem |
| Someday | `view_someday` | `CmdOrCtrl+4` | MenuItem |
| --- | | | separator |
| Calendar | `view_calendar` | `CmdOrCtrl+5` | MenuItem |
| Eisenhower Matrix | `view_eisenhower` | `CmdOrCtrl+6` | MenuItem |
| Kanban Board | `view_kanban` | `CmdOrCtrl+7` | MenuItem |
| Habits | `view_habits` | `CmdOrCtrl+8` | MenuItem |
| Daily Review | `view_daily_review` | `CmdOrCtrl+0` (mac) / `CmdOrCtrl+Shift+0` (non-mac) | MenuItem |
| --- | | | separator |
| AI Memory | `view_memory` | `Shift+CmdOrCtrl+M` | MenuItem |
| Dependencies | `view_dependencies` | `Shift+CmdOrCtrl+D` | MenuItem |
| AI Activity | `view_ai_changelog` | `Shift+CmdOrCtrl+A` | MenuItem |
| Weekly Review | `view_review` | `Shift+CmdOrCtrl+W` | MenuItem |
| Recurring | `view_recurring` | `Shift+CmdOrCtrl+R` | MenuItem |
| --- | | | separator |
| Enter Full Screen | — | — | PredefinedMenuItem::fullscreen |

### Window

| Item | ID | Accelerator | Type |
|------|----|-------------|------|
| Minimize | — | `CmdOrCtrl+M` | PredefinedMenuItem::minimize |
| Zoom | — | — | PredefinedMenuItem::maximize |
| --- | | | separator |
| Always on Top | `toggle_always_on_top` | — | CheckMenuItem |
| --- | | | separator |
| Close Window | — | `CmdOrCtrl+W` | PredefinedMenuItem::close_window |

### Help

| Item | ID | Accelerator | Type |
|------|----|-------------|------|
| Lorvex Help | `open_help` | — | MenuItem |

## Keyboard Shortcut Migration

### Remove from JS (`useMainWindowShortcuts.ts`)

These shortcuts will be handled natively by macOS menu accelerators:
- `Cmd+1` through `Cmd+6` (view navigation)
- `Cmd+N` (quick capture)
- `Cmd+K` (command palette)

### Keep in JS

- `Escape` (close palette/capture, deselect task) — no menu equivalent
- Any view-specific shortcuts (task list j/k navigation)

### Frontend event listener

Add a `useEffect` in `MainWindowApp.tsx` (or a dedicated hook) that listens for `menu://navigate`, `menu://quick-capture`, `menu://command-palette`, `menu://enter-focus` events from Tauri and dispatches the appropriate actions through existing controller methods.

## i18n

Menu text is localized in Rust before the frontend loads. Native menu strings are generated from the canonical JSON locale catalogs (`app/src/locales/*.json`) at Tauri build time, with English fallback for locales that do not yet have a complete `menu.*` namespace. This keeps native menu copy on the same source of truth as the React runtime without allowing partial native-menu translations to create hybrid-language menus.

## Testing

- `cargo clippy` clean
- `npx tsc --noEmit` clean
- Manual verification: all menu items visible, all accelerators work, no double-firing with JS shortcuts removed
- View navigation via menu works for all 14 view types
- Check for Updates works (calls updater plugin)
- Export/Import triggers frontend dialog
