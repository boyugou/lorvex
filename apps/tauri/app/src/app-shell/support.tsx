import {
  DEV_ASSISTANT_UI_COMMAND,
  DEV_ASSISTANT_UI_COMMAND_HANDLED_ID,
} from '../lib/preferences/keys';
import type { SidebarModule } from '../lib/sidebarModules';
import type { View } from '../lib/types';

export const ASSISTANT_UI_COMMAND_KEY = DEV_ASSISTANT_UI_COMMAND;
export const ASSISTANT_UI_HANDLED_ID_KEY = DEV_ASSISTANT_UI_COMMAND_HANDLED_ID;

export function areViewsEqual(left: View, right: View): boolean {
  if (left.type !== right.type) return false;
  if (left.type === 'list' && right.type === 'list') {
    return left.listId === right.listId && !right.rename;
  }
  if (left.type === 'all_tasks' && right.type === 'all_tasks') {
    return left.initialSearch === right.initialSearch;
  }
  if (left.type === 'settings' && right.type === 'settings') {
    return left.sectionId === right.sectionId;
  }
  return true;
}

/**
 * Exhaustive mapping from non-list view types to sidebar modules.
 * If a new view type is added to the View union without updating this record,
 * TypeScript will report a compile error on the `satisfies` clause.
 */
const SIDEBAR_MODULE_MAP: Record<Exclude<View['type'], 'list'>, SidebarModule | null> = {
  today: 'today',
  upcoming: 'upcoming',
  all_tasks: 'all_tasks',
  someday: 'someday',
  calendar: 'calendar',
  eisenhower: 'eisenhower',
  kanban: 'kanban',
  daily_review: 'daily_review',
  memory: 'memory',
  review: 'review',
  ai_changelog: 'ai_changelog',
  settings: null,
  dependencies: 'dependencies',
  habits: 'habits',
  recurring: 'recurring',
} satisfies Record<Exclude<View['type'], 'list'>, SidebarModule | null>;

export function mapViewToSidebarModule(view: View): SidebarModule | null {
  if (view.type === 'list') return null;
  return SIDEBAR_MODULE_MAP[view.type];
}

export function ViewLoadingFallback() {
  return (
    <div className="h-full flex flex-col gap-4 p-6 animate-pulse">
      <div className="h-6 w-48 rounded-r-control bg-surface-2" />
      <div className="h-4 w-full rounded-r-control bg-surface-2" />
      <div className="h-4 w-3/4 rounded-r-control bg-surface-2" />
      <div className="h-4 w-5/6 rounded-r-control bg-surface-2" />
    </div>
  );
}
