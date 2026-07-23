import {
  isFreshUpdateCheckCacheEntry,
  parseUpdateCheckCacheEntry,
  type UpdateCheckCacheEntry,
} from './checkForUpdateCached.logic';
import { safeLocalStorage } from './storage';

interface CheckForUpdateCachedRuntimeDeps {
  appVersionFallback: string;
  isOffline: () => boolean;
  now: () => number;
  readStorage: () => string | null;
  ttlMs: number;
  getVersion: () => Promise<string>;
  checkForUpdate: () => Promise<string | null>;
  setInflight: (inflight: Promise<string | null> | null) => void;
  getInflight: () => Promise<string | null> | null;
  writeStorage: (value: string) => void;
}

type BrowserCheckForUpdateCachedRuntimeInput = Omit<
  CheckForUpdateCachedRuntimeDeps,
  'isOffline' | 'readStorage' | 'writeStorage'
> & {
  cacheKey: string;
};

export function isBrowserUpdateCheckOffline(): boolean {
  try {
    return globalThis.navigator?.onLine === false;
  } catch {
    return false;
  }
}

export function createBrowserCheckForUpdateCachedRuntimeDeps(
  input: BrowserCheckForUpdateCachedRuntimeInput,
): CheckForUpdateCachedRuntimeDeps {
  const { cacheKey, ...deps } = input;
  return {
    ...deps,
    isOffline: isBrowserUpdateCheckOffline,
    readStorage: () => safeLocalStorage()?.getItem(cacheKey) ?? null,
    writeStorage: (value) => {
      safeLocalStorage()?.setItem(cacheKey, value);
    },
  };
}

export async function checkForUpdateCachedRuntime(
  deps: CheckForUpdateCachedRuntimeDeps,
): Promise<string | null> {
  if (deps.isOffline()) {
    return null;
  }

  const existingInflight = deps.getInflight();
  if (existingInflight) {
    return existingInflight;
  }

  const inflight = (async () => {
    const appVersion = await readAppVersion(deps);
    const cached = readCache(deps, appVersion);
    if (cached && isFreshUpdateCheckCacheEntry(cached, deps.now(), deps.ttlMs)) {
      return cached.version;
    }

    const version = await deps.checkForUpdate();
    writeCache(deps, {
      version,
      checkedAt: deps.now(),
      appVersion,
    });
    return version;
  })().finally(() => {
    deps.setInflight(null);
  });

  deps.setInflight(inflight);
  return inflight;
}

async function readAppVersion(
  deps: Pick<CheckForUpdateCachedRuntimeDeps, 'appVersionFallback' | 'getVersion'>,
): Promise<string> {
  try {
    return await deps.getVersion();
  } catch {
    return deps.appVersionFallback;
  }
}

function readCache(
  deps: Pick<CheckForUpdateCachedRuntimeDeps, 'readStorage'>,
  appVersion: string,
): UpdateCheckCacheEntry | null {
  try {
    return parseUpdateCheckCacheEntry(deps.readStorage(), appVersion);
  } catch {
    return null;
  }
}

function writeCache(
  deps: Pick<CheckForUpdateCachedRuntimeDeps, 'writeStorage'>,
  entry: UpdateCheckCacheEntry,
): void {
  try {
    deps.writeStorage(JSON.stringify(entry));
  } catch {
    // Non-fatal: quota exhaustion / private mode means the next
    // session re-checks instead of reusing the cache.
  }
}
