import type { DatePickerController } from './DatePicker.controller';
import { DatePickerGrid } from './DatePickerGrid';
import { DatePickerQuickChips } from './DatePickerQuickChips';
import { XIcon } from './icons';

interface DatePickerContentProps {
  controller: DatePickerController;
}

export function DatePickerContent({ controller }: DatePickerContentProps) {
  const {
    isMobile,
    quickChips,
    showQuickChips,
    showClearButton,
    value,
    onChange,
    onClose,
    handleSelectDate,
    goToPrevYear,
    goToPrevMonth,
    goToNextMonth,
    goToNextYear,
    goToToday,
    navPrevYearLabel,
    navPrevMonthLabel,
    navNextMonthLabel,
    navNextYearLabel,
    goToTodayLabel,
    monthLabel,
    clearLabel,
    closeLabel,
    weeks,
    weekdayLabels,
    focusedDay,
    todayYmd,
    todayLabel,
    locale,
    dayButtonRefs,
    isDisabled,
  } = controller;

  const navBtnClass = isMobile
    ? 'min-h-11 min-w-11 flex items-center justify-center rounded-r-control text-text-muted hover:text-text-primary active:bg-surface-3 bg-surface-2/40 transition-colors text-base focus-ring-soft'
    : 'w-8 h-8 flex items-center justify-center rounded-r-control text-text-muted hover:text-text-primary hover:bg-surface-3 bg-surface-2/40 transition-colors text-sm focus-ring-soft';
  const navBtnClassSmall = isMobile
    ? navBtnClass
    : 'w-8 h-8 flex items-center justify-center rounded-r-control text-text-muted hover:text-text-primary hover:bg-surface-3 bg-surface-2/40 transition-colors text-xs focus-ring-soft';
  const closeBtnClass = isMobile
    ? 'min-h-11 min-w-11 flex items-center justify-center rounded-r-control text-text-muted hover:text-text-primary hover:bg-surface-3 transition-colors focus-ring-soft'
    : 'p-1.5 rounded-r-control text-text-muted hover:text-text-primary hover:bg-surface-3 transition-colors focus-ring-soft';
  const clearBtnClass = isMobile
    ? 'min-h-11 px-3 flex items-center text-sm text-text-muted hover:text-danger transition-colors rounded-r-control focus-ring-soft'
    : 'text-xs text-text-muted hover:text-danger transition-colors rounded-r-control px-1 py-0.5 focus-ring-soft';

  return (
    <>
      {showQuickChips && (
        <DatePickerQuickChips
          chips={quickChips}
          value={value}
          isMobile={isMobile}
          onSelectDate={handleSelectDate}
        />
      )}

      <div className="flex items-center justify-between mb-2">
        <div className="flex items-center gap-1">
          <button
            type="button"
            onClick={goToPrevYear}
            className={navBtnClassSmall}
            aria-label={navPrevYearLabel}
          >
            &#x00AB;
          </button>
          <button
            type="button"
            onClick={goToPrevMonth}
            className={navBtnClass}
            aria-label={navPrevMonthLabel}
          >
            &#x2039;
          </button>
        </div>
        <button
          type="button"
          onClick={goToToday}
          className={`${isMobile ? 'min-h-11 text-base' : 'text-sm'} font-medium text-text-primary hover:text-accent transition-colors rounded-r-control px-2 focus-ring-soft`}
          aria-label={goToTodayLabel}
        >
          {monthLabel}
        </button>
        <div className="flex items-center gap-1">
          <button
            type="button"
            onClick={goToNextMonth}
            className={navBtnClass}
            aria-label={navNextMonthLabel}
          >
            &#x203A;
          </button>
          <button
            type="button"
            onClick={goToNextYear}
            className={navBtnClassSmall}
            aria-label={navNextYearLabel}
          >
            &#x00BB;
          </button>
        </div>
      </div>

      <DatePickerGrid
        weeks={weeks}
        weekdayLabels={weekdayLabels}
        monthLabel={monthLabel}
        isMobile={isMobile}
        value={value}
        focusedDay={focusedDay}
        todayYmd={todayYmd}
        todayLabel={todayLabel}
        locale={locale}
        dayButtonRefs={dayButtonRefs}
        isDisabled={isDisabled}
        onSelectDate={handleSelectDate}
      />

      {showClearButton && (
        <div className="flex items-center justify-between mt-2 pt-2 border-t border-surface-3">
          <button
            type="button"
            onClick={() => { onChange(null); onClose(); }}
            className={clearBtnClass}
          >
            {clearLabel}
          </button>
          <button
            type="button"
            onClick={onClose}
            aria-label={closeLabel}
            className={closeBtnClass}
          >
            <XIcon className={isMobile ? 'w-5 h-5' : 'w-3.5 h-3.5'} />
          </button>
        </div>
      )}
    </>
  );
}
