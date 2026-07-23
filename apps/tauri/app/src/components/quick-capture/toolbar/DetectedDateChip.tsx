import { XIcon } from '@/components/ui/icons';
import { ymdFromDateParts } from '@/lib/dayContextMath';
import { formatCalendarDate } from '@/lib/dates/dateLocale';
import type { ParseResult } from '@/lib/dateParser';
import type { CompactToolbarTranslate } from './types';

export function InlineDetectedDateChip({
  activeNlDate,
  clearNlDate,
  locale,
  t,
  timezone,
}: {
  activeNlDate: ParseResult | null;
  clearNlDate: () => void;
  locale: string;
  t: CompactToolbarTranslate;
  timezone: string;
}) {
  if (!activeNlDate) return null;

  const formatted = formatCalendarDate(
    ymdFromDateParts(activeNlDate.date, timezone),
    locale,
    { weekday: 'short', month: 'short', day: 'numeric' },
  );

  return (
    <span
      className="inline-flex items-center gap-1 text-xs px-2 py-1 rounded-r-control bg-accent/15 text-accent origin-center animate-[chip-scale-in_220ms_cubic-bezier(0.22,1,0.36,1)_both]"
      role="status"
      aria-label={`${t('capture.detectedDate')}: ${formatted}`}
    >
      <SparkleIcon />
      <span className="max-w-[6rem] truncate">{formatted}</span>
      <button
        type="button"
        onClick={clearNlDate}
        aria-label={t('capture.clearDetectedDate')}
        className="ms-0.5 rounded-full p-0.5 hover:bg-accent/20 transition-colors focus-ring-soft"
      >
        <XIcon className="w-2.5 h-2.5" />
      </button>
    </span>
  );
}

/**
 * Four-point sparkle drawn as a single 36-unit-perimeter stroked path
 * so it can be progressively revealed by `animate-sparkle-draw`
 * (defined in `tokens.css`). The icon stays purely decorative — the
 * surrounding `<span>` carries the screen-reader label.
 */
function SparkleIcon() {
  return (
    <svg
      aria-hidden="true"
      width="10"
      height="10"
      viewBox="0 0 12 12"
      fill="none"
      className="shrink-0"
    >
      <path
        d="M6 1 L7 5 L11 6 L7 7 L6 11 L5 7 L1 6 L5 5 Z"
        stroke="currentColor"
        strokeWidth="1.1"
        strokeLinecap="round"
        strokeLinejoin="round"
        strokeDasharray="36"
        className="motion-safe:animate-[sparkleDraw_200ms_cubic-bezier(0.65,0,0.35,1)_both]"
      />
    </svg>
  );
}
