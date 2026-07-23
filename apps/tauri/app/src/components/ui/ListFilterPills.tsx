import type { ListWithCount } from '@/lib/ipc/tasks/models';
import { useI18n } from '@/lib/i18n';
import { FilterDropdown, type FilterOption } from './FilterDropdown';

interface ListFilterPillsProps {
  lists: ListWithCount[];
  value: string | null;
  onChange: (listId: string | null) => void;
}

export function ListFilterPills({ lists, value, onChange }: ListFilterPillsProps) {
  const { t } = useI18n();
  if (lists.length === 0) return null;

  const options: FilterOption<string>[] = [
    { value: '', label: t('allTasks.allLists') },
    ...lists.map((list) => ({
      value: list.id,
      label: list.icon ? `${list.icon} ${list.name}` : list.name,
      color: list.color ?? undefined,
    })),
  ];

  return (
    <FilterDropdown
      label={t('allTasks.filterByList')}
      value={value ?? ''}
      options={options}
      onChange={(v) => onChange(v === '' ? null : v)}
    />
  );
}
