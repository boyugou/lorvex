import RecurrenceField from './RecurrenceField';
import { TaskMetricsFields } from './editable-grid/TaskMetricsFields';
import { DueTimeField } from './editable-grid/DueTimeField';
import { RemindersField } from './editable-grid/RemindersField';
import type { TaskSecondaryMetaFieldsProps } from './editable-grid/types';

/**
 * Secondary metadata for the collapsible "More" section: time,
 * reminders, recurrence, metrics. Due-date / planned-date / duration
 * live in the primary `TaskUnifiedMetaCard` block above, so this
 * panel only carries the remaining temporal slots.
 */
export function TaskSecondaryMetaFields({
  task,
  locale,
  t,
  onSave,
}: TaskSecondaryMetaFieldsProps) {
  return (
    <div className="rounded-r-control bg-surface-2/30 border border-card px-3 py-2.5">
      <div className="grid grid-cols-2 gap-2.5 text-sm">
        <DueTimeField task={task} t={t} onSave={onSave} />
        <RemindersField taskId={task.id} locale={locale} t={t} />

        <TaskMetricsFields task={task} t={t} onSave={onSave} />

        <div className="col-span-2 pt-1 border-t border-card">
          <RecurrenceField
            task={task}
            locale={locale}
            t={t}
            onSave={async (recurrence) => {
              await onSave({ recurrence });
            }}
          />
        </div>
      </div>
    </div>
  );
}
