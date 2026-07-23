import { useI18n } from '@/lib/i18n';
import { PRIORITY_OPTIONS } from '@/components/task-card/support';
import {
  parsePriorityFilterValue,
  type PriorityFilterValue,
} from '@/lib/tasks/priorityFilter';
import { FilterDropdown, type FilterOption } from './FilterDropdown';

type PriorityFilterDropdownValue = '' | '1' | '2' | '3';

interface PriorityFilterDropdownProps {
  value: PriorityFilterValue;
  onChange: (priority: PriorityFilterValue) => void;
}

function toDropdownValue(value: PriorityFilterValue): PriorityFilterDropdownValue {
  switch (value) {
    case null:
      return '';
    case 1:
      return '1';
    case 2:
      return '2';
    case 3:
      return '3';
  }
}

export function PriorityFilterDropdown({ value, onChange }: PriorityFilterDropdownProps) {
  const { t } = useI18n();

  const options: FilterOption<PriorityFilterDropdownValue>[] = [
    { value: '', label: t('allTasks.allPriorities') },
    ...PRIORITY_OPTIONS.map(({ value, labelKey }) => ({ value, label: t(labelKey) })),
  ];

  return (
    <FilterDropdown
      label={t('allTasks.filterByPriority').replace(/:$/, '')}
      value={toDropdownValue(value)}
      options={options}
      onChange={(v) => {
        const parsed = parsePriorityFilterValue(v);
        if (parsed !== undefined) onChange(parsed);
      }}
    />
  );
}
