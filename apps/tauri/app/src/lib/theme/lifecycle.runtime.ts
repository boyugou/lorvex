import type { ResolvedTheme, ThemeMode } from './model';

interface ThemeVisibilityDocumentTarget {
  addEventListener: (type: 'visibilitychange', listener: () => void) => void;
  removeEventListener: (type: 'visibilitychange', listener: () => void) => void;
  hidden: boolean;
}

interface ThemeVisibilityWindowTarget {
  addEventListener: (type: 'focus', listener: () => void) => void;
  removeEventListener: (type: 'focus', listener: () => void) => void;
}

interface ThemeVisibilityRefreshRuntimeDeps {
  documentTarget: ThemeVisibilityDocumentTarget;
  reapply: () => void;
  windowTarget: ThemeVisibilityWindowTarget;
}

interface ThemeMediaChangeEventLike {
  matches: boolean;
}

interface ThemeMediaQueryLike {
  addEventListener?: ((type: 'change', listener: (event: ThemeMediaChangeEventLike) => void) => void) | undefined;
  removeEventListener?: ((type: 'change', listener: (event: ThemeMediaChangeEventLike) => void) => void) | undefined;
}

interface ThemeMediaRuntimeDeps {
  applyNativeTheme: (mode: ThemeMode, resolved: ResolvedTheme, options: { force: true }) => void;
  createMediaQueryList: () => ThemeMediaQueryLike;
  readLatestTheme: () => { mode: ThemeMode; resolved: ResolvedTheme };
  resolveSystemTheme: (systemTheme: 'dark' | 'light') => ResolvedTheme;
  setSystemTheme: (systemTheme: 'dark' | 'light') => void;
}

export function resolveThemeMediaSystemTheme(matches: boolean): 'dark' | 'light' {
  return matches ? 'light' : 'dark';
}

export function createBrowserThemeVisibilityRefreshRuntimeDeps(
  reapply: () => void,
): ThemeVisibilityRefreshRuntimeDeps | null {
  if (typeof document === 'undefined' || typeof window === 'undefined') return null;
  return {
    documentTarget: document,
    reapply,
    windowTarget: window,
  };
}

export function createBrowserThemeMediaRuntimeDeps(
  deps: Omit<ThemeMediaRuntimeDeps, 'createMediaQueryList'>,
): ThemeMediaRuntimeDeps | null {
  if (typeof window === 'undefined' || typeof window.matchMedia !== 'function') return null;
  return {
    ...deps,
    createMediaQueryList: () => window.matchMedia('(prefers-color-scheme: light)'),
  };
}

export function installThemeVisibilityRefreshRuntime(
  deps: ThemeVisibilityRefreshRuntimeDeps,
): () => void {
  const onFocus = () => {
    deps.reapply();
  };
  const onVisibilityChange = () => {
    if (!deps.documentTarget.hidden) {
      deps.reapply();
    }
  };

  deps.windowTarget.addEventListener('focus', onFocus);
  deps.documentTarget.addEventListener('visibilitychange', onVisibilityChange);

  return () => {
    deps.windowTarget.removeEventListener('focus', onFocus);
    deps.documentTarget.removeEventListener('visibilitychange', onVisibilityChange);
  };
}

export function installThemeMediaRuntime(deps: ThemeMediaRuntimeDeps): () => void {
  let mediaQuery: ThemeMediaQueryLike;
  try {
    mediaQuery = deps.createMediaQueryList();
  } catch {
    return () => {};
  }

  const onChange = (event: ThemeMediaChangeEventLike) => {
    const nextSystemTheme = resolveThemeMediaSystemTheme(event.matches);
    deps.setSystemTheme(nextSystemTheme);
    const latest = deps.readLatestTheme();
    const nextResolved =
      latest.mode === 'system' ? deps.resolveSystemTheme(nextSystemTheme) : latest.resolved;
    deps.applyNativeTheme(latest.mode, nextResolved, { force: true });
  };

  if (
    typeof mediaQuery.addEventListener === 'function'
    && typeof mediaQuery.removeEventListener === 'function'
  ) {
    mediaQuery.addEventListener('change', onChange);
    return () => mediaQuery.removeEventListener?.('change', onChange);
  }

  return () => {};
}
