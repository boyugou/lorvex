import {
  APPEARANCE_PROFILES,
  THEME_MODES,
  type AppearanceProfile,
  type ThemeMode,
} from '@lorvex/shared/types';
import type { TranslationKey } from '@/locales';
import { parseJsonValueOrNull } from '../security/jsonParse';

export type { AppearanceProfile, ThemeMode } from '@lorvex/shared/types';

export type ResolvedTheme = Exclude<ThemeMode, 'system'>;
type ThemeTone = 'dark' | 'light' | 'system';

export const DEFAULT_THEME_MODE: ThemeMode = 'system';
export const DEFAULT_APPEARANCE_PROFILE: AppearanceProfile = 'clarity';

export function isLightTheme(resolved: ResolvedTheme): boolean {
  return resolved === 'light'
    || resolved === 'paper'
    || resolved === 'liquid_light'
    || resolved === 'mica_light'
    || resolved === 'adwaita_light';
}

export function normalizeThemeMode(value: unknown): ThemeMode | null {
  if (typeof value !== 'string') return null;
  const normalized = value.trim().toLowerCase();
  if (!THEME_MODES.includes(normalized as ThemeMode)) return null;
  return normalized as ThemeMode;
}

export function normalizeAppearanceProfile(value: unknown): AppearanceProfile | null {
  if (typeof value !== 'string') return null;
  const normalized = value.trim().toLowerCase();
  if (!APPEARANCE_PROFILES.includes(normalized as AppearanceProfile)) return null;
  return normalized as AppearanceProfile;
}

export function normalizeStoredThemePreference(
  raw: string | null,
): { mode: ThemeMode; shouldMigrate: boolean } {
  if (raw === null) {
    return { mode: DEFAULT_THEME_MODE, shouldMigrate: false };
  }
  const parsed = parseJsonValueOrNull(raw);
  const normalized = normalizeThemeMode(parsed);
  return {
    mode: normalized ?? DEFAULT_THEME_MODE,
    shouldMigrate: !normalized || raw !== JSON.stringify(normalized),
  };
}

export function normalizeStoredAppearanceProfilePreference(
  raw: string | null,
): { profile: AppearanceProfile; shouldMigrate: boolean } {
  if (raw === null) {
    return { profile: DEFAULT_APPEARANCE_PROFILE, shouldMigrate: false };
  }
  const parsed = parseJsonValueOrNull(raw);
  const normalized = normalizeAppearanceProfile(parsed);
  return {
    profile: normalized ?? DEFAULT_APPEARANCE_PROFILE,
    shouldMigrate: !normalized || raw !== JSON.stringify(normalized),
  };
}

export interface ThemeOption {
  value: ThemeMode;
  labelKey: TranslationKey;
  tone: ThemeTone;
}

interface AppearanceProfileOption {
  value: AppearanceProfile;
  labelKey: TranslationKey;
}

const baseThemeOptions: ThemeOption[] = [
  { value: 'paper', labelKey: 'settings.themePaper', tone: 'light' },
  { value: 'light', labelKey: 'settings.themeLight', tone: 'light' },
  { value: 'dark', labelKey: 'settings.themeDark', tone: 'dark' },
  { value: 'ember', labelKey: 'settings.themeEmber', tone: 'dark' },
  { value: 'midnight', labelKey: 'settings.themeMidnight', tone: 'dark' },
  { value: 'liquid', labelKey: 'settings.themeLiquidGlass', tone: 'dark' },
  { value: 'liquid_light', labelKey: 'settings.themeLiquidGlassLight', tone: 'light' },
  { value: 'mica', labelKey: 'settings.themeMica', tone: 'dark' },
  { value: 'mica_light', labelKey: 'settings.themeMicaLight', tone: 'light' },
  { value: 'adwaita', labelKey: 'settings.themeAdwaita', tone: 'dark' },
  { value: 'adwaita_light', labelKey: 'settings.themeAdwaitaLight', tone: 'light' },
  { value: 'system', labelKey: 'settings.themeSystem', tone: 'system' },
];

const baseAppearanceProfileOptions: AppearanceProfileOption[] = [
  { value: 'clarity', labelKey: 'settings.appearanceProfileClarity' },
  { value: 'studio', labelKey: 'settings.appearanceProfileStudio' },
  { value: 'focus_compact', labelKey: 'settings.appearanceProfileFocusCompact' },
  { value: 'liquid_glass', labelKey: 'settings.appearanceProfileLiquidGlass' },
];

export const THEME_OPTIONS = baseThemeOptions;
export const APPEARANCE_PROFILE_OPTIONS = baseAppearanceProfileOptions;
