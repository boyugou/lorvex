import { useI18n } from '@/lib/i18n';
import { AppSelect } from '@/components/ui/AppSelect';
import { Button } from '@/components/ui/Button';
import { SettingsSection, TimeInput } from '../SettingsPrimitives';
import { WEEKLY_REVIEW_DAY_OPTIONS } from './catalog';
import type { AdvancedPreferencesPanelProps } from './types';

export function AdvancedPreferencesPanel({
  normalizedTimezone,
  timezoneOptions,
  weeklyReviewDay,
  weeklyReviewTime,
  morningBriefingTime,
  onTimezoneChange,
  onUseSystemTimezone,
  onWeeklyReviewDayChange,
  onWeeklyReviewTimeChange,
  onMorningBriefingTimeChange,
}: AdvancedPreferencesPanelProps) {
  const { t } = useI18n();

  return (
    <SettingsSection
      title={t('settings.advanced')}
      description={t('settings.advancedDesc')}
    >
      <div className="space-y-4">
        <div className="space-y-1.5">
          <p className="text-xs text-text-secondary font-medium">{t('settings.timezone')}</p>
          <div className="flex items-center gap-2">
            <AppSelect
              value={normalizedTimezone}
              variant="default"
              onChange={(event) => onTimezoneChange(event.target.value)}
              className="flex-1"
            >
              {timezoneOptions.map((option) => (
                <option key={option} value={option}>
                  {option}
                </option>
              ))}
            </AppSelect>
            <Button
              variant="outline"
              onClick={onUseSystemTimezone}
            >
              {t('settings.useSystem')}
            </Button>
          </div>
        </div>

        <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
          <div className="space-y-1.5">
            <p className="text-xs text-text-secondary font-medium">{t('settings.weeklyReviewDay')}</p>
            <AppSelect
              value={weeklyReviewDay}
              variant="default"
              onChange={(event) => onWeeklyReviewDayChange(event.target.value)}
              className="w-full"
            >
              {WEEKLY_REVIEW_DAY_OPTIONS.map((day) => (
                <option key={day.value} value={day.value}>{t(day.labelKey)}</option>
              ))}
            </AppSelect>
          </div>

          <div className="space-y-1.5">
            <p className="text-xs text-text-secondary font-medium">{t('settings.weeklyReviewTime')}</p>
            <TimeInput
              value={weeklyReviewTime}
              onChange={onWeeklyReviewTimeChange}
              ariaLabel={t('settings.weeklyReviewTime')}
            />
          </div>

          <div className="space-y-1.5">
            <p className="text-xs text-text-secondary font-medium">{t('settings.morningBriefingTime')}</p>
            <TimeInput
              value={morningBriefingTime}
              onChange={onMorningBriefingTimeChange}
              ariaLabel={t('settings.morningBriefingTime')}
            />
          </div>
        </div>
      </div>
    </SettingsSection>
  );
}
