import { useCallback, useEffect, useMemo, useRef, useState, type Dispatch, type SetStateAction } from 'react';

import { getNextMondayYmd, getNextWeekendYmd, ymdFromDateParts } from '@/lib/dayContextMath';
import { parseDateFromText, type ParseResult } from '@/lib/dateParser';
import type { TranslationKey } from '@/locales/types.generated';

import type { QuickDateOption } from './types';

interface QuickCaptureDayContext {
  timezone: string;
  todayYmd: string;
  tomorrowYmd: string;
}

interface UseQuickCaptureDateResolutionArgs {
  title: string;
  locale: string;
  t: (key: TranslationKey) => string;
  dayContext: QuickCaptureDayContext;
  initialDateOption: QuickDateOption;
  initialCustomDate: string;
}

interface ResetQuickCaptureDateStateArgs {
  dateOption: QuickDateOption;
  customDate: string;
}

export function useQuickCaptureDateResolution({
  title,
  locale,
  t,
  dayContext,
  initialDateOption,
  initialCustomDate,
}: UseQuickCaptureDateResolutionArgs) {
  const [dateOption, setDateOption] = useState<QuickDateOption>(initialDateOption);
  const [customDate, setCustomDate] = useState(initialCustomDate);
  const [nlDateDismissed, setNlDateDismissed] = useState(false);

  // Natural-language date extraction from the title text.
  // Re-parsed on every title change; dismissed state resets when title changes.
  const nlDateResult: ParseResult | null = useMemo(() => {
    if (!title.trim()) return null;
    const [yearStr, monthStr, dayStr] = dayContext.todayYmd.split('-');
    const year = Number(yearStr);
    const month = Number(monthStr);
    const day = Number(dayStr);
    if (!Number.isFinite(year) || !Number.isFinite(month) || !Number.isFinite(day)) {
      return null;
    }
    const refDate = new Date(year, month - 1, day, 12, 0, 0);
    return parseDateFromText(title, locale, refDate);
  }, [title, locale, dayContext.todayYmd]);

  const currentMatchText = nlDateResult?.matchedText ?? null;
  const prevMatchRef = useRef(currentMatchText);
  useEffect(() => {
    if (currentMatchText !== prevMatchRef.current) {
      prevMatchRef.current = currentMatchText;
      setNlDateDismissed(false);
    }
  }, [currentMatchText]);

  const activeNlDate = (!nlDateDismissed && dateOption === 'none' && nlDateResult) ? nlDateResult : null;

  const resolvedDueDate = useCallback((): string | undefined => {
    switch (dateOption) {
      case 'today': return dayContext.todayYmd;
      case 'tomorrow': return dayContext.tomorrowYmd;
      case 'weekend': return getNextWeekendYmd(dayContext.timezone);
      case 'next-week': return getNextMondayYmd(dayContext.timezone);
      case 'custom': return customDate || undefined;
      default:
        return activeNlDate ? ymdFromDateParts(activeNlDate.date, dayContext.timezone) : undefined;
    }
  }, [activeNlDate, customDate, dateOption, dayContext.timezone, dayContext.todayYmd, dayContext.tomorrowYmd]);

  const dateLabel = useCallback((): string | null => {
    const due = resolvedDueDate();
    if (!due) return null;
    if (due === dayContext.todayYmd) return t('capture.today');
    if (due === dayContext.tomorrowYmd) return t('capture.tomorrow');
    return due;
  }, [dayContext.todayYmd, dayContext.tomorrowYmd, resolvedDueDate, t]);

  const toggleDateOption = useCallback((option: QuickDateOption): void => {
    setDateOption(option === dateOption ? 'none' : option);
  }, [dateOption]);

  const clearDate = useCallback((): void => {
    setDateOption('none');
    setCustomDate('');
  }, []);

  const clearNlDate = useCallback((): void => {
    setNlDateDismissed(true);
  }, []);

  const resetDateState = useCallback((nextState: ResetQuickCaptureDateStateArgs): void => {
    setDateOption(nextState.dateOption);
    setCustomDate(nextState.customDate);
    setNlDateDismissed(false);
  }, []);

  return {
    activeNlDate,
    clearDate,
    clearNlDate,
    customDate,
    dateLabel,
    dateOption,
    resetDateState,
    resolvedDueDate,
    setCustomDate,
    setDateOption: setDateOption as Dispatch<SetStateAction<QuickDateOption>>,
    toggleDateOption,
  };
}
