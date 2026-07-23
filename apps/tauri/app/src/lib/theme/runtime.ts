import { setTheme as setNativeTheme } from '@tauri-apps/api/app';

import { reportClientError } from '../errors/errorLogging';
import { setNativeWindowEffects } from '../ipc/runtime';
import { getRuntimeId } from '../platform/platform';
import { isTauriRuntimeAvailable } from '../platform/tauriRuntime';
import type { AppearanceProfile, ThemeMode } from './model';
import { isLightTheme, type ResolvedTheme } from './model';

interface ThemeDocumentHost {
  getRoot: () => HTMLElement | null;
}

interface ThemeSystemPreferenceHost {
  readSystemPreference: () => 'dark' | 'light' | null;
}

export function createBrowserThemeDocumentHost(): ThemeDocumentHost {
  return {
    getRoot: () => {
      try {
        return globalThis.document?.documentElement ?? null;
      } catch {
        return null;
      }
    },
  };
}

export function createBrowserThemeSystemPreferenceHost(): ThemeSystemPreferenceHost {
  return {
    readSystemPreference: () => {
      try {
        const matchMedia = globalThis.window?.matchMedia;
        if (typeof matchMedia !== 'function') return null;
        return matchMedia.call(globalThis.window, '(prefers-color-scheme: light)').matches
          ? 'light'
          : 'dark';
      } catch {
        return null;
      }
    },
  };
}

const themeDocumentHost = createBrowserThemeDocumentHost();
const themeSystemPreferenceHost = createBrowserThemeSystemPreferenceHost();

function getDocumentRoot(): HTMLElement | null {
  return themeDocumentHost.getRoot();
}

function readSystemPreference(): 'dark' | 'light' | null {
  return themeSystemPreferenceHost.readSystemPreference();
}

export function getSystemTheme(): 'dark' | 'light' {
  return readSystemPreference() ?? 'dark';
}

/**
 * Map the raw OS colour-scheme preference to a concrete theme token.
 *
 * On Linux, Adwaita is the standard GTK theme (used by GNOME, elementary, and
 * most GTK-based desktop environments — which is exactly the rendering engine
 * Tauri uses via webkit2gtk). Default Linux to the Adwaita pair so that "System"
 * feels native out of the box.
 *
 * Other platforms keep the generic `dark` / `light` tokens.
 */
export function resolveSystemTheme(systemPreference: 'dark' | 'light'): ResolvedTheme {
  if (getRuntimeId() === 'linux') {
    return systemPreference === 'light' ? 'adwaita_light' : 'adwaita';
  }
  if (getRuntimeId() === 'windows') {
    return systemPreference === 'light' ? 'mica_light' : 'mica';
  }
  return systemPreference;
}

export function applyTheme(resolved: ResolvedTheme) {
  const root = getDocumentRoot();
  if (!root) return;

  root.setAttribute('data-theme', resolved);
  if (isLightTheme(resolved)) {
    root.classList.add('light');
  } else {
    root.classList.remove('light');
  }

  if (isTauriRuntimeAvailable()) {
    void setNativeWindowEffects(resolved).catch((error: unknown) => {
      reportClientError(
        'theme.setNativeWindowEffects',
        'Failed to apply native window effects for theme',
        error,
        resolved,
        'warn',
      );
    });
  }
}

export function applyAppearanceProfile(profile: AppearanceProfile) {
  getDocumentRoot()?.setAttribute('data-appearance-profile', profile);
}

export function applySystemThemeAttribute(systemTheme: 'dark' | 'light') {
  getDocumentRoot()?.setAttribute('data-system-theme', systemTheme);
}

export function getThemeWindowKind(): string | null {
  return getDocumentRoot()?.getAttribute('data-window-kind') ?? null;
}

function toNativeTheme(mode: ThemeMode, resolved: ResolvedTheme): 'light' | 'dark' | null {
  if (mode === 'system') return null;
  return isLightTheme(resolved) ? 'light' : 'dark';
}

let nativeThemeWarningLogged = false;
let lastNativeThemeApplied: 'light' | 'dark' | null | undefined;

export function shouldApplyNativeTheme(args: {
  force: boolean;
  lastApplied: 'light' | 'dark' | null | undefined;
  nextNativeTheme: 'light' | 'dark' | null;
}): boolean {
  return args.force || args.lastApplied !== args.nextNativeTheme;
}

export function applyNativeTheme(
  mode: ThemeMode,
  resolved: ResolvedTheme,
  options?: { force?: boolean },
) {
  // Only the main window should control app-level native chrome theme.
  // Overlay windows (focus/popover) can otherwise race and flip titlebar
  // appearance back to stale values.
  if (getThemeWindowKind() === 'overlay') return;
  if (!isTauriRuntimeAvailable()) return;

  const nativeTheme = toNativeTheme(mode, resolved);
  if (!shouldApplyNativeTheme({
    force: options?.force ?? false,
    lastApplied: lastNativeThemeApplied,
    nextNativeTheme: nativeTheme,
  })) {
    return;
  }

  // Keep native macOS titlebar/chrome aligned with in-app theme tokens.
  void setNativeTheme(nativeTheme).then(() => {
    lastNativeThemeApplied = nativeTheme;
  }).catch((error: unknown) => {
    lastNativeThemeApplied = undefined;
    if (nativeThemeWarningLogged) return;
    nativeThemeWarningLogged = true;
    // upgrade the one-time console.warn to a durable
    // error_logs entry so bug reports can surface the "dark-mode
    // toggle did nothing" class of failure instead of it being
    // visible only in Console.app on developer machines.
    reportClientError(
      'theme.setNativeTheme',
      'Failed to apply native app theme; continuing with web theme only',
      error,
      nativeTheme ?? 'system',
      'warn',
    );
  });
}
