import { createContext } from 'react';

import {
  DEFAULT_APPEARANCE_PROFILE,
  DEFAULT_THEME_MODE,
  type AppearanceProfile,
  type ResolvedTheme,
  type ThemeMode,
} from './model';

export interface ThemeContextValue {
  mode: ThemeMode;
  setMode: (mode: ThemeMode, options?: { persist?: boolean }) => void;
  appearanceProfile: AppearanceProfile;
  setAppearanceProfile: (profile: AppearanceProfile, options?: { persist?: boolean }) => void;
  resolved: ResolvedTheme;
}

export const ThemeContext = createContext<ThemeContextValue>({
  mode: DEFAULT_THEME_MODE,
  setMode: () => {},
  appearanceProfile: DEFAULT_APPEARANCE_PROFILE,
  setAppearanceProfile: () => {},
  resolved: 'dark',
});
