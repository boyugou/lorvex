const platformCapabilities = { isMacDesktop: true };

const trayIconTitleKey = platformCapabilities.isMacDesktop
  ? 'settings.menuBarIcon'
  : 'settings.systemTrayIcon';

const trayIconDescKey = platformCapabilities.isMacDesktop
  ? 'settings.menuBarIconDesc'
  : 'settings.systemTrayIconDesc';

const trayIconVisibleKey = platformCapabilities.isMacDesktop
  ? 'settings.menuBarIconVisible'
  : 'settings.systemTrayIconVisible';

const trayIconHiddenKey = platformCapabilities.isMacDesktop
  ? 'settings.menuBarIconHidden'
  : 'settings.systemTrayIconHidden';

const trayIconToggleRollbackKey = platformCapabilities.isMacDesktop
  ? 'settings.menuBarToggleRollback'
  : 'settings.systemTrayToggleRollback';

export {
  trayIconDescKey,
  trayIconHiddenKey,
  trayIconTitleKey,
  trayIconToggleRollbackKey,
  trayIconVisibleKey,
};
