import { useI18n } from '@/lib/i18n';
import { Button } from '@/components/ui/Button';
import { Toggle } from '@/components/ui/Toggle';
import { SettingsSection } from '../SettingsPrimitives';
import { useNativeCalendarPanelController } from './useNativeCalendarPanelController';

export function NativeCalendarPanel() {
  const { t } = useI18n();
  const {
    config,
    enabled,
    handleSync,
    handleToggle,
    lastResult,
    syncing,
  } = useNativeCalendarPanelController();

  if (!config) return null;

  if (!config.isAvailable) {
    return (
      <SettingsSection title={t(config.titleKey)} description={t(config.descKey)}>
        <p className="text-xs text-text-muted">{t(config.inactiveMessageKey)}</p>
      </SettingsSection>
    );
  }

  return (
    <SettingsSection title={t(config.titleKey)} description={t(config.descKey)}>
      <div className="space-y-3">
        <Toggle
          checked={enabled}
          onChange={() => { void handleToggle(); }}
          label={enabled ? t('common.enabled') : t('common.disabled')}
        />

        {enabled && (
          <Button
            variant="outline"
            onClick={() => { void handleSync(); }}
            disabled={syncing}
          >
            {syncing ? t('common.saving') : t('settings.nativeCalendarSync')}
          </Button>
        )}

        {lastResult && (
          lastResult.error ? (
            <p className="text-xs text-danger">{lastResult.error}</p>
          ) : (
            <p className="text-xs text-text-muted">
              {lastResult.events_imported} {t('settings.nativeCalendarNew')}, {lastResult.events_updated} {t('settings.nativeCalendarUpdated')}
            </p>
          )
        )}
      </div>
    </SettingsSection>
  );
}
