import type React from 'react';
import { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState } from 'react';

import { formatDate, localeWeekStartDay, parseWeekStartDayPreference } from '@/lib/dates/dateLocale';
import { useConfiguredDayContext } from '@/lib/dayContext';
import { getNextMondayYmd, getNextWeekendYmd, parseYmd } from '@/lib/dayContextMath';
import { useI18n } from '@/lib/i18n';
import { PREF_WEEK_STARTS_ON } from '@/lib/preferences/keys';
import { usePreference } from '@/lib/query/usePreference';
import { STALE_LONG } from '@/lib/query/timing';
import { useFocusRestore } from '@/lib/focus/useFocusRestore';
import { useRuntimeProfile } from '@/lib/useRuntimeProfile';

import {
  buildDatePickerGrid,
  getDatePickerWeekdayKeys,
  resolveDatePickerArrowFocusYmd,
  resolveDatePickerInitialFocusYmd,
  resolveDatePickerMonthFocusYmd,
  type DatePickerCell,
  type DatePickerWeekdayKey,
} from './DatePicker.logic';
import { resolveDatePickerDesktopPosition } from './DatePicker.runtime';
import type { DatePickerProps } from './DatePicker.types';
import { pushModalEscapeHandler } from './overlay';
import { getPopoverLayerClasses } from './popoverLayer';

type DatePickerWeek = DatePickerCell[];

export interface DatePickerQuickChip {
  label: string;
  date: string;
}

export interface DatePickerWeekdayLabel {
  key: DatePickerWeekdayKey;
  label: string;
}

export interface DatePickerController {
  value: string | null;
  onChange: (date: string | null) => void;
  onClose: () => void;
  isMobile: boolean;
  layerClasses: ReturnType<typeof getPopoverLayerClasses>;
  position: { top: number; left: number };
  panelRef: React.RefObject<HTMLDivElement | null>;
  dayButtonRefs: React.MutableRefObject<Map<string, HTMLButtonElement>>;
  handleBackdropClick: (e: React.MouseEvent) => void;
  handleKeyDown: (e: React.KeyboardEvent) => void;
  handleSelectDate: (ymd: string) => void;
  isDisabled: (ymd: string) => boolean;
  focusedDay: string | null;
  viewYear: number;
  viewMonth: number;
  weeks: DatePickerWeek[];
  weekdayLabels: DatePickerWeekdayLabel[];
  quickChips: DatePickerQuickChip[];
  showQuickChips: boolean;
  showClearButton: boolean;
  monthLabel: string;
  todayYmd: string;
  todayLabel: string;
  locale: string;
  pickDateLabel: string;
  navPrevYearLabel: string;
  navPrevMonthLabel: string;
  navNextMonthLabel: string;
  navNextYearLabel: string;
  goToTodayLabel: string;
  clearLabel: string;
  closeLabel: string;
  goToPrevYear: () => void;
  goToNextYear: () => void;
  goToPrevMonth: () => void;
  goToNextMonth: () => void;
  goToToday: () => void;
}

