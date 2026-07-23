import { useRef, useState } from 'react';
import { CalendarUpcomingIcon, XIcon } from '@/components/ui/icons';
import { DatePicker } from '@/components/ui/DatePicker';
import { useConfiguredDayContext } from '@/lib/dayContext';
import { ToggleChip } from '@/components/ui/ToggleChip';
import type { QuickDateOption } from '../types';
import type { CompactToolbarTranslate } from './types';

export function DatePills({
  dateOption,
  customDate,
  setCustomDate,
  setDateOption,
  toggleDateOption,
  clearDate,
  t,
}: {
  dateOption: QuickDateOption;
  customDate: string;
  setCustomDate: (d: string) => void;
  setDateOption: (o: QuickDateOption) => void;
  toggleDateOption: (o: QuickDateOption) => void;
  clearDate: () => void;
  t: CompactToolbarTranslate;
}) {
  const [showDatePicker, setShowDatePicker] = useState(false);
  const datePickerAnchorRef = useRef<HTMLButtonElement>(null);
  const dayContext = useConfiguredDayContext();

  function handleDatePickerChange(date: string | null): void {
    if (date) {
      setCustomDate(date);
      setDateOption('custom');
    } else {
      clearDate();
    }
    setShowDatePicker(false);
  }

  return (
    <>
      <ToggleChip
        onClick={() => toggleDateOption('today')}
        aria-pressed={dateOption === 'today'}
        selected={dateOption === 'today'}
      >
        {t('capture.today')}
      </ToggleChip>
      <ToggleChip
        onClick={() => toggleDateOption('tomorrow')}
        aria-pressed={dateOption === 'tomorrow'}
        selected={dateOption === 'tomorrow'}
      >
        {t('capture.tomorrow')}
      </ToggleChip>
      <div className="relative">
        <ToggleChip
          ref={datePickerAnchorRef}
          onClick={() => setShowDatePicker(true)}
          aria-pressed={dateOption === 'custom'}
          selected={dateOption === 'custom'}
          aria-label={t('capture.pickDate')}
        >
          <CalendarUpcomingIcon className="w-3.5 h-3.5" />
          {dateOption === 'custom' && customDate && (
            <span className="max-w-[5rem] truncate">{customDate}</span>
          )}
        </ToggleChip>
        {showDatePicker && (
          <DatePicker
            value={customDate || null}
            onChange={handleDatePickerChange}
            onClose={() => setShowDatePicker(false)}
            anchorRef={datePickerAnchorRef}
            showQuickChips={false}
            minDate={dayContext.todayYmd}
            popoverLayer="modalPopover"
          />
        )}
      </div>
      {dateOption !== 'none' && (
        <button
          type="button"
          onClick={clearDate}
          className="text-text-muted hover:text-text-primary transition-colors focus-ring-soft rounded-r-control"
          aria-label={t('quickdate.clear')}
        >
          <XIcon className="w-3 h-3" />
        </button>
      )}
    </>
  );
}
