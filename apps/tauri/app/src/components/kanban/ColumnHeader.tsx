import { useI18n } from '../../lib/i18n';
import { formatNumber } from '../../locales';
import { formatDurationCompact } from '../today-view/primitives';

/**
 * Title + counts row at the top of a single Kanban column. Owns the
 * locale-aware total-minutes formatting so the `Column` shell only
 * passes the column's tasks down once.
 */
export function ColumnHeader({
  title,
  totalMinutes,
  count,
}: {
  title: string;
  totalMinutes: number;
  count: number;
}) {
  const { locale, t } = useI18n();
  return (
    <div className="mb-3 shrink-0">
      <div className="flex items-center justify-between gap-2">
        <h2 className="heading-section">{title}</h2>
        <div className="flex items-center gap-2 text-text-muted text-xs tabular-nums">
          {totalMinutes > 0 && (
            <span>{formatDurationCompact(totalMinutes, t('common.hourShort'), t('common.min'), (value) => formatNumber(locale, value))}</span>
          )}
          <span>{formatNumber(locale, count)}</span>
        </div>
      </div>
    </div>
  );
}
