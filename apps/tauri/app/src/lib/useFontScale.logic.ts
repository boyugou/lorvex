import { createBrowserCancelableTimeoutTimerApi } from './browserTimeoutTimerApi';

export const FONT_SCALE_OPTIONS = [
  { value: 0.85, labelKey: 'settings.fontScaleSmall' as const },
  { value: 0.925, labelKey: 'settings.fontScaleCompact' as const },
  { value: 1.0, labelKey: 'settings.fontScaleDefault' as const },
  { value: 1.1, labelKey: 'settings.fontScaleLarge' as const },
  { value: 1.2, labelKey: 'settings.fontScaleExtraLarge' as const },
] as const;

const DEFAULT_FONT_SCALE = 1.0;
const BASE_FONT_SIZE_PX = 16;
const FONT_SCALE_PAYLOADS = new Map(
  FONT_SCALE_OPTIONS.map((option) => [JSON.stringify(option.value), option.value]),
);

export interface FontScaleTimerApi {
  cancel: (handle: unknown) => void;
  schedule: (callback: () => void, delayMs: number) => unknown;
}

export interface FontScaleRootHost {
  addTransitionEndListener: (listener: () => void) => void;
  clearTransition: () => void;
  removeTransitionEndListener: (listener: () => void) => void;
  setFontSizePx: (fontSizePx: number) => void;
  setTransition: (transition: string) => void;
}

const defaultTimerApi: FontScaleTimerApi = createBrowserCancelableTimeoutTimerApi();

interface FontScaleAnimationState {
  cleanupHandle: unknown | null;
  transitionEndListener: (() => void) | null;
}

export function createFontScaleAnimationState(): FontScaleAnimationState {
  return {
    cleanupHandle: null,
    transitionEndListener: null,
  };
}

export function clearPendingFontScaleAnimation(
  host: FontScaleRootHost,
  state: FontScaleAnimationState,
  timerApi: FontScaleTimerApi = defaultTimerApi,
): void {
  if (state.cleanupHandle !== null) {
    timerApi.cancel(state.cleanupHandle);
    state.cleanupHandle = null;
  }
  if (state.transitionEndListener !== null) {
    host.removeTransitionEndListener(state.transitionEndListener);
    state.transitionEndListener = null;
  }
}

export function parseFontScale(raw: string | null): number {
  if (raw == null) return DEFAULT_FONT_SCALE;
  return FONT_SCALE_PAYLOADS.get(raw) ?? DEFAULT_FONT_SCALE;
}

export function snapFontScaleToNearest(value: number): number {
  return FONT_SCALE_OPTIONS.reduce((nearest, option) => (
    Math.abs(option.value - value) < Math.abs(nearest - value) ? option.value : nearest
  ), DEFAULT_FONT_SCALE);
}

export function fontSizePxForScale(scale: number): number {
  return BASE_FONT_SIZE_PX * scale;
}

export function applyFontScale(
  host: FontScaleRootHost,
  scale: number,
  animate: boolean,
  state: FontScaleAnimationState = createFontScaleAnimationState(),
  timerApi: FontScaleTimerApi = defaultTimerApi,
): void {
  clearPendingFontScaleAnimation(host, state, timerApi);
  if (animate) {
    host.setTransition('font-size 0.2s ease');
    const cleanup = () => {
      host.clearTransition();
      state.cleanupHandle = null;
      state.transitionEndListener = null;
    };
    const onTransitionEnd = () => {
      if (state.cleanupHandle !== null) {
        timerApi.cancel(state.cleanupHandle);
      }
      cleanup();
    };
    state.transitionEndListener = onTransitionEnd;
    host.addTransitionEndListener(onTransitionEnd);
    state.cleanupHandle = timerApi.schedule(() => {
      cleanup();
      host.removeTransitionEndListener(onTransitionEnd);
    }, 300);
  } else {
    host.clearTransition();
  }
  host.setFontSizePx(fontSizePxForScale(scale));
}
