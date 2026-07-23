import { MetaField } from '../primitives';
import type { TaskMetricsFieldsProps } from './types';

export function TaskMetricsFields({ task, t }: TaskMetricsFieldsProps) {
  if (task.defer_count <= 0) return null;
  return (
    <MetaField
      label={t('task.deferred')}
      value={`${task.defer_count}${t('task.times')}`}
      className="text-warning"
    />
  );
}
