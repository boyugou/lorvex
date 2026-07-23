import type { TranslationKey } from '../../../locales/types';

const t = (key: TranslationKey): string => key;

interface GeneralPreferencesSectionProps {
  trayIconTitleKey: TranslationKey;
  trayIconDescKey: TranslationKey;
  trayIconVisibleKey: TranslationKey;
  trayIconHiddenKey: TranslationKey;
}

export function GeneralPreferencesSection({
  trayIconTitleKey,
  trayIconDescKey,
  trayIconVisibleKey,
  trayIconHiddenKey,
}: GeneralPreferencesSectionProps) {
  return (
    <>
      {t(trayIconTitleKey)}
      {t(trayIconDescKey)}
      {t(trayIconVisibleKey)}
      {t(trayIconHiddenKey)}
    </>
  );
}
