import { useI18n } from '@/lib/i18n';
import { AppSelect } from '@/components/ui/AppSelect';
import { Toggle } from '@/components/ui/Toggle';
import { DESKTOP_CLOSE_ACTION_OPTIONS } from './catalog';
import type { DesktopBehaviorPanelProps } from './types';

type DesktopBehaviorContentProps = Omit<DesktopBehaviorPanelProps, 'runtimeClass'>;

/** Inner content without the wrapping SettingsSection — used when the parent controls collapse. */
export function DesktopBehaviorPanelContent({
  autostart,
  autostartBusy,
  supportsBiometricLock,
  trayIconVisible,
  trayIconBusy,
  trayIconTitleKey,
  trayIconDescKey,
  trayIconVisibleKey,
  trayIconHiddenKey,
  desktopCloseAction,
  memoryLock,
  memoryLockBusy,
  onAutostartToggle,
  onTrayIconToggle,
  onDesktopCloseActionChange,
  onMemoryLockToggle,
}: DesktopBehaviorContentProps) {
  const { t } = useI18n();

  return (
    <div className="space-y-4">
      <div className="space-y-1.5">
        <p className="text-xs text-text-secondary font-medium">{t('settings.launchOnLogin')}</p>
        <p className="text-xs text-text-muted">{t('settings.launchOnLoginDesc')}</p>
        <div className="mt-1.5">
          <Toggle
            checked={autostart}
            disabled={autostartBusy}
            onChange={(value) => { void onAutostartToggle(value); }}
            label={autostart ? t('settings.launchEnabled') : t('settings.launchDisabled')}
          />
        </div>
      </div>

      <div className="space-y-1.5">
        <p className="text-xs text-text-secondary font-medium">{t(trayIconTitleKey)}</p>
        <p className="text-xs text-text-muted">{t(trayIconDescKey)}</p>
        <div className="mt-1.5">
          <Toggle
            checked={trayIconVisible}
            disabled={trayIconBusy}
            onChange={(value) => { void onTrayIconToggle(value); }}
            label={trayIconVisible ? t(trayIconVisibleKey) : t(trayIconHiddenKey)}
          />
        </div>
      </div>

      <div className="space-y-1.5">
        <p className="text-xs text-text-secondary font-medium">{t('settings.desktopCloseAction')}</p>
        <p className="text-xs text-text-muted">{t('settings.desktopCloseActionDesc')}</p>
        <AppSelect
          value={desktopCloseAction}
          variant="default"
          onChange={(event) => {
            const next = event.target.value;
            if (next === 'quit' || next === 'hide_to_tray') {
              onDesktopCloseActionChange(next);
            }
          }}
          className="w-full max-w-sm mt-1.5"
        >
          {DESKTOP_CLOSE_ACTION_OPTIONS.map((option) => (
            <option key={option.value} value={option.value}>
              {t(option.labelKey)}
            </option>
          ))}
        </AppSelect>
      </div>

      {supportsBiometricLock && <div className="space-y-1.5">
        <p className="text-xs text-text-secondary font-medium">{t('settings.memoryLock')}</p>
        <p className="text-xs text-text-muted">{t('settings.memoryLockDescBiometric')}</p>
        <div className="mt-1.5">
          <Toggle
            checked={memoryLock}
            disabled={memoryLockBusy}
            onChange={(value) => { void onMemoryLockToggle(value); }}
            label={memoryLock ? `🔒 ${t('settings.memoryLock')}` : t('settings.memoryLockDisabled')}
          />
        </div>
      </div>}
    </div>
  );
}
