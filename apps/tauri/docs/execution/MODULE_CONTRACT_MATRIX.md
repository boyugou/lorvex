# Module Contract Matrix

This document is the durable sidebar/module contract matrix for the app shell. Update it whenever module visibility, fallback behavior, or the static validation path changes.

Desktop hidden-module guard ownership is centralized in
`app/src/app-shell/main-window/useMainWindowNavigation.ts`
(`resolveGuardedView` + `navigateToView`). Sidebar components remain
visibility/render surfaces instead of owning fallback policy. Mobile uses a
fixed `MobileMainWindow` more-view list and does not consult the
`sidebar_visible_modules` desktop preference.

## Contract Sources

- Module registry + defaults + normalization safety: `app/src/lib/sidebarModules.ts`
- Settings toggle surface: `app/src/components/settings/general/SidebarModulesPanel.tsx` + `app/src/components/settings/general/catalog.ts` (composed by `app/src/components/SettingsView.tsx`)
- Primary sidebar visibility guards: `app/src/components/sidebar/PrimaryNav.tsx`
- Secondary sidebar visibility guards + toolbox guards: `app/src/components/sidebar/SecondaryNav.tsx` + `app/src/components/sidebar/SidebarToolbox.tsx` (module definitions/render helper in `app/src/components/sidebar/secondaryModules.tsx`)
- Main view render branches: `app/src/components/MainViewContent.tsx`
- Desktop guarded navigation boundary: `app/src/app-shell/main-window/useMainWindowNavigation.ts`
- Mobile more-view inventory: `app/src/app-shell/main-window/MobileMainWindow.tsx`
- View type canonical union: `app/src/lib/types.ts`

## Matrix

