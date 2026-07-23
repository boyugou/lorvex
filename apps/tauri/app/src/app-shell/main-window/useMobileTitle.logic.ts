import type { TranslationKey } from '@/lib/i18n';
import type { View } from '@/lib/types';

type MobileTitleViewType = Exclude<View['type'], 'list'>;

export const MOBILE_TITLE_KEYS: Record<MobileTitleViewType, TranslationKey> = {
  today: 'nav.today',
  upcoming: 'nav.upcoming',
  all_tasks: 'nav.allTasks',
  someday: 'nav.someday',
  ai_changelog: 'nav.changelog',
  memory: 'nav.memory',
  calendar: 'nav.calendar',
  eisenhower: 'nav.eisenhower',
  kanban: 'nav.kanban',
  review: 'nav.review',
  daily_review: 'nav.daily_review',
  settings: 'nav.settings',
  dependencies: 'nav.dependencies',
  habits: 'nav.habits',
  recurring: 'nav.recurring',
};

export function resolveMobileTitleKey(viewType: MobileTitleViewType): TranslationKey {
  return MOBILE_TITLE_KEYS[viewType];
}
