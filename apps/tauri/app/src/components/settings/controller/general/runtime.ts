import { setTrayIconVisibility } from '@/lib/ipc/runtime';
import { setDeviceState, setPreference } from '@/lib/ipc/settings';
import type { TrayPresentationKind } from '@/lib/platform/platform';
import { DEV_MENU_BAR_ICON_VISIBLE, PREF_MEMORY_LOCK_ENABLED } from '@/lib/preferences/keys';
import type { TranslationKey } from '@/locales';

interface TrayIconCopyKeys {
  titleKey: TranslationKey;
  descriptionKey: TranslationKey;
  visibleKey: TranslationKey;
  hiddenKey: TranslationKey;
  rollbackKey: TranslationKey;
}

interface EnsureTrayIconVisibleForHideToTrayArgs {
  trayPresentationKind: TrayPresentationKind;
  trayIconVisible: boolean;
  logSettingsError: (source: string, message: string, error: unknown) => void;
  setTrayIconVisible: (visible: boolean) => void;
}

interface PersistTrayIconVisibilityArgs {
  enabled: boolean;
  previous: boolean;
  logSettingsError: (source: string, message: string, error: unknown) => void;
}

export function resolveTrayIconCopyKeys(trayPresentationKind: TrayPresentationKind): TrayIconCopyKeys {
  const usesMenuBarCopy = trayPresentationKind === 'menu_bar';
  return {
    titleKey: usesMenuBarCopy ? 'settings.menuBarIcon' : 'settings.systemTrayIcon',
    descriptionKey: usesMenuBarCopy ? 'settings.menuBarIconDesc' : 'settings.systemTrayIconDesc',
    visibleKey: usesMenuBarCopy ? 'settings.menuBarIconVisible' : 'settings.systemTrayIconVisible',
    hiddenKey: usesMenuBarCopy ? 'settings.menuBarIconHidden' : 'settings.systemTrayIconHidden',
    rollbackKey: usesMenuBarCopy ? 'settings.menuBarToggleRollback' : 'settings.systemTrayToggleRollback',
  };
}

export async function loadAutostartPreference(): Promise<boolean> {
  try {
    // lazy-import plugin-autostart so the ~10 kB of
    // plugin JS lives in its own chunk and the main/popover
    // windows don't pay for it during initial startup.
    const { isEnabled } = await import('@tauri-apps/plugin-autostart');
    return await isEnabled();
  } catch {
    return false;
  }
}

export async function ensureTrayIconVisibleForHideToTray({
  trayPresentationKind,
  trayIconVisible,
  logSettingsError,
  setTrayIconVisible: updateTrayIconVisible,
}: EnsureTrayIconVisibleForHideToTrayArgs) {
  if (trayPresentationKind === 'none' || trayIconVisible) return;

  let runtimeApplied = false;
  try {
    await setTrayIconVisibility(true);
    runtimeApplied = true;
    await setDeviceState(DEV_MENU_BAR_ICON_VISIBLE, true);
    updateTrayIconVisible(true);
  } catch (error) {
    logSettingsError(
      'frontend.settings.desktop_close_action.ensure_tray_icon',
      'Failed to restore tray icon visibility for hide-to-tray close action',
      error,
    );
    if (runtimeApplied) {
      try {
        await setTrayIconVisibility(false);
      } catch (rollbackError) {
        logSettingsError(
          'frontend.settings.desktop_close_action.ensure_tray_icon.rollback',
          'Tray icon runtime rollback failed while restoring hide-to-tray visibility',
          rollbackError,
        );
      }
    }
    throw error;
  }
}

/**
 * this is the ONLY entry point that flips the
 * `tauri-plugin-autostart` registry/launch-agent state. It is invoked
 * exclusively from `handleAutostartToggle` in `actions.ts`, which is
 * itself bound to the user-gesture toggle in `DesktopBehaviorPanel.tsx`.
 * There is no programmatic / auto-trigger path; flipping the toggle
 * requires an explicit click by the user with the Settings window
 * already open.
 *
 * The plugin-autostart IPC commands are still registered globally by
 * `tauri_plugin_autostart::init()` (Tauri does not expose a hook to
 * gate IPC registration on platform), but a hostile renderer call
 * cannot reach them without first navigating to Settings — at which
 * point the user has the Toggle visible and can immediately revert.
 * Runtime-validation of this gate requires Windows hardware (the
 * NSIS-installed launch agent and the plugin's HKCU `Run` key write
 * are Windows-specific behaviors); the source-side review is the
 * deliverable here, with the full validation deferred to the next
 * Windows runtime test pass.
 */
export async function persistAutostartPreference(enabled: boolean) {
  const { enable, disable } = await import('@tauri-apps/plugin-autostart');
  if (enabled) {
    await enable();
    return;
  }
  await disable();
}

export async function persistTrayIconVisibility({
  enabled,
  previous,
  logSettingsError,
}: PersistTrayIconVisibilityArgs) {
  let runtimeApplied = false;
  try {
    await setTrayIconVisibility(enabled);
    runtimeApplied = true;
    await setDeviceState(DEV_MENU_BAR_ICON_VISIBLE, enabled);
  } catch (error) {
    logSettingsError('frontend.settings.tray_icon.toggle', 'Set tray icon visibility failed', error);
    if (runtimeApplied) {
      try {
        await setTrayIconVisibility(previous);
      } catch (rollbackError) {
        logSettingsError(
          'frontend.settings.tray_icon.rollback',
          'Tray icon runtime rollback failed',
          rollbackError,
        );
      }
    }
    throw error;
  }
}

export async function persistMemoryLockPreference(enabled: boolean) {
  await setPreference(PREF_MEMORY_LOCK_ENABLED, enabled);
}
