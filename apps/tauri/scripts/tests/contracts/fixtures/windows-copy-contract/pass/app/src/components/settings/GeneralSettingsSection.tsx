import type { TranslationKey } from '../../locales/types';

interface GeneralSettingsSectionProps {
  trayIconTitleKey: TranslationKey;
  trayIconDescKey: TranslationKey;
  trayIconVisibleKey: TranslationKey;
  trayIconHiddenKey: TranslationKey;
}

const t = (key: TranslationKey): string => key;

export function GeneralSettingsSection({
  trayIconTitleKey,
  trayIconDescKey,
  trayIconVisibleKey,
  trayIconHiddenKey,
}: GeneralSettingsSectionProps) {
  return (
    <>
      {t(trayIconTitleKey)}
      {t(trayIconDescKey)}
      {t(trayIconVisibleKey)}
      {t(trayIconHiddenKey)}
    </>
  );
}
