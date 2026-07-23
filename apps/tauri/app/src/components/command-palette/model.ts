import type { ReactNode } from 'react';

import type { TranslationKey } from '@/lib/i18n';
import { type ShortcutToken } from '@/lib/shortcuts';
import type { View } from '@/lib/types';
import {
  BoltIcon,
  CalendarDayIcon,
  CalendarUpcomingIcon,
  ChartIcon,
  ClipboardIcon,
  FlameIcon,
  GridIcon,
  KanbanIcon,
  LinkIcon,
  NotebookIcon,
  RecurrenceIcon,
  SparkleIcon,
  SunIcon,
  ThoughtBubbleIcon,
} from '../ui/icons';
import type { ResultItem } from './types';

export function resultIdentity(item: ResultItem): string {
  if (item.kind === 'task') return `task:${item.task.id}`;
  if (item.kind === 'nav') return `nav:${JSON.stringify(item.view)}`;
  return `action:${item.label}:${item.shortcut ?? ''}`;
}

export function getPaletteOptionId(key: string): string {
  return `command-palette-option-${key.replace(/[^a-zA-Z0-9_-]/g, '_')}`;
}

// command-palette hints mirror the canonical shortcut
// scheme documented at the top of `secondaryModules.tsx`. Keep this
// array in the same order the sidebar renders (primary first, then
// secondary in SECONDARY_MODULES order) so the palette feels
// consistent with the nav rail.
export const NAV_KEYS: Array<{
  labelKey: TranslationKey;
  icon: ReactNode;
  shortcut?: ShortcutToken[] | undefined;
  view: View;
}> = [
  // Primary ⌘1 – ⌘4
  { labelKey: 'nav.today', icon: SunIcon({}), shortcut: ['Mod', '1'], view: { type: 'today' } },
  { labelKey: 'nav.upcoming', icon: CalendarUpcomingIcon({}), shortcut: ['Mod', '2'], view: { type: 'upcoming' } },
  { labelKey: 'nav.allTasks', icon: ClipboardIcon({}), shortcut: ['Mod', '3'], view: { type: 'all_tasks' } },
  { labelKey: 'nav.someday', icon: ThoughtBubbleIcon({}), shortcut: ['Mod', '4'], view: { type: 'someday' } },
  // Secondary digit row ⌘5 – ⌘0
  { labelKey: 'nav.calendar', icon: CalendarDayIcon({}), shortcut: ['Mod', '5'], view: { type: 'calendar' } },
  { labelKey: 'nav.eisenhower', icon: GridIcon({}), shortcut: ['Mod', '6'], view: { type: 'eisenhower' } },
  { labelKey: 'nav.kanban', icon: KanbanIcon({}), shortcut: ['Mod', '7'], view: { type: 'kanban' } },
  { labelKey: 'nav.habits', icon: FlameIcon({}), shortcut: ['Mod', '8'], view: { type: 'habits' } },
  { labelKey: 'nav.daily_review', icon: NotebookIcon({}), shortcut: ['Mod', '0'], view: { type: 'daily_review' } },
  // Secondary ⌘⇧-letter row
  { labelKey: 'nav.memory', icon: SparkleIcon({}), shortcut: ['Mod', 'Shift', 'M'], view: { type: 'memory' } },
  { labelKey: 'nav.dependencies', icon: LinkIcon({}), shortcut: ['Mod', 'Shift', 'D'], view: { type: 'dependencies' } },
  { labelKey: 'nav.changelog', icon: BoltIcon({}), shortcut: ['Mod', 'Shift', 'A'], view: { type: 'ai_changelog' } },
  { labelKey: 'nav.review', icon: ChartIcon({}), shortcut: ['Mod', 'Shift', 'W'], view: { type: 'review' } },
  { labelKey: 'nav.recurring', icon: RecurrenceIcon({}), shortcut: ['Mod', 'Shift', 'R'], view: { type: 'recurring' } },
];

export function isListView(view: View): view is Extract<View, { type: 'list' }> {
  return view.type === 'list';
}
