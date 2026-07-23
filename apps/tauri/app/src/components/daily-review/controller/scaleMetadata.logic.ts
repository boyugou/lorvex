import type { TranslationKey } from '@/lib/i18n';
import { formatNumber } from '@/locales';

export const DAILY_REVIEW_SCALE_VALUES = [1, 2, 3, 4, 5] as const;

type DailyReviewScaleValue = (typeof DAILY_REVIEW_SCALE_VALUES)[number];
type DailyReviewScaleKind = 'mood' | 'energy';

type Translator = (key: TranslationKey) => string;

interface DailyReviewScaleOption {
  value: DailyReviewScaleValue;
  icon: string;
  labelKey?: TranslationKey;
}

interface DailyReviewEnergyScaleOption extends DailyReviewScaleOption {
  labelKey: TranslationKey;
  bg: string;
  activeBorder: string;
  activeRing: string;
}

export const DAILY_REVIEW_MOOD_SCALE: readonly DailyReviewScaleOption[] = [
  { value: 1, icon: '\u{1F61E}' },
  { value: 2, icon: '\u{1F615}' },
  { value: 3, icon: '\u{1F610}' },
  { value: 4, icon: '\u{1F642}' },
  { value: 5, icon: '\u{1F604}' },
] as const;

// Static Tailwind classes reference theme CSS variables so energy cards adapt
// across light/dark themes. Dynamic class names would be purged.
export const DAILY_REVIEW_ENERGY_SCALE: readonly DailyReviewEnergyScaleOption[] = [
  {
    value: 1,
    icon: '\u{1F4A4}',
    labelKey: 'dailyReview.exhausted',
    bg: 'bg-[var(--danger-tint-sm)]',
    activeBorder: 'border-danger/40',
    activeRing: 'ring-danger/40',
  },
  {
    value: 2,
    icon: '\u{1F634}',
    labelKey: 'dailyReview.tired',
    bg: 'bg-[var(--warning-tint-sm)]',
    activeBorder: 'border-warning/40',
    activeRing: 'ring-warning/40',
  },
  {
    value: 3,
    icon: '\u26A1',
    labelKey: 'dailyReview.neutral',
    bg: 'bg-[var(--warning-tint-xs)]',
    activeBorder: 'border-warning/30',
    activeRing: 'ring-warning/30',
  },
  {
    value: 4,
    icon: '\u26A1\u26A1',
    labelKey: 'dailyReview.good',
    bg: 'bg-[var(--success-tint-xs)]',
    activeBorder: 'border-success/30',
    activeRing: 'ring-success/30',
  },
  {
    value: 5,
    icon: '\u{1F525}',
    labelKey: 'dailyReview.energized',
    bg: 'bg-[var(--success-tint-sm)]',
    activeBorder: 'border-success/40',
    activeRing: 'ring-success/40',
  },
] as const;

function scaleOptions(kind: DailyReviewScaleKind): readonly DailyReviewScaleOption[] {
  return kind === 'mood' ? DAILY_REVIEW_MOOD_SCALE : DAILY_REVIEW_ENERGY_SCALE;
}

function isDailyReviewScaleValue(value: number): value is DailyReviewScaleValue {
  return DAILY_REVIEW_SCALE_VALUES.includes(value as DailyReviewScaleValue);
}

export function getDailyReviewScaleOption(
  kind: DailyReviewScaleKind,
  value: number | null | undefined,
): DailyReviewScaleOption | null {
  if (value == null || !isDailyReviewScaleValue(value)) return null;
  return scaleOptions(kind).find((option) => option.value === value) ?? null;
}

function getDailyReviewScaleCategoryLabel(kind: DailyReviewScaleKind, t: Translator): string {
  return t(kind === 'mood' ? 'dailyReview.mood' : 'dailyReview.energy');
}

export function formatDailyReviewScaleValue(
  kind: DailyReviewScaleKind,
  value: number | null | undefined,
  locale: string,
): string | null {
  const option = getDailyReviewScaleOption(kind, value);
  if (!option) return null;
  return `${option.icon} ${formatNumber(locale, option.value)}/5`;
}

export function formatDailyReviewScaleTooltipLabel(input: {
  kind: DailyReviewScaleKind;
  value: number | null | undefined;
  locale: string;
  t: Translator;
}): string | null {
  const formattedValue = formatDailyReviewScaleValue(input.kind, input.value, input.locale);
  if (!formattedValue) return null;
  return `${getDailyReviewScaleCategoryLabel(input.kind, input.t)}: ${formattedValue}`;
}

export function formatDailyReviewScaleAriaLabel(input: {
  kind: DailyReviewScaleKind;
  value: DailyReviewScaleValue;
  locale: string;
  t: Translator;
}): string {
  const option = getDailyReviewScaleOption(input.kind, input.value);
  const base = `${getDailyReviewScaleCategoryLabel(input.kind, input.t)} ${formatNumber(input.locale, input.value)}/5`;
  if (option?.labelKey) {
    return `${base} ${input.t(option.labelKey)}`;
  }
  return base;
}

export function formatDailyReviewScaleCopyParts(input: {
  mood: number | null | undefined;
  energyLevel: number | null | undefined;
  locale: string;
  t: Translator;
}): string[] {
  const parts: string[] = [];
  const moodLabel = formatDailyReviewScaleTooltipLabel({
    kind: 'mood',
    value: input.mood,
    locale: input.locale,
    t: input.t,
  });
  if (moodLabel) {
    parts.push(moodLabel);
  }

  const energyLabel = formatDailyReviewScaleTooltipLabel({
    kind: 'energy',
    value: input.energyLevel,
    locale: input.locale,
    t: input.t,
  });
  if (energyLabel) {
    parts.push(energyLabel);
  }

  return parts;
}
