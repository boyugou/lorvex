/**
 * Font scale preference — allows users to adjust the global text size.
 *
 * Applies a CSS `font-size` on `<html>` that scales all `rem`-based sizes.
 *
 * Scale values: 0.85 (Small), 0.925 (Compact), 1.0 (Default), 1.1 (Large), 1.2 (Extra Large)
 */

import { useEffect, useRef } from 'react';
import { usePreference } from './query/usePreference';
import { STALE_LONG } from './query/timing';
import { PREF_FONT_SCALE } from './preferences/keys';
import { useLazyRef } from './useLazyRef';
import { applyFontScale, createFontScaleAnimationState, parseFontScale } from './useFontScale.logic';
import { createBrowserFontScaleRootHost } from './useFontScale.runtime';

export { FONT_SCALE_OPTIONS } from './useFontScale.logic';

/**
 * Internal — read the user's font-scale preference and apply it as
 * a CSS `font-size` on `<html>`. Returns the live scale + a setter
 * so the settings UI can read/write. App.tsx only needs the side
 * effect, so it calls {@link useFontScaleApply} instead of
 * discarding this hook's return value at the call site.
 */
export function useFontScale(): { scale: number; setScale: (value: number) => void } {
  const hasApplied = useRef(false);
  const animationStateRef = useLazyRef(() => createFontScaleAnimationState());
  const { value: scale, set: setScale } = usePreference(
    PREF_FONT_SCALE,
    parseFontScale,
    { staleTime: STALE_LONG },
  );

  useEffect(() => {
    const host = createBrowserFontScaleRootHost();
    if (!host) {
      return;
    }

    applyFontScale(
      host,
      scale,
      hasApplied.current,
      animationStateRef.current,
    );
    hasApplied.current = true;
    // animationStateRef is a stable MutableRefObject from useLazyRef.
  }, [scale, animationStateRef]);

  return {
    scale,
    setScale: (value: number) => { void setScale(value); },
  };
}

/**
 * Side-effect-only variant of {@link useFontScale}. App.tsx mounts
 * this once at the top of every window so the user's font-scale
 * preference is applied to `<html>` before any view renders. The
 * read/write API is intentionally hidden here so the App-level call
 * doesn't drop a meaningful return value.
 */
export function useFontScaleApply(): void {
  useFontScale();
}
