import { memo, useMemo } from 'react';
import { useI18n } from '@/lib/i18n';
import { formatDurationCompact } from '../today-view/primitives';
import type { TaskSection } from './types';

interface VirtualSectionHeaderProps {
  section: TaskSection;
  collapsed: boolean;
  onToggleCollapse: () => void;
}

/**
 * Standalone section header for the virtualized AllTasks list.
 *
 * Extracts the header portion of `TaskGroup` so it can be rendered as an
 * independent virtual row.
 */
export const VirtualSectionHeader = memo(function VirtualSectionHeader({ section, collapsed, onToggleCollapse }: VirtualSectionHeaderProps) {
  const { t, formatNumber } = useI18n();
  const totalDurationMinutes = useMemo(
    () => section.tasks.reduce((sum, tk) => sum + (tk.estimated_minutes ?? 0), 0),
    [section.tasks],
  );

  return (
    <h2 className="-mx-1">
      <button
        type="button"
        className="flex items-baseline gap-2 cursor-pointer select-none group/header rounded-r-control hover:bg-surface-3/40 px-1 py-1 focus-ring-soft text-start"
        onClick={onToggleCollapse}
        aria-expanded={!collapsed}
      >
        <span className={`text-3xs text-text-muted transition-transform duration-200 ${collapsed ? '-rotate-90' : ''}`}>
          {'\u25BC'}
        </span>
        <span className="heading-meta">{section.title}</span>
        <span className="chip-tight text-text-muted/70 text-2xs bg-surface-3/40 tabular-nums">{formatNumber(section.tasks.length)}</span>
        {totalDurationMinutes > 0 && (
          <span className="text-text-muted text-xs">
            {'\u00B7'} {formatDurationCompact(totalDurationMinutes, t('common.hourShort'), t('common.min'), formatNumber)}
          </span>
        )}
      </button>
    </h2>
  );
});
