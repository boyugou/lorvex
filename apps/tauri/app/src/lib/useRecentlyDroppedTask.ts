import { useCallback, useEffect, useRef, useState } from 'react';

/**
 * tracks the most-recently-dropped task across any
 * drop surface (Eisenhower quadrants, Kanban columns, Calendar week
 * cells) so the just-moved card can render a FLIP-style settle
 * animation + a brief accent afterglow ring.
 *
 * Usage:
 *
 *   const drop = useRecentlyDroppedTask();
 *   // … on successful drop:
 *   drop.markDropped(taskId);
 *   // … in render:
 *   <TaskCard className={drop.isRecent(task.id) ? 'animate-drop-settle' : ''}/>
 *
 * The marker auto-clears after `holdMs` (default 700 ms) so the
 * decoration is purely transient — no consumer cleanup required.
 * Re-marking the same id resets the timer.
 *
 * Reduced motion: the global `*` reset in `accessibility.css` collapses
 * `animate-*` to instant, so the moved card simply lands in its final
 * position with no settle. The marker still fires so consumers can
 * branch on it (e.g. to suppress an afterglow ring under reduced
 * motion) if needed.
 */
export function useRecentlyDroppedTask(holdMs = 700) {
  const [droppedId, setDroppedId] = useState<string | null>(null);
  const timeoutRef = useRef<number | null>(null);

  useEffect(() => {
    return () => {
      if (timeoutRef.current !== null) {
        window.clearTimeout(timeoutRef.current);
      }
    };
  }, []);

  const markDropped = useCallback((taskId: string) => {
    if (timeoutRef.current !== null) {
      window.clearTimeout(timeoutRef.current);
    }
    setDroppedId(taskId);
    timeoutRef.current = window.setTimeout(() => {
      setDroppedId(null);
      timeoutRef.current = null;
    }, holdMs);
  }, [holdMs]);

  const isRecent = useCallback(
    (taskId: string) => droppedId === taskId,
    [droppedId],
  );

  return { droppedId, markDropped, isRecent };
}