export function useDatePickerController({
  value,
  onChange,
  onClose,
  anchorRef,
  showQuickChips = true,
  showClearButton = true,
  minDate,
  popoverLayer = 'popover',
}: DatePickerProps): DatePickerController {
  const { t, locale } = useI18n();
  const dayContext = useConfiguredDayContext();
  const defaultWeekStartDay = useMemo(() => localeWeekStartDay(), []);
  const { value: weekStartDay } = usePreference(
    PREF_WEEK_STARTS_ON,
    (raw) => parseWeekStartDayPreference(raw, defaultWeekStartDay),
    { staleTime: STALE_LONG },
  );
  const skipFocusRestoreRef = useRef(false);
  useFocusRestore({ shouldRestore: () => !skipFocusRestoreRef.current });
  const runtime = useRuntimeProfile();
  const isMobile = runtime.runtimeClass === 'mobile';
  const layerClasses = getPopoverLayerClasses(popoverLayer);
  const initialFocusedDay = useMemo(
    () => resolveDatePickerInitialFocusYmd({
      value,
      todayYmd: dayContext.todayYmd,
      minDate,
    }),
    [value, dayContext.todayYmd, minDate],
  );

  const initial = useMemo(() => {
    const parsed = parseYmd(initialFocusedDay);
    return parsed ? { year: parsed.year, month: parsed.month } : { year: 2026, month: 0 };
  }, [initialFocusedDay]);

  const [viewYear, setViewYear] = useState(initial.year);
  const [viewMonth, setViewMonth] = useState(initial.month);
  const panelRef = useRef<HTMLDivElement>(null);
  const dayButtonRefs = useRef(new Map<string, HTMLButtonElement>());
  const computePosition = useCallback(() => {
    if (isMobile) {
      return resolveDatePickerDesktopPosition({
        isMobile,
        anchorRect: null,
        viewportWidth: 0,
        viewportHeight: 0,
      });
    }

    const anchor = anchorRef?.current;
    return resolveDatePickerDesktopPosition({
      isMobile,
      anchorRect: anchor?.getBoundingClientRect() ?? null,
      viewportWidth: window.innerWidth,
      viewportHeight: window.innerHeight,
    });
  }, [anchorRef, isMobile]);
  const [position, setPosition] = useState(computePosition);

  useLayoutEffect(() => {
    setPosition(computePosition());
  }, [computePosition]);

  useEffect(() => {
    if (isMobile) return;
    panelRef.current?.focus();
  }, [isMobile]);

  const [focusedDay, setFocusedDay] = useState(initialFocusedDay);
  useEffect(() => {
    setFocusedDay(initialFocusedDay);
  }, [initialFocusedDay]);
  useEffect(() => {
    dayButtonRefs.current.get(focusedDay)?.focus();
  }, [focusedDay, viewYear, viewMonth]);

  const isDesktopFocusInsidePicker = useCallback((target: EventTarget | null): boolean => {
    if (!(target instanceof Node)) return false;
    if (panelRef.current?.contains(target)) return true;
    if (anchorRef?.current?.contains(target)) return true;
    return false;
  }, [anchorRef]);

  useEffect(() => {
    if (isMobile) return;
    const handleDesktopFocusIn = (event: FocusEvent) => {
      const { target } = event;
      if (isDesktopFocusInsidePicker(target)) return;
      skipFocusRestoreRef.current = true;
      onClose();
    };
    document.addEventListener('focusin', handleDesktopFocusIn);
    return () => document.removeEventListener('focusin', handleDesktopFocusIn);
  }, [isDesktopFocusInsidePicker, isMobile, onClose]);

  useEffect(() => {
    if (isMobile) return;
    return pushModalEscapeHandler(onClose);
  }, [onClose, isMobile]);

  const isDisabled = useCallback((ymd: string) => minDate ? ymd < minDate : false, [minDate]);

  const handleSelectDate = useCallback((ymd: string) => {
    if (isDisabled(ymd)) return;
    onChange(ymd);
    onClose();
  }, [isDisabled, onChange, onClose]);

  const handleKeyDown = useCallback((e: React.KeyboardEvent) => {
    if (e.key === 'Escape') {
      e.preventDefault();
      onClose();
      return;
    }
    if (!focusedDay) return;
    const parsed = parseYmd(focusedDay);
    if (!parsed) return;

    const isArrowKey = e.key === 'ArrowLeft' || e.key === 'ArrowRight' || e.key === 'ArrowUp' || e.key === 'ArrowDown';
    const isGridNavKey = isArrowKey || e.key === 'Home' || e.key === 'End' || e.key === 'PageUp' || e.key === 'PageDown';
    if (e.key === 'Enter' || e.key === ' ') {
      e.preventDefault();
      handleSelectDate(focusedDay);
      return;
    }

    if (isGridNavKey) {
      e.preventDefault();
      const nextFocusedDay = resolveDatePickerArrowFocusYmd({
        focusedYmd: focusedDay,
        key: e.key,
        shiftKey: e.shiftKey,
        weekStartDay,
        isDisabled,
      });
      const landed = parseYmd(nextFocusedDay);
      if (landed) {
        setFocusedDay(nextFocusedDay);
        if (landed.month !== viewMonth || landed.year !== viewYear) {
          setViewMonth(landed.month);
          setViewYear(landed.year);
        }
      }
    }
  }, [onClose, focusedDay, viewMonth, viewYear, isDisabled, handleSelectDate, weekStartDay]);

  const handleBackdropClick = useCallback((e: React.MouseEvent) => {
    if (e.target === e.currentTarget) onClose();
  }, [onClose]);

  const focusVisibleMonth = useCallback((year: number, month: number) => {
    setFocusedDay(resolveDatePickerMonthFocusYmd({
      year,
      month,
      focusedYmd: focusedDay,
      minDate,
    }));
  }, [focusedDay, minDate]);
  const goToPrevYear = useCallback(() => {
    const nextYear = viewYear - 1;
    setViewYear(nextYear);
    focusVisibleMonth(nextYear, viewMonth);
  }, [focusVisibleMonth, viewMonth, viewYear]);
  const goToNextYear = useCallback(() => {
    const nextYear = viewYear + 1;
    setViewYear(nextYear);
    focusVisibleMonth(nextYear, viewMonth);
  }, [focusVisibleMonth, viewMonth, viewYear]);
  const goToPrevMonth = useCallback(() => {
    const nextYear = viewMonth === 0 ? viewYear - 1 : viewYear;
    const nextMonth = viewMonth === 0 ? 11 : viewMonth - 1;
    setViewYear(nextYear);
    setViewMonth(nextMonth);
    focusVisibleMonth(nextYear, nextMonth);
  }, [focusVisibleMonth, viewMonth, viewYear]);
  const goToNextMonth = useCallback(() => {
    const nextYear = viewMonth === 11 ? viewYear + 1 : viewYear;
    const nextMonth = viewMonth === 11 ? 0 : viewMonth + 1;
    setViewYear(nextYear);
    setViewMonth(nextMonth);
    focusVisibleMonth(nextYear, nextMonth);
  }, [focusVisibleMonth, viewMonth, viewYear]);
  const goToToday = useCallback(() => {
    const target = resolveDatePickerInitialFocusYmd({
      value: null,
      todayYmd: dayContext.todayYmd,
      minDate,
    });
    const parsed = parseYmd(target);
    if (parsed) {
      setViewYear(parsed.year);
      setViewMonth(parsed.month);
      setFocusedDay(target);
    }
  }, [dayContext.todayYmd, minDate]);

  const grid = useMemo(() => {
    return buildDatePickerGrid(viewYear, viewMonth, weekStartDay);
  }, [viewYear, viewMonth, weekStartDay]);
  const weeks = useMemo(() => {
    const rows: DatePickerWeek[] = [];
    for (let i = 0; i < grid.length; i += 7) {
      rows.push(grid.slice(i, i + 7));
    }
    return rows;
  }, [grid]);
  const weekdayLabels = useMemo(
    () => getDatePickerWeekdayKeys(weekStartDay).map((key) => ({ key, label: t(key) })),
    [t, weekStartDay],
  );

  const quickChips = useMemo(() => [
    { label: t('capture.today'), date: dayContext.todayYmd },
    { label: t('capture.tomorrow'), date: dayContext.tomorrowYmd },
    { label: t('capture.weekend'), date: getNextWeekendYmd(dayContext.timezone) },
    { label: t('capture.nextWeek'), date: getNextMondayYmd(dayContext.timezone) },
  ], [t, dayContext]);

  const monthLabel = useMemo(
    () =>
      formatDate(new Date(viewYear, viewMonth), locale, {
        year: 'numeric',
        month: 'long',
      }),
    [viewYear, viewMonth, locale],
  );

  return {
    value,
    onChange,
    onClose,
    isMobile,
    layerClasses,
    position,
    panelRef,
    dayButtonRefs,
    handleBackdropClick,
    handleKeyDown,
    handleSelectDate,
    isDisabled,
    focusedDay,
    viewYear,
    viewMonth,
    weeks,
    weekdayLabels,
    quickChips,
    showQuickChips,
    showClearButton,
    monthLabel,
    todayYmd: dayContext.todayYmd,
    todayLabel: t('nav.today'),
    locale,
    pickDateLabel: t('capture.pickDate'),
    navPrevYearLabel: t('datePicker.navPrevYear'),
    navPrevMonthLabel: t('datePicker.navPrevMonth'),
    navNextMonthLabel: t('datePicker.navNextMonth'),
    navNextYearLabel: t('datePicker.navNextYear'),
    goToTodayLabel: t('datePicker.goToToday'),
    clearLabel: t('quickdate.clear'),
    closeLabel: t('common.close'),
    goToPrevYear,
    goToNextYear,
    goToPrevMonth,
    goToNextMonth,
    goToToday,
  };
}
