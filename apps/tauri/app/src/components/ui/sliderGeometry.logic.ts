import type { LocaleTextDirection } from '@/locales/registry';

interface ResolveSliderFillPercentArgs {
  value: number;
  min: number;
  max: number;
}

interface ResolveSliderTrackBackgroundArgs {
  fillPercent: number;
  textDirection: LocaleTextDirection;
  activeColor?: string | undefined;
  inactiveColor?: string | undefined;
}

interface ResolveLogicalSliderThumbStyleArgs {
  fillPercent: number;
  thumbRadiusPx: number;
}

const DEFAULT_ACTIVE_COLOR = 'var(--color-accent)';
const DEFAULT_INACTIVE_COLOR = 'var(--color-surface-3)';
const percentFormatterCache = new Map<string, Intl.NumberFormat>();

function clampPercent(value: number): number {
  if (!Number.isFinite(value)) return 0;
  return Math.min(100, Math.max(0, value));
}

function formatPercentStop(value: number): string {
  const clamped = clampPercent(value);
  return Number.isInteger(clamped) ? `${clamped}%` : `${Number(clamped.toFixed(2))}%`;
}

export function resolveSliderFillPercent({
  value,
  min,
  max,
}: ResolveSliderFillPercentArgs): number {
  if (!Number.isFinite(value) || !Number.isFinite(min) || !Number.isFinite(max)) return 0;
  if (max <= min) return 0;
  return clampPercent(((value - min) / (max - min)) * 100);
}

export function resolveSliderTrackBackground({
  fillPercent,
  textDirection,
  activeColor = DEFAULT_ACTIVE_COLOR,
  inactiveColor = DEFAULT_INACTIVE_COLOR,
}: ResolveSliderTrackBackgroundArgs): string {
  const stop = formatPercentStop(fillPercent);
  const gradientDirection = textDirection === 'rtl' ? 'to left' : 'to right';
  return `linear-gradient(${gradientDirection}, ${activeColor} 0%, ${activeColor} ${stop}, ${inactiveColor} ${stop}, ${inactiveColor} 100%)`;
}

export function resolveLogicalSliderFillStyle(fillPercent: number): {
  insetInlineStart: string;
  inlineSize: string;
} {
  return {
    insetInlineStart: '0%',
    inlineSize: formatPercentStop(fillPercent),
  };
}

export function resolveLogicalSliderThumbStyle({
  fillPercent,
  thumbRadiusPx,
}: ResolveLogicalSliderThumbStyleArgs): {
  insetInlineStart: string;
} {
  return {
    insetInlineStart: `calc(${formatPercentStop(fillPercent)} - ${thumbRadiusPx}px)`,
  };
}

export function formatSliderPercentLabel(
  value: number,
  locale: string,
): string {
  const safeValue = Number.isFinite(value) ? value : 0;
  const cached = percentFormatterCache.get(locale);
  if (cached) return cached.format(safeValue / 100);

  let formatter: Intl.NumberFormat;
  try {
    formatter = new Intl.NumberFormat(locale, {
      maximumFractionDigits: 0,
      style: 'percent',
    });
  } catch {
    formatter = new Intl.NumberFormat('en', {
      maximumFractionDigits: 0,
      style: 'percent',
    });
  }
  percentFormatterCache.set(locale, formatter);
  return formatter.format(safeValue / 100);
}
