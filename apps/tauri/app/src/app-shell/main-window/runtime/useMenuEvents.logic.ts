import type { View } from '@/lib/types';

export const MENU_VIEW_TYPE_MAP = {
  today: { type: 'today' },
  upcoming: { type: 'upcoming' },
  all: { type: 'all_tasks' },
  someday: { type: 'someday' },
  calendar: { type: 'calendar' },
  eisenhower: { type: 'eisenhower' },
  kanban: { type: 'kanban' },
  habits: { type: 'habits' },
  daily_review: { type: 'daily_review' },
  memory: { type: 'memory' },
  dependencies: { type: 'dependencies' },
  ai_changelog: { type: 'ai_changelog' },
  review: { type: 'review' },
  recurring: { type: 'recurring' },
  settings: { type: 'settings' },
} satisfies Record<string, View>;

type MenuViewType = keyof typeof MENU_VIEW_TYPE_MAP;
const SETTINGS_DATA_SECTION_ID = 'settings-section-data';

export function resolveMenuView(viewType: string): View | null {
  return MENU_VIEW_TYPE_MAP[viewType as MenuViewType] ?? null;
}

export function resolveMenuDataView(): View {
  return { type: 'settings', sectionId: SETTINGS_DATA_SECTION_ID };
}
