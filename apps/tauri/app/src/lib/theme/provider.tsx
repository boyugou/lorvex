import { useCallback, useContext, useMemo, useRef, useState, type ReactNode } from 'react';

import { reportClientError } from '../errors/errorLogging';
import { setPreference } from '@/lib/ipc/settings';
import { PREF_APPEARANCE_PROFILE, PREF_THEME } from '../preferences/keys';
import { ThemeContext } from './context';
import {
  emitThemeChanged,
  getInitialSystemTheme,
  useThemePreferenceBootstrap,
  useThemeRuntimeLifecycle,
} from './lifecycle';
import {
  type AppearanceProfile,
  DEFAULT_APPEARANCE_PROFILE,
  DEFAULT_THEME_MODE,
  normalizeAppearanceProfile,
  normalizeThemeMode,
  type ResolvedTheme,
  type ThemeMode,
} from './model';
import { resolveSystemTheme } from './runtime';

export function ThemeProvider({ children }: { children: ReactNode }) {
  const [mode, setModeState] = useState<ThemeMode>(DEFAULT_THEME_MODE);
  const [appearanceProfile, setAppearanceProfileState] = useState<AppearanceProfile>(
    DEFAULT_APPEARANCE_PROFILE,
  );
  const [systemTheme, setSystemTheme] = useState<'dark' | 'light'>(getInitialSystemTheme);
  const [loaded, setLoaded] = useState(false);

  const resolved: ResolvedTheme = mode === 'system' ? resolveSystemTheme(systemTheme) : mode;
  const latestThemeRef = useRef<{ mode: ThemeMode; resolved: ResolvedTheme }>({ mode, resolved });

  useThemePreferenceBootstrap({
    setAppearanceProfileState,
    setLoaded,
    setModeState,
  });
  useThemeRuntimeLifecycle({
    appearanceProfile,
    latestThemeRef,
    loaded,
    mode,
    resolved,
    setAppearanceProfileState,
    setModeState,
    setSystemTheme,
    systemTheme,
  });

  const setMode = useCallback((nextMode: ThemeMode, options?: { persist?: boolean }) => {
    const normalizedMode = normalizeThemeMode(nextMode) ?? DEFAULT_THEME_MODE;
    setModeState(normalizedMode);
    if (options?.persist !== false) {
      setPreference(PREF_THEME, normalizedMode).catch((error) => {
        reportClientError('theme.setMode', 'Failed to persist theme mode', error, normalizedMode);
      });
    }
    emitThemeChanged(normalizedMode, appearanceProfile);
  }, [appearanceProfile]);

  const setAppearanceProfile = useCallback((profile: AppearanceProfile, options?: { persist?: boolean }) => {
    const normalizedProfile = normalizeAppearanceProfile(profile) ?? DEFAULT_APPEARANCE_PROFILE;
    setAppearanceProfileState(normalizedProfile);
    if (options?.persist !== false) {
      setPreference(PREF_APPEARANCE_PROFILE, normalizedProfile).catch((error) => {
        reportClientError('theme.setAppearanceProfile', 'Failed to persist appearance profile', error, normalizedProfile);
      });
    }
    emitThemeChanged(mode, normalizedProfile);
  }, [mode]);

  const contextValue = useMemo(() => ({
    mode, setMode, appearanceProfile, setAppearanceProfile, resolved,
  }), [mode, setMode, appearanceProfile, setAppearanceProfile, resolved]);

  if (!loaded) return null;

  return (
    <ThemeContext.Provider value={contextValue}>
      {children}
    </ThemeContext.Provider>
  );
}

export function useTheme() {
  return useContext(ThemeContext);
}
