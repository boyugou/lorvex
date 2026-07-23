import type { ListWithCount, Task } from '@/lib/ipc/tasks/models';

function buildKnownListIdSet(lists: readonly ListWithCount[]): Set<string> {
  return new Set(lists.map((list) => list.id));
}

function isTaskListRepairState(
  task: Pick<Task, 'list_id'>,
  knownListIds?: ReadonlySet<string>,
): boolean {
  // list_id is NOT NULL (schema-enforced), so no null check needed.
  return knownListIds ? !knownListIds.has(task.list_id) : false;
}

interface TaskListGroupingMeta {
  id: string;
  name: string;
  icon: string | null;
}

interface TaskListSection<TTask> {
  key: string;
  title: string;
  tasks: TTask[];
}

export function partitionTasksByListOwnership(
  tasks: Task[],
  lists?: readonly ListWithCount[] | null,
): { authoredTasks: Task[]; repairTasks: Task[] } {
  if (!lists) {
    // Fail open while the list inventory is still loading: otherwise a
    // cold All Tasks mount briefly classifies every task as "repair"
    // because the known-list set is empty, which hides the whole task
    // corpus until the lists query resolves.
    return { authoredTasks: [...tasks], repairTasks: [] };
  }
  const knownListIds = buildKnownListIdSet(lists);
  const authoredTasks: Task[] = [];
  const repairTasks: Task[] = [];
  for (const task of tasks) {
    if (isTaskListRepairState(task, knownListIds)) {
      repairTasks.push(task);
    } else {
      authoredTasks.push(task);
    }
  }
  return { authoredTasks, repairTasks };
}

export function resolveTaskListGroupingMeta(
  task: Pick<Task, 'list_id'>,
  lists?: readonly ListWithCount[] | null,
): TaskListGroupingMeta | null {
  if (!task.list_id) {
    return null;
  }
  if (!lists) {
    return {
      id: task.list_id,
      name: task.list_id,
      icon: null,
    };
  }
  const list = lists.find((candidate) => candidate.id === task.list_id);
  if (!list) {
    return null;
  }
  return {
    id: list.id,
    name: list.name,
    icon: list.icon ?? null,
  };
}

export function buildListGroupedTaskSections<TTask extends Pick<Task, 'list_id'>>(
  tasks: readonly TTask[],
  lists: readonly ListWithCount[] | null | undefined,
  options: {
    loadingLabel: string;
    sortTasks: (tasks: TTask[]) => TTask[];
  },
): TaskListSection<TTask>[] {
  if (!lists) {
    return tasks.length > 0
      ? [{
        key: 'list-loading',
        title: options.loadingLabel,
        tasks: options.sortTasks([...tasks]),
      }]
      : [];
  }

  const listMap = new Map<string, { name: string; icon: string | null; tasks: TTask[] }>();
  for (const task of tasks) {
    const listMeta = resolveTaskListGroupingMeta(task, lists);
    if (!listMeta) continue;
    const entry = listMap.get(listMeta.id);
    if (entry) {
      entry.tasks.push(task);
    } else {
      listMap.set(listMeta.id, {
        name: listMeta.name,
        icon: listMeta.icon,
        tasks: [task],
      });
    }
  }

  const sections: TaskListSection<TTask>[] = [];
  for (const [listId, entry] of listMap) {
    const label = entry.icon ? `${entry.icon} ${entry.name}` : entry.name;
    sections.push({
      key: `list-${listId}`,
      title: label,
      tasks: options.sortTasks(entry.tasks),
    });
  }
  return sections;
}
