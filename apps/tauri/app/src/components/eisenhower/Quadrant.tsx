import { memo, useMemo } from 'react';
import type { Task } from '@/lib/ipc/tasks/models';
import { useI18n } from '../../lib/i18n';
import { isSpuriousDragLeave } from '../../lib/dragLeave';
import { shouldVirtualizeListView } from '../list-view/virtualization';
import { formatDurationCompact } from '../today-view/primitives';
import { DRAG_MIME, type QuadrantKey } from './quadrants';
import { EisenhowerTaskRow } from './EisenhowerTaskRow';
import { QuadrantList } from './QuadrantList';
import { EmptyQuadrant } from './EmptyQuadrant';

interface QuadrantProps {
  quadrantKey: QuadrantKey;
  title: string;
  hint: string;
  tasks: Task[];
  styleClass: string;
  onSelectTask?: ((taskId: string) => void) | undefined;
  isFocused: (taskId: string) => boolean;
  focusedTaskId: string | null;
  emptyLabel: string;
  dropHint: string;
  isDragOver: boolean;
  isBusy: boolean;
  onDragOverQuadrant: (quadrant: QuadrantKey | null) => void;
  onDrop: (quadrant: QuadrantKey, taskId: string) => void;
  isRecentlyDropped: (taskId: string) => boolean;
  hourUnit: string;
  minUnit: string;
}

/**
 * A single quadrant of the Eisenhower matrix: header (title + counts),
 * HTML5 drop target, and either an empty placeholder or the (possibly
 * virtualized) task list. Memoized so a `dragOverQuadrant` state tick
 * on the parent re-renders only the quadrant whose `isDragOver`
 * actually flipped.
 */
export const Quadrant = memo(function Quadrant({
  quadrantKey,
  title,
  hint,
  tasks,
  styleClass,
  onSelectTask,
  isFocused,
  focusedTaskId,
  emptyLabel,
  dropHint,
  isDragOver,
  isBusy,
  onDragOverQuadrant,
  onDrop,
  isRecentlyDropped,
  hourUnit,
  minUnit,
}: QuadrantProps) {
  const { formatNumber } = useI18n();
  // Pre-memoize per-quadrant total — parent re-renders that don't
  // change this quadrant's `tasks` reference skip the sum entirely.
  const estimatedMinutes = useMemo(
    () => tasks.reduce((sum, tk) => sum + (tk.estimated_minutes ?? 0), 0),
    [tasks],
  );
  return (
    // Drop zone for HTML5 drag-and-drop. The keyboard alternative is
    // documented on the draggable card (Ctrl/Cmd+Arrow chord, see
    // `aria-keyshortcuts` below); the drop target itself has no
    // user-action contract beyond receiving a drag, so a role + key
    // handler here would mis-describe the relationship.
    // eslint-disable-next-line jsx-a11y/no-static-element-interactions
    <section
      // Drag-over visual is standardized at `ring-2 ring-accent/50
      // bg-accent/5` across Eisenhower / Kanban / Upcoming / Calendar
      // (no scale on the parent column — only individual cards may
      // grow on hover, never the drop zone they live inside).
      // `min-h-[min(280px,30vh)]` lets the quadrant collapse to ~30%
      // of the viewport on short laptops (≤720px tall, common on 13"
      // panels with dock + menubar visible) while keeping a 280px
      // floor on taller screens. The `lg:auto-rows-fr` on the parent
      // grid makes both rows equal-height when there's room; this
      // relaxes only the per-cell minimum.
      className={`rounded-r-card border p-3 min-h-[min(280px,30vh)] flex flex-col transition-[box-shadow,background-color] ${styleClass} ${
        isDragOver ? 'ring-2 ring-accent/50 bg-accent/5' : ''
      }`}
      onDragOver={(event) => {
        if (isBusy) return;
        if (!event.dataTransfer.types.includes(DRAG_MIME)) return;
        event.preventDefault();
        event.dataTransfer.dropEffect = 'move';
        onDragOverQuadrant(quadrantKey);
      }}
      onDragLeave={(event) => {
        // use the shared spurious-leave guard so the
        // drag-over ring doesn't flicker when the cursor enters an
        // inner pill child or a portaled Tooltip whose relatedTarget
        // the browser reports as `null`.
        if (isSpuriousDragLeave(event)) return;
        onDragOverQuadrant(null);
      }}
      onDrop={(event) => {
        event.preventDefault();
        const taskId = event.dataTransfer.getData(DRAG_MIME);
        if (taskId) onDrop(quadrantKey, taskId);
      }}
    >
      <div className="mb-3">
        <div className="flex items-center justify-between gap-2">
          <h2 className="heading-section">{title}</h2>
          <div className="flex items-center gap-2 text-text-muted text-xs">
            {estimatedMinutes > 0 && (
              <span>{formatDurationCompact(estimatedMinutes, hourUnit, minUnit, formatNumber)}</span>
            )}
            <span>{formatNumber(tasks.length)}</span>
          </div>
        </div>
        <p className="text-text-muted text-xs mt-1">{hint}</p>
      </div>

      {tasks.length === 0 ? (
        <EmptyQuadrant
          quadrantKey={quadrantKey}
          isDragOver={isDragOver}
          emptyLabel={emptyLabel}
          dropHint={dropHint}
        />
      ) : shouldVirtualizeListView(tasks.length) ? (
        <QuadrantList
          tasks={tasks}
          isBusy={isBusy}
          isFocused={isFocused}
          focusedTaskId={focusedTaskId}
          isRecentlyDropped={isRecentlyDropped}
          onDragOverQuadrant={onDragOverQuadrant}
          onSelectTask={onSelectTask}
        />
      ) : (
        <div className="flex-1 min-h-0 overflow-y-auto overscroll-contain space-y-1.5">
          {tasks.map((task) => (
            <EisenhowerTaskRow
              key={task.id}
              task={task}
              isBusy={isBusy}
              focused={isFocused(task.id)}
              justDropped={isRecentlyDropped(task.id)}
              onDragOverQuadrant={onDragOverQuadrant}
              onSelectTask={onSelectTask}
            />
          ))}
        </div>
      )}
    </section>
  );
});
