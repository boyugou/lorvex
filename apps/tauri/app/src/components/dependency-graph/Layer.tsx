import type { Task } from '@/lib/ipc/tasks/models';
import type { TranslationKey } from '@/lib/i18n';
import TaskCard from '../task-card/TaskCard';
import { SwipeableTaskCard } from '../task-card/SwipeableTaskCard';
import { isDependencyGraphActiveTask, isDependencyGraphTerminalTask } from './clustering';

/**
 * One layer of a dependency cluster: the tasks at a given depth in the
 * blocked-by chain, plus the "depends on" arrow header that introduces
 * deeper layers. Cyclic layers render a warning header instead and skip
 * the indentation rail (the cycle has no canonical "above" task).
 */
export function Layer({
  layer,
  layerIdx,
  cyclicTaskIds,
  allDepsMap,
  taskMap,
  clusterIds,
  isFocused,
  onSelectTask,
  t,
}: {
  layer: Task[];
  layerIdx: number;
  cyclicTaskIds: Set<string>;
  allDepsMap: Map<string, string[]>;
  taskMap: Map<string, Task>;
  clusterIds: Set<string>;
  isFocused: (taskId: string) => boolean;
  onSelectTask?: ((taskId: string) => void) | undefined;
  t: (key: TranslationKey) => string;
}) {
  const isCyclicLayer = layer.some((task) => cyclicTaskIds.has(task.id));
  const terminalIds = new Set(
    [...clusterIds].filter((id) => {
      const task = taskMap.get(id);
      return task ? isDependencyGraphTerminalTask(task) : false;
    }),
  );

  const isBlocked = (task: Task): boolean => {
    if (!isDependencyGraphActiveTask(task)) return false;
    const deps = allDepsMap.get(task.id) ?? [];
    return deps.some((dep) => clusterIds.has(dep) && !terminalIds.has(dep));
  };

  return (
    <div key={layer[0]?.id ?? layerIdx} className="space-y-1.5">
      {layerIdx > 0 && !isCyclicLayer && (
        <div className="flex items-center gap-2 ms-2 px-4">
          <svg width="16" height="20" viewBox="0 0 16 20" className="text-accent/50 shrink-0">
            <path d="M8 0 L8 14 M4 10 L8 14 L12 10" stroke="currentColor" strokeWidth="2" fill="none" strokeLinecap="round" strokeLinejoin="round" />
          </svg>
          <span className="text-xs font-medium text-text-muted">
            {t('deps.dependsOn')}
          </span>
        </div>
      )}
      {isCyclicLayer && (
        <div className="flex items-center gap-2 ms-2 px-4">
          <span className="text-xs font-medium text-warning">
            ↺ {t('deps.cyclicLayer')}
          </span>
        </div>
      )}
      {layer.map((task) => {
        const isCyclic = cyclicTaskIds.has(task.id);
        const blocked = !isCyclic && isBlocked(task);
        const isReady = !blocked && !isCyclic && isDependencyGraphActiveTask(task);
        const depIds = allDepsMap.get(task.id) ?? [];
        const depNames = depIds
          .map((id) => taskMap.get(id)?.title)
          .filter((title): title is string => !!title);
        return (
          <div
            key={task.id}
            className={`${layerIdx > 0 ? 'ms-8 ps-3 border-s-2' : ''} ${isCyclic ? 'border-warning/40' : layerIdx > 0 && isReady ? 'border-success/50' : layerIdx > 0 ? 'border-accent/20' : ''} ${blocked || isCyclic ? 'opacity-60' : ''}`}
          >
            <SwipeableTaskCard task={task}>
              <TaskCard
                task={task}
                focused={isFocused(task.id)}
                onClick={() => onSelectTask?.(task.id)}
                completed={isDependencyGraphTerminalTask(task)}
              />
            </SwipeableTaskCard>
            {depNames.length > 0 && (
              <p className="text-xs text-text-muted mt-0.5 ms-4 truncate">
                {t('deps.dependsOnLabel')} {depNames.join(', ')}
              </p>
            )}
            {isCyclic && (
              <p className="text-xs text-warning mt-0.5 ms-4">↺ {t('deps.cyclicTask')}</p>
            )}
            {!isCyclic && blocked && (
              <p className="text-xs text-warning mt-0.5 ms-4">{t('deps.waitingOn')}</p>
            )}
          </div>
        );
      })}
    </div>
  );
}
