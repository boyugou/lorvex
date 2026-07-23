const trayPresentationKind = 'menu_bar';

const trayCopy = trayPresentationKind === 'menu_bar'
  ? 'settings.menuBarIcon'
  : 'settings.systemTrayIcon';

const rollbackCopy = trayPresentationKind === 'menu_bar'
  ? 'settings.menuBarToggleRollback'
  : 'settings.systemTrayToggleRollback';

export { trayCopy, rollbackCopy };
