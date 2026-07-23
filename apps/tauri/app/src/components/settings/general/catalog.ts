import type { SidebarModule } from '@/lib/sidebarModules';
import type { TranslationKey } from '@/locales';

export const WEEKLY_REVIEW_DAY_OPTIONS: Array<{ value: string; labelKey: TranslationKey }> = [
  { value: 'monday', labelKey: 'settings.weekday.monday' },
  { value: 'tuesday', labelKey: 'settings.weekday.tuesday' },
  { value: 'wednesday', labelKey: 'settings.weekday.wednesday' },
  { value: 'thursday', labelKey: 'settings.weekday.thursday' },
  { value: 'friday', labelKey: 'settings.weekday.friday' },
  { value: 'saturday', labelKey: 'settings.weekday.saturday' },
  { value: 'sunday', labelKey: 'settings.weekday.sunday' },
];

export const SIDEBAR_MODULE_OPTIONS: Array<{
  id: SidebarModule;
  labelKey: TranslationKey;
  section: 'primary' | 'secondary';
}> = [
  { id: 'today', labelKey: 'nav.today', section: 'primary' },
  { id: 'upcoming', labelKey: 'nav.upcoming', section: 'primary' },
  { id: 'all_tasks', labelKey: 'nav.allTasks', section: 'primary' },
  { id: 'someday', labelKey: 'nav.someday', section: 'primary' },
  { id: 'calendar', labelKey: 'nav.calendar', section: 'secondary' },
  { id: 'eisenhower', labelKey: 'nav.eisenhower', section: 'secondary' },
  { id: 'kanban', labelKey: 'nav.kanban', section: 'secondary' },
  { id: 'dependencies', labelKey: 'nav.dependencies', section: 'secondary' },
  { id: 'habits', labelKey: 'nav.habits', section: 'secondary' },
  { id: 'daily_review', labelKey: 'nav.daily_review', section: 'secondary' },
  { id: 'memory', labelKey: 'nav.memory', section: 'secondary' },
  { id: 'review', labelKey: 'nav.review', section: 'secondary' },
  { id: 'recurring', labelKey: 'nav.recurring', section: 'secondary' },
  { id: 'ai_changelog', labelKey: 'nav.changelog', section: 'secondary' },
  { id: 'focus', labelKey: 'today.focus', section: 'secondary' },
];

export const DESKTOP_CLOSE_ACTION_OPTIONS: Array<{
  value: 'quit' | 'hide_to_tray';
  labelKey: TranslationKey;
}> = [
  { value: 'hide_to_tray', labelKey: 'settings.desktopCloseActionHideToTray' },
  { value: 'quit', labelKey: 'settings.desktopCloseActionQuit' },
];
