import type { ListWithCount, Task } from '@/lib/ipc/tasks/models';
import { parseTags } from '@/lib/format';
import type { useI18n } from '@/lib/i18n';

export type SomedaySortKey = 'newest' | 'oldest' | 'priority' | 'actionDate';
export const SORT_KEYS: SomedaySortKey[] = ['newest', 'oldest', 'priority', 'actionDate'];

export type GroupBy = 'none' | 'list' | 'priority' | 'tag';
export const GROUP_BY_KEYS: GroupBy[] = ['none', 'list', 'priority', 'tag'];

export interface SomedaySection {
  key: string;
  title: string;
  tasks: Task[];
}

export function sortSomedayTasks(tasks: Task[], key: SomedaySortKey): Task[] {
  const sorted = [...tasks];
  switch (key) {
    case 'newest':
      return sorted.sort((a, b) => b.created_at.localeCompare(a.created_at));
    case 'oldest':
      return sorted.sort((a, b) => a.created_at.localeCompare(b.created_at));
    case 'priority':
      return sorted.sort((a, b) => (a.priority ?? 99) - (b.priority ?? 99));
    case 'actionDate':
      return sorted.sort((a, b) => {
        const aDate = a.planned_date ?? a.due_date ?? '9999-12-31';
        const bDate = b.planned_date ?? b.due_date ?? '9999-12-31';
        const dateDiff = aDate.localeCompare(bDate);
        if (dateDiff !== 0) return dateDiff;
        return (a.priority ?? 99) - (b.priority ?? 99);
      });
    default:
      return sorted;
  }
}

export function buildListSections(
  tasks: Task[],
  lists: ListWithCount[],
  sortKey: SomedaySortKey,
): SomedaySection[] {
  const listMap = new Map<string, { name: string; icon: string | null; tasks: Task[] }>();
  for (const task of tasks) {
    const listId = task.list_id;
    if (!listId) {
      continue;
    }
    const list = lists.find((l) => l.id === listId);
    if (!list) {
      continue;
    }
    const entry = listMap.get(listId);
    if (entry) {
      entry.tasks.push(task);
    } else {
      listMap.set(listId, {
        name: list.name,
        icon: list.icon ?? null,
        tasks: [task],
      });
    }
  }
  const sections: SomedaySection[] = [];
  for (const [listId, entry] of listMap) {
    const label = entry.icon ? `${entry.icon} ${entry.name}` : entry.name;
    sections.push({
      key: `list-${listId ?? 'none'}`,
      title: label,
      tasks: sortSomedayTasks(entry.tasks, sortKey),
    });
  }
  return sections;
}

export function buildPrioritySections(
  tasks: Task[],
  sortKey: SomedaySortKey,
  t: ReturnType<typeof useI18n>['t'],
): SomedaySection[] {
  const p1: Task[] = [], p2: Task[] = [], p3: Task[] = [], noPri: Task[] = [];
  for (const task of tasks) {
    const p = task.priority;
    if (p === 1) p1.push(task);
    else if (p === 2) p2.push(task);
    else if (p === 3) p3.push(task);
    else noPri.push(task);
  }

  const sectionDefs: Array<{ key: string; titleKey: string; tasks: Task[] }> = [
    { key: 'p1', titleKey: 'allTasks.groupP1', tasks: p1 },
    { key: 'p2', titleKey: 'allTasks.groupP2', tasks: p2 },
    { key: 'p3', titleKey: 'allTasks.groupP3', tasks: p3 },
    { key: 'none', titleKey: 'allTasks.groupNoPriority', tasks: noPri },
  ];

  return sectionDefs
    .filter((s) => s.tasks.length > 0)
    .map((s) => ({
      key: `priority-${s.key}`,
      title: t(s.titleKey as Parameters<typeof t>[0]),
      tasks: sortSomedayTasks(s.tasks, sortKey),
    }));
}

export function buildTagSections(
  tasks: Task[],
  sortKey: SomedaySortKey,
  t: ReturnType<typeof useI18n>['t'],
): SomedaySection[] {
  const tagBuckets = new Map<string, Task[]>();
  const noTagTasks: Task[] = [];
  for (const task of tasks) {
    const taskTags = parseTags(task.tags);
    if (taskTags.length === 0) {
      noTagTasks.push(task);
    } else {
      for (const tag of taskTags) {
        const bucket = tagBuckets.get(tag);
        if (bucket) bucket.push(task);
        else tagBuckets.set(tag, [task]);
      }
    }
  }
  const sections: SomedaySection[] = [];
  for (const [tag, tagTasks] of [...tagBuckets.entries()].sort(([a], [b]) => a.localeCompare(b))) {
    sections.push({ key: `tag-${tag}`, title: tag, tasks: sortSomedayTasks(tagTasks, sortKey) });
  }
  if (noTagTasks.length > 0) {
    sections.push({ key: 'tag-none', title: t('allTasks.groupNoTag'), tasks: sortSomedayTasks(noTagTasks, sortKey) });
  }
  return sections;
}
