import type { Task } from '@/lib/ipc/tasks/models';
import type { TranslationKey } from '@/lib/i18n';

/**
 * Formats a list's task plan as markdown text for clipboard copying.
 */
export function formatListPlan(
  listName: string,
  listIcon: string | null | undefined,
  openTasks: readonly Task[],
  completedTasks: readonly Task[],
  t: (key: TranslationKey) => string,
): string {
  const lines: string[] = [`${listIcon ? `${listIcon} ` : ''}${listName}\n`];
  if (openTasks.length > 0) {
    for (const task of openTasks) {
      const dur = task.estimated_minutes ? ` (${task.estimated_minutes}${t('common.min')})` : '';
      const pri = task.priority && task.priority <= 2 ? ` P${task.priority}` : '';
      lines.push(`- [ ] ${task.title}${dur}${pri}`);
    }
    lines.push('');
  }
  if (completedTasks.length > 0) {
    lines.push(`${t('list.recentlyCompleted')}:`);
    for (const task of completedTasks) {
      lines.push(`- [x] ${task.title}`);
    }
    lines.push('');
  }
  return lines.join('\n').trimEnd();
}
