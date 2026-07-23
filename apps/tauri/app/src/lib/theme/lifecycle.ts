import { emit, listen } from '@tauri-apps/api/event';
import { getCurrentWindow } from '@tauri-apps/api/window';
import {
  useCallback,
  useEffect,
  type Dispatch,
  type RefObject,
  type SetStateAction,
} from 'react';

import { reportClientError } from '../errors/errorLogging';
import { getPreference, setPreference } from '@/lib/ipc/settings';
import { isTauriRuntimeAvailable } from '../platform/tauriRuntime';
import { PREF_APPEARANCE_PROFILE, PREF_THEME } from '../preferences/keys';
import { createAsyncTauriListenerScope } from '../tauriListenerLifecycle';
import {
  type AppearanceProfile,
  normalizeAppearanceProfile,
  normalizeStoredAppearanceProfilePreference,
  normalizeStoredThemePreference,
  normalizeThemeMode,
  type ResolvedTheme,
  type ThemeMode,
} from './model';
import {
  applyAppearanceProfile,
  applyNativeTheme,
  applySystemThemeAttribute,
  applyTheme,
  getSystemTheme,
  getThemeWindowKind,
  resolveSystemTheme,
} from './runtime';
import {
  createBrowserThemeMediaRuntimeDeps,
  createBrowserThemeVisibilityRefreshRuntimeDeps,
  installThemeMediaRuntime,
  installThemeVisibilityRefreshRuntime,
} from './lifecycle.runtime';

/** Cross-window theme sync event name. */
const THEME_CHANGED_EVENT = 'theme://changed';

interface ThemeChangedPayload {
  mode: ThemeMode;
  appearanceProfile: AppearanceProfile;
}

/** Broadcast a theme change to all other windows. */
export function emitThemeChanged(mode: ThemeMode, appearanceProfile: AppearanceProfile) {
  if (!isTauriRuntimeAvailable()) return;
  emit(THEME_CHANGED_EVENT, { mode, appearanceProfile } satisfies ThemeChangedPayload).catch(() => {
    // Silently ignore — cross-window sync is best-effort.
  });
}

type ThemeStateSetter<T> = Dispatch<SetStateAction<T>>;

interface ThemeBootstrapParams {
  setAppearanceProfileState: ThemeStateSetter<AppearanceProfile>;
  setLoaded: ThemeStateSetter<boolean>;
  setModeState: ThemeStateSetter<ThemeMode>;
}

interface ThemeRuntimeLifecycleParams {
  appearanceProfile: AppearanceProfile;
  latestThemeRef: RefObject<{ mode: ThemeMode; resolved: ResolvedTheme }>;
  loaded: boolean;
  mode: ThemeMode;
  resolved: ResolvedTheme;
  setAppearanceProfileState: ThemeStateSetter<AppearanceProfile>;
  setModeState: ThemeStateSetter<ThemeMode>;
  setSystemTheme: ThemeStateSetter<'dark' | 'light'>;
  systemTheme: 'dark' | 'light';
}

export function getInitialSystemTheme(): 'dark' | 'light' {
  return getSystemTheme();
}

export function useThemePreferenceBootstrap({
  setAppearanceProfileState,
  setLoaded,
  setModeState,
}: ThemeBootstrapParams) {
  useEffect(() => {
    let cancelled = false;

    if (!isTauriRuntimeAvailable()) {
      setLoaded(true);
      return () => {
        cancelled = true;
      };
    }

    Promise.all([
      getPreference(PREF_THEME),
      getPreference(PREF_APPEARANCE_PROFILE),
    ]).then(([rawTheme, rawAppearanceProfile]) => {
      if (cancelled) return;

      const { mode: normalizedMode, shouldMigrate: shouldMigrateTheme } =
        normalizeStoredThemePreference(rawTheme);
      const {
        profile: normalizedAppearanceProfile,
        shouldMigrate: shouldMigrateAppearanceProfile,
      } = normalizeStoredAppearanceProfilePreference(rawAppearanceProfile);

      setModeState(normalizedMode);
      setAppearanceProfileState(normalizedAppearanceProfile);
      if (shouldMigrateTheme) {
        setPreference(PREF_THEME, normalizedMode).catch((error) => {
          reportClientError(
            'theme.migrateMode',
            'Failed to migrate stored theme preference',
            error,
            normalizedMode,
          );
        });
      }
      if (shouldMigrateAppearanceProfile) {
        setPreference(PREF_APPEARANCE_PROFILE, normalizedAppearanceProfile).catch((error) => {
          reportClientError(
            'theme.migrateAppearanceProfile',
            'Failed to migrate stored appearance profile',
            error,
            normalizedAppearanceProfile,
          );
        });
      }
      setLoaded(true);
    }).catch((error) => {
      if (cancelled) return;
      reportClientError('theme.loadPreferences', 'Failed to load theme preferences', error);
      setLoaded(true);
    });

    return () => {
      cancelled = true;
    };
  }, [setAppearanceProfileState, setLoaded, setModeState]);
}

