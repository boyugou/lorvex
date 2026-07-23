import { type ReactNode } from 'react';
import { useI18n } from '@/lib/i18n';
import { Pill } from '@/components/ui/Pill';

type StatColor = 'success' | 'accent' | 'danger' | 'warning' | 'muted';

const COLOR_MAP: Record<StatColor, string> = {
  success: 'text-success',
  accent: 'text-accent',
  danger: 'text-danger',
  warning: 'text-warning',
  muted: 'text-text-muted',
};

const BG_MAP: Record<StatColor, string> = {
  success: 'tonal-surface-success-xs',
  accent: 'tonal-surface-accent-xs',
  danger: 'tonal-surface-danger-xs',
  warning: 'tonal-surface-warning-xs',
  muted: 'bg-surface-2 border-card',
};

const ICON_BG_MAP: Record<StatColor, string> = {
  success: 'chip-success',
  accent: 'bg-accent/10 text-accent',
  danger: 'chip-danger',
  warning: 'chip-warning',
  muted: 'bg-surface-3/60 text-text-muted',
};

interface StatCardProps {
  label: string;
  value: number;
  color: StatColor;
  showSign?: boolean;
  subtitle?: string | undefined;
  unitSuffix?: string | undefined;
  icon?: ReactNode | undefined;
  trend?: { value: number; label: string } | undefined;
}

export default function StatCard({
  label,
  value,
  color,
  showSign = false,
  subtitle,
  unitSuffix,
  icon,
  trend,
}: StatCardProps) {
  const { formatNumber } = useI18n();
  const formattedValue = Number.isFinite(value) ? formatNumber(value) : String(value);
  const baseDisplay = showSign && value > 0 ? `+${formattedValue}` : formattedValue;
  const display = unitSuffix ? `${baseDisplay}${unitSuffix}` : baseDisplay;

  return (
    <div className={`rounded-r-card px-4 py-4 border transition-colors ${BG_MAP[color]}`}>
      <div className="flex items-start justify-between mb-2">
        {icon && (
          <span className={`w-8 h-8 rounded-r-control inline-flex items-center justify-center ${ICON_BG_MAP[color]}`}>
            {icon}
          </span>
        )}
        {trend && (
          <Pill tone={trend.value > 0 ? 'success' : trend.value < 0 ? 'danger' : 'muted'} size="sm">
            {trend.value > 0 ? '+' : trend.value < 0 ? '-' : ''}{formatNumber(Math.abs(trend.value))} {trend.label}
          </Pill>
        )}
      </div>
      <div className={`text-2xl font-semibold tabular-nums ${COLOR_MAP[color]}`}>{display}</div>
      <div className="text-text-muted text-xs mt-1 font-medium">{label}</div>
      {subtitle && <div className="text-text-muted/60 text-2xs mt-0.5">{subtitle}</div>}
    </div>
  );
}
