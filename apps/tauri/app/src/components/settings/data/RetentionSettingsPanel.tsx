import {
  MAX_HIDE_COMPLETED_OLDER_THAN_DAYS,
  MIN_HIDE_COMPLETED_OLDER_THAN_DAYS,
} from '@/lib/hideCompletedOlderThan';
import { useI18n } from '@/lib/i18n';
import { RETENTION_DEFAULT_KEYS } from '@/lib/preferences/defaults';
import { RestoreDefaultsButton } from '../RestoreDefaultsButton';
import { AppSelect } from '@/components/ui/AppSelect';
import { CompactNumberInput } from '@/components/ui/CompactNumberInput';
import { DangerZoneLink } from './DangerZoneLink';
import { useRetentionSettingsController } from './useRetentionSettingsController';

const RETENTION_OPTIONS = [null, 7, 14, 30, 60, 90, 180, 365] as const;

function RetentionSelect({
  value,
  onChange,
  disabled,
}: {
  value: number | null;
  onChange: (days: number | null) => void;
  disabled?: boolean;
}) {
  const { t, format } = useI18n();
  return (
    <AppSelect
      value={value === null ? '' : String(value)}
      variant="muted"
      onChange={(e) => onChange(e.target.value === '' ? null : Number(e.target.value))}
      disabled={disabled}
    >
      {RETENTION_OPTIONS.map((opt) => (
        <option key={opt ?? 'forever'} value={opt === null ? '' : String(opt)}>
          {opt === null
            ? t('settings.retentionForever')
            : format('settings.retentionDays', { count: opt })}
        </option>
      ))}
    </AppSelect>
  );
}

export function RetentionSettingsPanel() {
  const { t } = useI18n();
  const {
    changelogDays,
    errorLogDays,
    hideCompletedDays,
    handleChangelogRetention,
    handleErrorLogRetention,
    handleHideCompletedDays,
    loaded,
    saving,
  } = useRetentionSettingsController();

  if (!loaded) return null;

  // The parent SettingsSection now owns the panel chrome + section
  // title/description; we render only the rows and a trailing
  // "restore defaults" + purge-link strip.
  return (
    <div className="space-y-3">
      {/* `divide-y` alone draws the hairlines between rows; the row's
          own `py-1.5` provides vertical rhythm. The earlier
          `space-y-1` here doubled spacing on top of the row padding
          and pushed each divider 4px below the line above. */}
      <div className="divide-y divide-card">
        <div className="flex items-center justify-between gap-3 py-1.5">
          <span className="text-xs text-text-secondary">{t('settings.changelogRetention')}</span>
          <RetentionSelect value={changelogDays} onChange={handleChangelogRetention} disabled={saving} />
        </div>
        <div className="flex items-center justify-between gap-3 py-1.5">
          <span className="text-xs text-text-secondary">{t('settings.errorLogRetention')}</span>
          <RetentionSelect value={errorLogDays} onChange={handleErrorLogRetention} disabled={saving} />
        </div>
        <HideCompletedDaysRow
          value={hideCompletedDays}
          onChange={handleHideCompletedDays}
          disabled={saving}
        />
      </div>
      <div className="flex items-center justify-between gap-3 pt-2 border-t border-card">
        <DangerZoneLink message={t('settings.purgeCancelledMoved')} />
        {/* per-category Restore Defaults. Reverts changelog,
            error-log, and hide-completed windows as one Undo-able bundle. */}
        <RestoreDefaultsButton
          keys={RETENTION_DEFAULT_KEYS}
          categoryLabel={t('settings.restoreDefaultsRetention')}
          errorKeyPrefix="settings.retention.restoreDefaults"
        />
      </div>
    </div>
  );
}

function HideCompletedDaysRow({
  value,
  onChange,
  disabled,
}: {
  value: number;
  onChange: (days: number) => void;
  disabled?: boolean;
}) {
  const { t } = useI18n();
  return (
    <div className="space-y-1 py-1.5">
      <div className="flex items-center justify-between gap-3">
        <span className="text-xs text-text-secondary">
          {t('retention.hideCompletedAfter.label')}
        </span>
        <div className="flex items-center gap-2">
          <CompactNumberInput
            data-theme-form-control="true"
            inputMode="numeric"
            min={MIN_HIDE_COMPLETED_OLDER_THAN_DAYS}
            max={MAX_HIDE_COMPLETED_OLDER_THAN_DAYS}
            step={1}
            value={value}
            disabled={disabled}
            onChange={(e) => {
              const next = Number(e.target.value);
              if (Number.isFinite(next)) onChange(next);
            }}
            width="lg"
            background="surface-1"
            className="text-end disabled:opacity-50"
          />
          <span className="text-xs text-text-muted">
            {t('retention.hideCompletedAfter.unit')}
          </span>
        </div>
      </div>
      <p className="text-2xs text-text-muted leading-snug">
        {t('retention.hideCompletedAfter.hint')}
      </p>
    </div>
  );
}
