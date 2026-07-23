import type { TranslationKey } from '../../../locales/types';

interface DesktopBehaviorPanelProps {
  trayIconTitleKey: TranslationKey;
  trayIconDescKey: TranslationKey;
  trayIconVisibleKey: TranslationKey;
  trayIconHiddenKey: TranslationKey;
}

const t = (key: TranslationKey): string => key;

export function DesktopBehaviorPanel({
  trayIconTitleKey,
  trayIconDescKey,
  trayIconVisibleKey,
  trayIconHiddenKey,
}: DesktopBehaviorPanelProps) {
  return (
    <>
      {t(trayIconTitleKey)}
      {t(trayIconDescKey)}
      {t(trayIconVisibleKey)}
      {t(trayIconHiddenKey)}
    </>
  );
}
