import type { ScheduleBlock } from '@/lib/ipc/tasks/models';
import { parseTimeToMinutes } from '@/lib/timeUtils';

export function minutesBetween(start: string, end: string): number {
  const startMinutes = parseTimeToMinutes(start);
  const endMinutes = parseTimeToMinutes(end);
  if (startMinutes == null || endMinutes == null) return 0;
  return endMinutes - startMinutes;
}

/**
 * Swap a task block with the adjacent task block in the given direction.
 * Swaps only the task_id fields so time slots remain stable.
 */
export function moveTaskInBlocks(
  blocks: ScheduleBlock[],
  taskId: string,
  direction: 'up' | 'down',
): ScheduleBlock[] {
  const taskIndices = blocks
    .map((b, i) => (b.block_type === 'task' ? i : -1))
    .filter((i) => i !== -1);
  const pos = taskIndices.findIndex((i) => blocks[i]!.task_id === taskId);
  if (pos === -1) return blocks;

  const swapPos = direction === 'up' ? pos - 1 : pos + 1;
  if (swapPos < 0 || swapPos >= taskIndices.length) return blocks;

  const result = blocks.map((b) => ({ ...b }));
  const idxA = taskIndices[pos]!;
  const idxB = taskIndices[swapPos]!;
  const taskIdA = result[idxA]!.task_id;
  const taskIdB = result[idxB]!.task_id;
  if (!taskIdA || !taskIdB) {
    return blocks;
  }
  result[idxA]!.task_id = taskIdB;
  result[idxB]!.task_id = taskIdA;
  return result;
}

/** Remove a task block and its adjacent buffer from the blocks array. */
export function removeTaskFromBlocks(
  blocks: ScheduleBlock[],
  taskId: string,
): ScheduleBlock[] {
  const idx = blocks.findIndex((b) => b.block_type === 'task' && b.task_id === taskId);
  if (idx === -1) return blocks;

  const result = [...blocks];
  result.splice(idx, 1);

  // Remove adjacent buffer (prefer the one after, fall back to before)
  if (idx < result.length && result[idx]?.block_type === 'buffer') {
    result.splice(idx, 1);
  } else if (idx > 0 && result[idx - 1]?.block_type === 'buffer') {
    result.splice(idx - 1, 1);
  }

  return result;
}
