import type { Task } from '@/lib/ipc/tasks/models';
import { parseIdList } from '@/components/dependency-graph/clustering';

export interface RelationGraphSnapshot {
  /** Owning task id (the task whose detail panel is open). */
  selfId: string;
  /** Map of task-id → list of task-ids it depends on. */
  dependsOn: Map<string, string[]>;
}

/**
 * Build a frozen dependency-graph snapshot from the current task list.
 * The snapshot is captured at picker-open time; subsequent keystroke
 * filtering reuses the same map without rebuilding.
 */
export function buildRelationGraphSnapshot(
  tasks: Task[],
  selfId: string,
): RelationGraphSnapshot {
  const dependsOn = new Map<string, string[]>();
  for (const task of tasks) {
    dependsOn.set(task.id, parseIdList(task.depends_on));
  }
  return { selfId, dependsOn };
}

/**
 * Returns `true` if `candidateId` already reaches `targetId` through
 * the snapshot's `dependsOn` graph. Used as the cycle test before
 * adding a new edge in either direction.
 *
 * Plain iterative DFS with a `visited` set — O(V+E) once per check,
 * which is what the picker needs to call per filtered row.
 */
function dependsOnReaches(
  snapshot: RelationGraphSnapshot,
  fromId: string,
  targetId: string,
): boolean {
  if (fromId === targetId) return true;
  const visited = new Set<string>();
  const stack: string[] = [fromId];
  while (stack.length > 0) {
    const current = stack.pop()!;
    if (visited.has(current)) continue;
    visited.add(current);
    const deps = snapshot.dependsOn.get(current);
    if (!deps) continue;
    for (const dep of deps) {
      if (dep === targetId) return true;
      if (!visited.has(dep)) stack.push(dep);
    }
  }
  return false;
}

/**
 * Decide whether adding the proposed edge would create a cycle.
 *
 *   - `pickerType = 'depends_on'` adds edge `self → candidate`
 *     (self depends on candidate). Cycle forms iff `candidate`
 *     already depends on `self`.
 *   - `pickerType = 'blocks'` adds edge `candidate → self`
 *     (candidate depends on self). Cycle forms iff `self` already
 *     depends on `candidate`.
 *
 * Self-edges (candidate === self) always count as cycles — the
 * picker already filters self out via `excludeIds`, but we treat it
 * defensively here so the predicate is total.
 */
export function wouldCreateCycle(
  snapshot: RelationGraphSnapshot,
  pickerType: 'depends_on' | 'blocks',
  candidateId: string,
): boolean {
  const { selfId } = snapshot;
  if (candidateId === selfId) return true;
  if (pickerType === 'depends_on') {
    return dependsOnReaches(snapshot, candidateId, selfId);
  }
  return dependsOnReaches(snapshot, selfId, candidateId);
}
