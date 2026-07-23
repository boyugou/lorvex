import { useI18n } from '@/lib/i18n';

export function SectionHeader({
  title,
  subtitle,
  count,
  collapsed,
  onToggleCollapse,
}: {
  title: string;
  subtitle?: string | undefined;
  count?: number | undefined;
  collapsed?: boolean | undefined;
  onToggleCollapse?: (() => void) | undefined;
}) {
  const { formatNumber } = useI18n();
  const isCollapsible = onToggleCollapse != null;
  const inner = (
    <>
      {isCollapsible && (
        <span className={`text-text-muted text-xs transition-transform duration-150 ${collapsed ? '' : 'rotate-90'}`}>›</span>
      )}
      <span className="text-text-secondary text-xs font-medium">{title}</span>
      {count != null && <span className="chip-tight text-text-muted/70 text-2xs bg-surface-3/40 tabular-nums">{formatNumber(count)}</span>}
      {subtitle && <span className="text-text-muted text-xs">{subtitle}</span>}
    </>
  );

  if (isCollapsible) {
    return (
      <h2 className="mb-3">
        <button
          type="button"
          className="flex items-baseline gap-2 select-none cursor-pointer bg-transparent border-none p-0 focus-ring-soft rounded-r-control text-start"
          onClick={onToggleCollapse}
          aria-expanded={!collapsed}
        >
          {inner}
        </button>
      </h2>
    );
  }

  return (
    <h2 className="flex items-baseline gap-2 mb-3">
      {inner}
    </h2>
  );
}

export function formatDurationCompact(
  totalMinutes: number,
  hourUnit: string,
  minuteUnit: string,
  formatNumber: (value: number) => string = String,
): string {
  const rounded = Math.max(0, Math.round(totalMinutes));
  const hours = Math.floor(rounded / 60);
  const minutes = rounded % 60;
  const formattedHours = formatNumber(hours);
  const formattedMinutes = formatNumber(minutes);

  if (hours <= 0) return `${formattedMinutes}${minuteUnit}`;
  if (minutes <= 0) return `${formattedHours}${hourUnit}`;
  return `${formattedHours}${hourUnit} ${formattedMinutes}${minuteUnit}`;
}

const STAT_COLORS: Record<string, string> = {
  success: 'text-success',
  danger: 'text-danger',
  warning: 'text-warning',
  accent: 'text-accent',
};

export function StatCard({
  label,
  value,
  accent,
}: {
  label: string;
  value: number;
  accent?: string;
}) {
  const { formatNumber } = useI18n();
  return (
    <div className="bg-surface-2/70 rounded-r-card px-3.5 py-3 text-center border border-card">
      <p
        className={`text-xl font-light tabular-nums ${accent ? STAT_COLORS[accent] ?? 'text-text-primary' : 'text-text-primary'}`}
      >
        {Number.isFinite(value) ? formatNumber(value) : value}
      </p>
      <p className="text-text-muted/70 text-2xs mt-1 font-medium">{label}</p>
    </div>
  );
}
