import type { Task } from '@/lib/ipc/tasks/models';
import { useVirtualizedTaskColumn } from '../list-view/virtualization';
import { EisenhowerTaskRow } from './EisenhowerTaskRow';
import type { QuadrantKey } from './quadrants';

/**
 * Virtualized per-quadrant rail for large Eisenhower quadrants.
 * Mirrors the Kanban/ListView pattern — owns the scroll element inside
 * the quadrant body, windows rows via `@tanstack/react-virtual`, and
 * keeps the keyboard-focused card in view by mapping the focus id back
 * to its index and calling `scrollToIndex` on change.
 */
export function QuadrantList({
  tasks,
  isBusy,
  isFocused,
  focusedTaskId,
  isRecentlyDropped,
  onDragOverQuadrant,
  onSelectTask,
}: {
  tasks: Task[];
  isBusy: boolean;
  isFocused: (taskId: string) => boolean;
  focusedTaskId: string | null;
  isRecentlyDropped: (taskId: string) => boolean;
  onDragOverQuadrant: (quadrant: QuadrantKey | null) => void;
  onSelectTask?: ((taskId: string) => void) | undefined;
}) {
  // Virtualizer setup + scroll-to-focused effect lift to the shared
  // `useVirtualizedTaskColumn` hook so any tuning stays applied to
  // both this and the Kanban column virtualizer in lockstep.
  const { scrollRef, virtualItems, totalSize, measureElement } =
    useVirtualizedTaskColumn(tasks, focusedTaskId);

  return (
    <div ref={scrollRef} className="flex-1 min-h-0 overflow-y-auto overscroll-contain">
      <div className="relative w-full" style={{ height: `${totalSize}px` }}>
        {virtualItems.map((vItem) => {
          const task = tasks[vItem.index];
          if (!task) return null;
          return (
            <div
              key={vItem.key}
              data-index={vItem.index}
              ref={measureElement}
              style={{
                position: 'absolute',
                top: 0,
                left: 0,
                width: '100%',
                transform: `translateY(${vItem.start}px)`,
              }}
            >
              <div className="py-0.5">
                <EisenhowerTaskRow
                  task={task}
                  isBusy={isBusy}
                  focused={isFocused(task.id)}
                  justDropped={isRecentlyDropped(task.id)}
                  onDragOverQuadrant={onDragOverQuadrant}
                  onSelectTask={onSelectTask}
                />
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
}
