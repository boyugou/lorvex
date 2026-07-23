import { type ReactNode } from 'react';

import type { TranslationKey } from '@/lib/i18n';
import type { SidebarModule } from '@/lib/sidebarModules';
import type { View } from '@/lib/types';
import {
  BoltIcon,
  CalendarDayIcon,
  ChartIcon,
  FlameIcon,
  GridIcon,
  KanbanIcon,
  LinkIcon,
  NotebookIcon,
  RecurrenceIcon,
  SparkleIcon,
} from '../ui/icons';

import NavItem from './NavItem';

// ── Module keyboard-shortcut scheme ─────────────────────
//
// Before only a ragged subset of navigable views had ⌘-shortcuts;
// habits, memory, daily_review, and dependencies had none.
// The scheme below makes the mapping derivable and covers every
// permanent destination:
//
//   Primary (always-visible in PrimaryNav)  →  ⌘1 – ⌘4
//     ⌘1 Today   ⌘2 Upcoming   ⌘3 All Tasks   ⌘4 Someday
//
//   Secondary (module drawer), ⌘5 – ⌘0 in the exact order declared
//   in SECONDARY_MODULES below. The digit order is load-bearing — it
//   is rendered in the sidebar and documented in
//   KeyboardShortcutsPanel. Changing the order changes user-facing
//   shortcuts; run PR review before reshuffling.
//
//     ⌘5 Calendar   ⌘6 Eisenhower   ⌘7 Kanban
//     ⌘8 Habits     ⌘9 Daily Review
//
//   The remaining secondaries use ⌘⇧-letter combos so they still have
//   a keyboard path without crowding the digit row:
//     ⌘⇧M Memory   ⌘⇧D Dependencies
//     ⌘⇧A AI Changelog   ⌘⇧W Weekly Review
// ⌘⇧R Recurring tasks
//
// Settings keeps its platform-idiomatic binding (⌘, on macOS, ⌘; on
// Windows). The accelerators live in `app_menu.rs`; this file only
// advertises them to the sidebar UI and the shortcut reference panel.

// ── Secondary module definitions (single source of truth) ──────────────

interface SecondaryModuleDef {
  module: SidebarModule;
  icon: ReactNode;
  label: TranslationKey;
  /** one-line tooltip describing the view. Surfaced via
   *  NavItem's \`title\` attribute alongside the label. */
  description?: TranslationKey;
  /** View type string for active check and navigation. */
  viewType?: View['type'];
  /** Key into navShortcuts. Omit if no keyboard shortcut. */
  shortcutKey?: string;
  /** Whether the module requires desktop features. Default true. */
  desktopOnly?: boolean;
  /**
   * the module is populated by the AI assistant via MCP
   * (habits, daily_review, memory, ai_changelog). Standalone users
   * without a connected assistant land on an empty view and have no
   * way to seed it from the UI. When true, the sidebar NavItem tooltip
   * appends a "Requires AI assistant" hint so the intended workflow is
   * discoverable even when the view renders empty.
   */
  requiresAi?: boolean;
}

export const SECONDARY_MODULES: SecondaryModuleDef[] = [
  // Digit row ⌘5 – ⌘0 (order = assignment; see header doc above)
  { module: 'calendar',     icon: <CalendarDayIcon />,  label: 'nav.calendar',     description: 'nav.calendar.desc',     viewType: 'calendar',     shortcutKey: 'calendar' },
  { module: 'eisenhower',   icon: <GridIcon />,         label: 'nav.eisenhower',   description: 'nav.eisenhower.desc',   viewType: 'eisenhower',   shortcutKey: 'eisenhower' },
  { module: 'kanban',       icon: <KanbanIcon />,       label: 'nav.kanban',       description: 'nav.kanban.desc',       viewType: 'kanban',       shortcutKey: 'kanban' },
  { module: 'habits',       icon: <FlameIcon />,        label: 'nav.habits',       description: 'nav.habits.desc',       viewType: 'habits',       shortcutKey: 'habits',       desktopOnly: false, requiresAi: true },
  { module: 'daily_review', icon: <NotebookIcon />,     label: 'nav.daily_review', description: 'nav.daily_review.desc', viewType: 'daily_review', shortcutKey: 'dailyReview', requiresAi: true },
  // ⌘⇧-letter row
  { module: 'memory',       icon: <SparkleIcon />,      label: 'nav.memory',       description: 'nav.memory.desc',       viewType: 'memory',       shortcutKey: 'memory', requiresAi: true },
  { module: 'dependencies', icon: <LinkIcon />,         label: 'nav.dependencies', description: 'nav.dependencies.desc', viewType: 'dependencies', shortcutKey: 'dependencies' },
  { module: 'ai_changelog', icon: <BoltIcon />,         label: 'nav.changelog',    description: 'nav.changelog.desc',    viewType: 'ai_changelog', shortcutKey: 'changelog', requiresAi: true },
  { module: 'review',       icon: <ChartIcon />,        label: 'nav.review',       description: 'nav.review.desc',       viewType: 'review',       shortcutKey: 'review' },
  { module: 'recurring',    icon: <RecurrenceIcon />,   label: 'nav.recurring',    description: 'nav.recurring.desc',    viewType: 'recurring',    shortcutKey: 'recurring' },
];

interface RenderSecondaryModulesParams {
  modules: SecondaryModuleDef[];
  filter: (def: SecondaryModuleDef) => boolean;
  showDesktopFeatures: boolean;
  currentView: View;
  onNavigate: (view: View) => void;
  navShortcuts: Record<string, string | undefined>;
  t: (key: TranslationKey) => string;
}

/** Render a filtered subset of secondary modules as NavItem elements. */
export function renderSecondaryModules({
  modules,
  filter,
  showDesktopFeatures,
  currentView,
  onNavigate,
  navShortcuts,
  t,
}: RenderSecondaryModulesParams): ReactNode[] {
  const items: ReactNode[] = [];

  for (const def of modules) {
    const desktopOnly = def.desktopOnly !== false;
    if (desktopOnly && !showDesktopFeatures) continue;
    if (!filter(def)) continue;

    // surface the AI-assistant requirement in the
    // NavItem tooltip so standalone users understand why the view
    // renders empty without an MCP connection.
    const baseDescription = def.description ? t(def.description) : undefined;
    const description = def.requiresAi
      ? [baseDescription, t('nav.requiresAiHint')].filter(Boolean).join(' · ')
      : baseDescription;
    if (!def.viewType) continue;
    items.push(
      <NavItem
        key={def.module}
        label={t(def.label)}
        description={description}
        icon={def.icon}
        shortcut={def.shortcutKey ? navShortcuts[def.shortcutKey] : undefined}
        active={currentView.type === def.viewType}
        onClick={() => onNavigate({ type: def.viewType } as View)}
      />,
    );
  }

  return items;
}