| module id | settings toggle | sidebar guard | render branch | fallback behavior |
|---|---|---|---|---|
| `today` | `SIDEBAR_MODULE_OPTIONS` id `'today'` + `onSetSidebarModuleState(option.id, state)` (`settings/general/catalog.ts`, `SidebarModulesPanel.tsx`) | `canShowModule('today')` primary nav visibility (`PrimaryNav.tsx`) | `view.type === 'today'` (`MainViewContent.tsx`) | Desktop hidden-target guard resolves hidden module navigations to `{ type: 'today' }`; primary safety is also enforced by settings + normalization (`useMainWindowNavigation.ts`, `sidebarModules.ts`). |
| `upcoming` | `id: 'upcoming'` (`settings/general/catalog.ts`) | `canShowModule('upcoming')` primary nav visibility (`PrimaryNav.tsx`) | `view.type === 'upcoming'` (`MainViewContent.tsx`) | Same desktop hidden-module fallback contract as `today`. |
| `all_tasks` | `id: 'all_tasks'` (`settings/general/catalog.ts`) | `canShowModule('all_tasks')` primary nav visibility (`PrimaryNav.tsx`) | `view.type === 'all_tasks'` (`MainViewContent.tsx`) | Same desktop hidden-module fallback contract as `today`; mobile exposes search/all-tasks independently from desktop visibility prefs. |
| `someday` | `id: 'someday'` (`settings/general/catalog.ts`) | `canShowModule('someday')` primary nav visibility (`PrimaryNav.tsx`) | `view.type === 'someday'` (`MainViewContent.tsx`) | Same desktop hidden-module fallback contract as `today`; mobile exposes Someday in the fixed more-view list. |
| `calendar` | `id: 'calendar'` (`settings/general/catalog.ts`) | `canShowModule('calendar')` through secondary/toolbox filters (`SecondaryNav.tsx`, `SidebarToolbox.tsx`) | `view.type === 'calendar'` (`MainViewContent.tsx`) | Desktop hidden module target resolves to Today; mobile exposes Calendar in the fixed more-view list. |
| `eisenhower` | `id: 'eisenhower'` (`settings/general/catalog.ts`) | `canShowModule('eisenhower')` through secondary/toolbox filters (`SecondaryNav.tsx`, `SidebarToolbox.tsx`) | `view.type === 'eisenhower'` (`MainViewContent.tsx`) | Same desktop hidden-module fallback contract as `calendar`; mobile exposes Eisenhower in the fixed more-view list. |
| `daily_review` | `id: 'daily_review'` + `labelKey: 'nav.daily_review'` (`settings/general/catalog.ts`) | `canShowModule('daily_review')` through secondary/toolbox filters (`SecondaryNav.tsx`, `SidebarToolbox.tsx`) | `view.type === 'daily_review'` (`MainViewContent.tsx`) | Same desktop hidden-module fallback contract as `calendar`; mobile exposes Daily Review in the fixed more-view list. Semantic name is **Daily Review** (`nav.daily_review`). |
| `memory` | `id: 'memory'` (`settings/general/catalog.ts`) | `canShowModule('memory')` through secondary/toolbox filters (`SecondaryNav.tsx`, `SidebarToolbox.tsx`) | `view.type === 'memory'` (`MainViewContent.tsx`) | Same desktop hidden-module fallback contract as `calendar`; mobile exposes Memory in the fixed more-view list. |
| `review` | `id: 'review'` (`settings/general/catalog.ts`) | `canShowModule('review')` through secondary/toolbox filters (`SecondaryNav.tsx`, `SidebarToolbox.tsx`) | `view.type === 'review'` (`MainViewContent.tsx`) | Same desktop hidden-module fallback contract as `calendar`; mobile exposes Review in the fixed more-view list. |
| `recurring` | `id: 'recurring'` (`settings/general/catalog.ts`) | `canShowModule('recurring')` through secondary/toolbox filters (`SecondaryNav.tsx`, `SidebarToolbox.tsx`) | `view.type === 'recurring'` (`MainViewContent.tsx`) | Same desktop hidden-module fallback contract as `calendar`; mobile exposes Recurring in the fixed more-view list. |
| `kanban` | `id: 'kanban'` (`settings/general/catalog.ts`) | `showDesktopFeatures && canShowModule('kanban')` through secondary/toolbox filters (`SecondaryNav.tsx`, `SidebarToolbox.tsx`) | `view.type === 'kanban'` (`MainViewContent.tsx`) | Desktop hidden module target resolves to Today; mobile exposes Kanban in the fixed more-view list. |
| `dependencies` | `id: 'dependencies'` (`settings/general/catalog.ts`) | `showDesktopFeatures && canShowModule('dependencies')` through secondary/toolbox filters (`SecondaryNav.tsx`, `SidebarToolbox.tsx`) | `view.type === 'dependencies'` (`MainViewContent.tsx`) | Desktop hidden module target resolves to Today; mobile exposes Dependencies in the fixed more-view list. |
| `habits` | `id: 'habits'` (`settings/general/catalog.ts`) | `canShowModule('habits')` through secondary/toolbox filters (`SecondaryNav.tsx`, `SidebarToolbox.tsx`) | `view.type === 'habits'` (`MainViewContent.tsx`) | Same desktop hidden-module fallback contract as `calendar`; mobile exposes Habits in the fixed more-view list. |
| `ai_changelog` | `id: 'ai_changelog'` (`settings/general/catalog.ts`) | `canShowModule('ai_changelog')` through secondary/toolbox filters (`SecondaryNav.tsx`, `SidebarToolbox.tsx`) | `view.type === 'ai_changelog'` (`MainViewContent.tsx`) | Same desktop hidden-module fallback contract as `calendar`; mobile exposes AI Changelog in the fixed more-view list. |
| `focus` | `id: 'focus'` (`settings/general/catalog.ts`) | Action guard `canShowModule('focus') && onStartFocus` through secondary/toolbox filters (`SecondaryNav.tsx`, `SidebarToolbox.tsx`, `secondaryModules.tsx`) | No `View` render branch (action-only module; `View` union has no `focus` type in `lib/types.ts`) | No active-view fallback applies. Disabling hides the desktop sidebar action; explicit focus commands still route through focus-window IPC. |

## Shared Fallback Contract

- Desktop main-window navigation owns hidden-module guard at a single boundary:
  - `mapViewToSidebarModule(target)` + `visibleSidebarModules` gates hidden targets to `{ type: 'today' }` (`resolveGuardedView` in `useMainWindowNavigation.ts`)
  - the desktop guard query is disabled on mobile (`enabled: !usesMobileLayout`), so mobile navigation is independent of the desktop sidebar visibility preference
- Sidebar remains a visibility/render surface (`canShowModule`) and is not the fallback-chain contract owner.
- Preference parse/shape fallback for module visibility always defaults safely (`sidebarModules.ts`).
- Primary-module safety is enforced in both normalization and settings toggling:
  - normalization inserts `'today'` if no primary remains (`sidebarModules.ts:73-75`)
  - settings toggle blocks removing last primary (`settings/controller/general/actions.ts`)
- `daily_review` module semantics are explicitly user-facing as **Daily Review** (`nav.daily_review`) in sidebar and settings toggle surfaces.

## Repeatable Static Validation Path

Run these commands from repo root:

```bash
npm run verify:module-contract-matrix
npm run verify:ui-wiring
cd app && npx tsc --noEmit
```

Expected outcome:
- matrix rows remain complete for all registered modules
- sidebar/settings/render/fallback static wiring stays consistent
- app frontend typecheck remains clean
