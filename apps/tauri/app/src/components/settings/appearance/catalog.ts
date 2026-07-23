import type { ThemeMode } from '@/lib/theme';
import type { ThemePreviewMap, ThemePreviewPalette } from './types';

/**
 * Static fallback palette per theme — the values are kept loosely in
 * sync with `app/src/styles/themes.css` so a non-active theme card
 * still paints a recognizable swatch even before any DOM has been
 * mounted with that theme applied. The active theme's palette is
 * always read live from `getComputedStyle(document.documentElement)`
 * via {@link resolveThemePalette} so retunes to the live tokens
 * surface immediately in the lane swatch (which is what the user is
 * comparing against the running canvas).
 */
const THEME_PREVIEW: ThemePreviewMap = {
  paper: { canvas: '#fbf8f1', panel: '#f5f1e9', accent: '#9b5527', text: '#2a2118' },
  light: { canvas: '#fcfcfc', panel: '#f5f5f5', accent: '#366eca', text: '#1c1c1e' },
  dark: { canvas: '#0f0f0f', panel: '#1a1a1a', accent: '#4f8ef7', text: '#f0f0f0' },
  ember: { canvas: '#140b0a', panel: '#201312', accent: '#eb7e5a', text: '#fcf1ec' },
  midnight: { canvas: '#040810', panel: '#0a0f1a', accent: '#5cd3ff', text: '#f8fbff' },
  liquid: { canvas: '#1c1c1e', panel: '#2c2c2e', accent: '#0a84ff', text: '#ffffff' },
  liquid_light: { canvas: '#f2f2f7', panel: '#ffffff', accent: '#007aff', text: '#000000' },
  mica: { canvas: '#202020', panel: '#2d2d2d', accent: '#60cdff', text: '#ffffff' },
  mica_light: { canvas: '#f3f3f3', panel: '#ffffff', accent: '#005fb8', text: '#1a1a1a' },
  adwaita: { canvas: '#222226', panel: '#2e2e32', accent: '#78aeed', text: '#ffffff' },
  adwaita_light: { canvas: '#fafafb', panel: '#ebebed', accent: '#1c71d8', text: '#1a1a1a' },
};

/**
 * Resolve a theme's preview palette. For the currently active theme
 * the four swatch colors are read live from the document root via
 * `getComputedStyle`, so retunes to `--color-surface-0/-1`, `--color-accent`,
 * and `--color-text-primary` in `themes.css` surface in the preview
 * card without a parallel catalog edit. For non-active themes the
 * static fallback is returned (mounting a hidden scoped node would
 * require lifting the theme rules out of `:root[data-theme='X']`,
 * which is out of scope here). The result is that the user always
 * sees an exact match between the card for their current theme and
 * the canvas behind it.
 */
export function resolveThemePalette(
  mode: Exclude<ThemeMode, 'system'>,
  activeMode: Exclude<ThemeMode, 'system'>,
): ThemePreviewPalette {
  const fallback = THEME_PREVIEW[mode];
  if (typeof document === 'undefined' || mode !== activeMode) return fallback;
  const cs = getComputedStyle(document.documentElement);
  const read = (token: string, fallbackValue: string) => {
    const raw = cs.getPropertyValue(token).trim();
    return raw.length > 0 ? raw : fallbackValue;
  };
  return {
    canvas: read('--color-surface-0', fallback.canvas),
    panel: read('--color-surface-1', fallback.panel),
    accent: read('--color-accent', fallback.accent),
    text: read('--color-text-primary', fallback.text),
  };
}
