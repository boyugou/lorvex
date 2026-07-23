import type { NavigatorConnectionLike } from './network';

export function readBrowserNavigatorConnection(): NavigatorConnectionLike | null {
  try {
    const nav = globalThis.navigator as Navigator & { connection?: NavigatorConnectionLike } | undefined;
    return nav?.connection ?? null;
  } catch {
    return null;
  }
}
