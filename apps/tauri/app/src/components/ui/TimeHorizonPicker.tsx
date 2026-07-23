import { useI18n } from '@/lib/i18n';
import { ToggleChip } from '@/components/ui/ToggleChip';

export const HORIZON_OPTIONS = [7, 14, 30, 60, 90, null] as const;
type HorizonValue = (typeof HORIZON_OPTIONS)[number];

interface TimeHorizonPickerProps {
  value: HorizonValue;
  onChange: (value: HorizonValue) => void;
}

export type { HorizonValue };

export function TimeHorizonPicker({ value, onChange }: TimeHorizonPickerProps) {
  const { t, format } = useI18n();
  return (
    <div className="flex items-center gap-1" role="group" aria-label={t('filter.timeHorizon')}>
      {HORIZON_OPTIONS.map((opt) => {
        const isActive = value === opt;
        const label = opt === null ? t('filter.horizonAll') : format('filter.horizonDays', { count: opt });
        return (
          <ToggleChip
            key={opt ?? 'all'}
            size="xs"
            shape="control"
            onClick={() => onChange(opt)}
            selected={isActive}
            aria-pressed={isActive}
            className={isActive ? 'font-medium' : ''}
          >
            {label}
          </ToggleChip>
        );
      })}
    </div>
  );
}
