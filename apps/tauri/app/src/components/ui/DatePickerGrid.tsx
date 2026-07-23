import type React from 'react';

import { formatDatePickerDayAriaLabel, type DatePickerCell } from './DatePicker.logic';
import type { DatePickerWeekdayLabel } from './DatePicker.controller';

interface DatePickerGridProps {
  weeks: DatePickerCell[][];
  weekdayLabels: DatePickerWeekdayLabel[];
  monthLabel: string;
  isMobile: boolean;
  value: string | null;
  focusedDay: string | null;
  todayYmd: string;
  todayLabel: string;
  locale: string;
  dayButtonRefs: React.MutableRefObject<Map<string, HTMLButtonElement>>;
  isDisabled: (ymd: string) => boolean;
  onSelectDate: (ymd: string) => void;
}

export function DatePickerGrid({
  weeks,
  weekdayLabels,
  monthLabel,
  isMobile,
  value,
  focusedDay,
  todayYmd,
  todayLabel,
  locale,
  dayButtonRefs,
  isDisabled,
  onSelectDate,
}: DatePickerGridProps) {
  const dayCellBase = isMobile
    ? 'w-full aspect-square min-h-11 flex items-center justify-center text-base rounded-r-control transition-colors'
    : 'w-full aspect-square flex items-center justify-center text-xs rounded-r-control transition-colors';

  return (
    <div role="grid" aria-label={monthLabel}>
      <div className="grid grid-cols-7 gap-0 mb-1" role="row">
        {weekdayLabels.map(({ key, label }) => (
          <div
            key={key}
            role="columnheader"
            className={`${isMobile ? 'text-sm py-1' : 'text-xs py-0.5'} text-text-muted text-center`}
          >
            {label}
          </div>
        ))}
      </div>

      <div className={isMobile ? 'space-y-0.5' : 'space-y-0'}>
        {weeks.map((week, weekIndex) => (
          <div
            key={`week-${weekIndex}`}
            className={`grid grid-cols-7 ${isMobile ? 'gap-0.5' : 'gap-0'}`}
            role="row"
          >
            {week.map((cell, dayIndex) => {
              if (!cell) return <div key={`empty-${weekIndex}-${dayIndex}`} role="gridcell" />;
              const isToday = cell.ymd === todayYmd;
              const isSelected = cell.ymd === value;
              const disabled = isDisabled(cell.ymd);
              const isFocused = cell.ymd === focusedDay && !disabled;
              const ariaLabel = formatDatePickerDayAriaLabel({
                ymd: cell.ymd,
                locale,
                isToday,
                todayLabel,
              });
              return (
                <div key={cell.ymd} role="gridcell" aria-selected={isSelected}>
                  <button
                    ref={(node) => {
                      if (node) dayButtonRefs.current.set(cell.ymd, node);
                      else dayButtonRefs.current.delete(cell.ymd);
                    }}
                    type="button"
                    onClick={() => onSelectDate(cell.ymd)}
                    disabled={disabled}
                    tabIndex={isFocused ? 0 : -1}
                    data-focused={isFocused ? 'true' : undefined}
                    aria-label={ariaLabel}
                    aria-pressed={isSelected}
                    aria-current={isToday ? 'date' : undefined}
                    className={`${dayCellBase} focus-ring-strong ${
                      isSelected
                        ? 'bg-accent text-on-accent font-medium'
                        : isToday
                          ? 'ring-1 ring-inset ring-accent/40 text-accent font-medium hover:bg-accent/10'
                          : disabled
                            ? 'text-text-muted/45 cursor-not-allowed'
                            : 'text-text-primary hover:bg-surface-3'
                    } ${isFocused ? 'ring-2 ring-inset ring-accent/70 shadow-[0_0_0_2px_var(--color-surface-0)]' : ''}`}
                  >
                    {cell.day}
                  </button>
                </div>
              );
            })}
          </div>
        ))}
      </div>
    </div>
  );
}
