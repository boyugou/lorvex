import { isTerminalStatus } from '@lorvex/shared/types';
import type { Task } from '@/lib/ipc/tasks/models';

export interface DepCluster {
  id: string;
  roots: Task[];
  layers: Task[][];
  taskCount: number;
  blockedCount: number;
  /** IDs of tasks involved in dependency cycles (could not be topologically sorted). */
  cyclicTaskIds: Set<string>;
}

export interface FilteredCluster {
  cluster: DepCluster;
  filteredLayers: Task[][];
}

export function parseIdList(ids: string[] | null): string[] {
  return ids ?? [];
}

export function isDependencyGraphTerminalTask(task: Pick<Task, 'status'>): boolean {
  return isTerminalStatus(task.status);
}

export function isDependencyGraphActiveTask(task: Pick<Task, 'status'>): boolean {
  return !isDependencyGraphTerminalTask(task);
}

export function buildClusters(tasks: Task[]): DepCluster[] {
  const taskMap = new Map<string, Task>();
  const dependsOnMap = new Map<string, string[]>();
  const blocksMap = new Map<string, string[]>();
  const hasDeps = new Set<string>();

  for (const task of tasks) {
    taskMap.set(task.id, task);
    const deps = parseIdList(task.depends_on);
    if (deps.length > 0) {
      hasDeps.add(task.id);
      dependsOnMap.set(task.id, deps);
      for (const dep of deps) hasDeps.add(dep);
    }
  }

  // Build blocksMap by inverting dependsOnMap
  for (const [taskId, deps] of dependsOnMap) {
    for (const dep of deps) {
      const existing = blocksMap.get(dep) || [];
      existing.push(taskId);
      blocksMap.set(dep, existing);
    }
  }

  // Build adjacency for connected components
  const adjMap = new Map<string, Set<string>>();
  for (const id of hasDeps) {
    if (!adjMap.has(id)) adjMap.set(id, new Set());
  }
  for (const [id, deps] of dependsOnMap) {
    for (const dep of deps) {
      adjMap.get(id)?.add(dep);
      if (!adjMap.has(dep)) adjMap.set(dep, new Set());
      adjMap.get(dep)?.add(id);
    }
  }

  // Find connected components
  const visited = new Set<string>();
  const components: string[][] = [];
  for (const id of hasDeps) {
    if (visited.has(id)) continue;
    const component: string[] = [];
    const stack = [id];
    while (stack.length > 0) {
      const current = stack.pop()!;
      if (visited.has(current)) continue;
      visited.add(current);
      component.push(current);
      for (const neighbor of adjMap.get(current) ?? []) {
        if (!visited.has(neighbor)) stack.push(neighbor);
      }
    }
    components.push(component);
  }

  // For each component, do topological layering
  return components
    .map((component, idx) => {
      const componentSet = new Set(component);
      const inDegree = new Map<string, number>();
      const children = new Map<string, string[]>();

      for (const id of component) {
        inDegree.set(id, 0);
        children.set(id, []);
      }

      // Build directed edges from dependsOnMap only.
      for (const id of component) {
        for (const dep of dependsOnMap.get(id) ?? []) {
          if (componentSet.has(dep)) {
            children.get(dep)?.push(id);
            inDegree.set(id, (inDegree.get(id) ?? 0) + 1);
          }
        }
      }

      // Topological sort into layers (Kahn's algorithm)
      const layers: Task[][] = [];
      let currentLayer = component
        .filter((id) => (inDegree.get(id) ?? 0) === 0)
        .map((id) => taskMap.get(id))
        .filter((t): t is Task => t !== undefined);

      const processed = new Set<string>();
      while (currentLayer.length > 0) {
        layers.push(currentLayer);
        const nextIds: string[] = [];
        for (const task of currentLayer) {
          processed.add(task.id);
          for (const child of children.get(task.id) ?? []) {
            const newDeg = (inDegree.get(child) ?? 1) - 1;
            inDegree.set(child, newDeg);
            if (newDeg === 0 && !processed.has(child)) nextIds.push(child);
          }
        }
        currentLayer = nextIds
          .map((id) => taskMap.get(id))
          .filter((t): t is Task => t !== undefined);
      }

      // Handle cycles: tasks that Kahn's algorithm couldn't process are in dependency cycles.
      const remaining = component
        .filter((id) => !processed.has(id))
        .map((id) => taskMap.get(id))
        .filter((t): t is Task => t !== undefined);
      if (remaining.length > 0) layers.push(remaining);
      const cyclicTaskIds = new Set(remaining.map((t) => t.id));

      const roots = layers[0] ?? [];
      const allTasks = layers.flat();
      const terminalIds = new Set(allTasks.filter(isDependencyGraphTerminalTask).map((t) => t.id));
      const blockedCount = allTasks.filter((t) => {
        if (!isDependencyGraphActiveTask(t)) return false;
        const deps = dependsOnMap.get(t.id) ?? [];
        return deps.some((dep) => componentSet.has(dep) && !terminalIds.has(dep));
      }).length;

      return {
        id: `cluster-${idx}`,
        roots,
        layers,
        taskCount: allTasks.length,
        blockedCount,
        cyclicTaskIds,
      };
    })
    .sort((a, b) => b.blockedCount - a.blockedCount || b.taskCount - a.taskCount);
}
