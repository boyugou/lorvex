import type { RuntimeNavigatorSnapshot } from './platform.logic';

export function readRuntimeNavigatorSnapshot(): RuntimeNavigatorSnapshot | null {
  try {
    const nav = globalThis.navigator;
    if (!nav) {
      return null;
    }
    return {
      userAgent: nav.userAgent,
      maxTouchPoints: nav.maxTouchPoints,
    };
  } catch {
    return null;
  }
}
