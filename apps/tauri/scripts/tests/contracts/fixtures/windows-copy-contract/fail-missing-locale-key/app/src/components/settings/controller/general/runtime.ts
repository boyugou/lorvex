const trayPresentationKind = 'menu_bar';

const trayIconTitleKey = trayPresentationKind === 'menu_bar'
  ? 'settings.menuBarIcon'
  : 'settings.systemTrayIcon';

const trayIconDescKey = trayPresentationKind === 'menu_bar'
  ? 'settings.menuBarIconDesc'
  : 'settings.systemTrayIconDesc';

const trayIconVisibleKey = trayPresentationKind === 'menu_bar'
  ? 'settings.menuBarIconVisible'
  : 'settings.systemTrayIconVisible';

const trayIconHiddenKey = trayPresentationKind === 'menu_bar'
  ? 'settings.menuBarIconHidden'
  : 'settings.systemTrayIconHidden';

const trayIconToggleRollbackKey = trayPresentationKind === 'menu_bar'
  ? 'settings.menuBarToggleRollback'
  : 'settings.systemTrayToggleRollback';

export {
  trayIconDescKey,
  trayIconHiddenKey,
  trayIconTitleKey,
  trayIconToggleRollbackKey,
  trayIconVisibleKey,
};
