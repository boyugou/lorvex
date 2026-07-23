interface TaskListActionElement {
  dispatchEvent: (event: Event) => boolean;
}

export interface TaskListActionHost {
  createEvent: (eventName: string) => Event;
  findTaskElement: (taskId: string) => TaskListActionElement | null;
}

function escapeTaskListActionTaskIdSelectorValue(taskId: string): string {
  return taskId.replace(/\\/g, '\\\\').replace(/"/g, '\\"');
}

export function createBrowserTaskListActionHost(): TaskListActionHost {
  return {
    createEvent: (eventName) => new CustomEvent(eventName),
    findTaskElement: typeof document === 'undefined'
      ? () => null
      : (taskId) => document.querySelector(
          `[data-task-id="${escapeTaskListActionTaskIdSelectorValue(taskId)}"]`,
        ) as TaskListActionElement | null,
  };
}

export function dispatchTaskListElementEvent({
  eventName,
  host,
  taskId,
}: {
  eventName: string;
  host: TaskListActionHost;
  taskId: string;
}): boolean {
  const element = host.findTaskElement(taskId);
  if (!element) return false;
  element.dispatchEvent(host.createEvent(eventName));
  return true;
}