export function useThemeRuntimeLifecycle({
  appearanceProfile,
  latestThemeRef,
  loaded,
  mode,
  resolved,
  setAppearanceProfileState,
  setModeState,
  setSystemTheme,
  systemTheme,
}: ThemeRuntimeLifecycleParams) {
  useEffect(() => {
    latestThemeRef.current = { mode, resolved };
  }, [latestThemeRef, mode, resolved]);

  useEffect(() => {
    applySystemThemeAttribute(systemTheme);
  }, [systemTheme]);

  const reapplyNativeTheme = useCallback(() => {
    const latest = latestThemeRef.current;
    applyNativeTheme(latest.mode, latest.resolved, { force: true });
  }, [latestThemeRef]);

  useEffect(() => {
    if (!loaded) return;
    applyTheme(resolved);
    applyAppearanceProfile(appearanceProfile);
    reapplyNativeTheme();
  }, [appearanceProfile, loaded, reapplyNativeTheme, resolved]);

  useEffect(() => {
    if (!loaded) return;
    const deps = createBrowserThemeVisibilityRefreshRuntimeDeps(reapplyNativeTheme);
    if (!deps) return;
    return installThemeVisibilityRefreshRuntime(deps);
  }, [loaded, reapplyNativeTheme]);

  useEffect(() => {
    const deps = createBrowserThemeMediaRuntimeDeps({
      applyNativeTheme,
      readLatestTheme: () => latestThemeRef.current,
      resolveSystemTheme,
      setSystemTheme,
    });
    if (!deps) return;
    return installThemeMediaRuntime(deps);
  }, [latestThemeRef, setSystemTheme]);

  useEffect(() => {
    if (!loaded) return;
    if (!isTauriRuntimeAvailable()) return;
    if (getThemeWindowKind() === 'overlay') return;

    const listeners = createAsyncTauriListenerScope();
    const reapply = () => reapplyNativeTheme();

    listeners.add(
      getCurrentWindow().onFocusChanged(({ payload: focused }) => {
        if (focused) reapply();
      }),
      (error) => {
        reportClientError('theme.listenFocus', 'Failed to subscribe to native focus changes', error);
      },
    );

    listeners.add(
      getCurrentWindow().onThemeChanged(() => {
        reapply();
      }),
      (error) => {
        reportClientError(
          'theme.listenNativeTheme',
          'Failed to subscribe to native theme changes',
          error,
        );
      },
    );

    return () => {
      listeners.dispose();
    };
  }, [loaded, reapplyNativeTheme]);

  // Cross-window theme sync: listen for theme changes from other windows.
  useEffect(() => {
    if (!loaded) return;
    if (!isTauriRuntimeAvailable()) return;
    const listeners = createAsyncTauriListenerScope();

    listeners.add(
      listen<ThemeChangedPayload>(THEME_CHANGED_EVENT, (event) => {
        const { mode: incomingMode, appearanceProfile: incomingProfile } = event.payload;
        const validMode = normalizeThemeMode(incomingMode);
        const validProfile = normalizeAppearanceProfile(incomingProfile);
        if (validMode) setModeState(validMode);
        if (validProfile) setAppearanceProfileState(validProfile);
      }),
      (error) => {
        reportClientError('theme.crossWindowSync', 'Failed to listen for cross-window theme changes', error);
      },
    );

    return () => {
      listeners.dispose();
    };
  }, [loaded, setModeState, setAppearanceProfileState]);
}
