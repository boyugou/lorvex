/**
 * Shared types used across multiple components.
 */

export type View =
  | { type: 'today' }
  | { type: 'list'; listId: string; rename?: boolean }
  | { type: 'ai_changelog' }
  | { type: 'someday' }
  | { type: 'upcoming' }
  | { type: 'all_tasks'; initialSearch?: string }
  | { type: 'memory' }
  | { type: 'settings'; sectionId?: string }
  | { type: 'review' }
  | { type: 'daily_review' }
  | { type: 'calendar' }
  | { type: 'eisenhower' }
  | { type: 'kanban' }
  | { type: 'dependencies' }
  | { type: 'habits' }
  | { type: 'recurring' };
