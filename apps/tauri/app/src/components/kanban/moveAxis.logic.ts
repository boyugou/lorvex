export type TaskMoveAxis = 'horizontal' | 'vertical';

export function isKanbanMoveAxisHandled(axis?: TaskMoveAxis): boolean {
  return axis !== 'vertical';
}
