import { tryParseJson } from './security/jsonParse';
import { hasOnlyKeys, isPlainRecord as isRecord } from './objectGuards';

export interface UpdateCheckCacheEntry {
  version: string | null;
  checkedAt: number;
  appVersion: string;
}

const CACHE_ENTRY_KEYS = new Set(['version', 'checkedAt', 'appVersion']);

function hasExactCacheEntryKeys(value: Record<string, unknown>): boolean {
  const keys = Object.keys(value);
  return keys.length === CACHE_ENTRY_KEYS.size && hasOnlyKeys(value, CACHE_ENTRY_KEYS);
}

export function parseUpdateCheckCacheEntry(
  raw: string | null,
  appVersion: string,
): UpdateCheckCacheEntry | null {
  if (!raw) return null;

  const parseResult = tryParseJson(raw);
  if (!parseResult.ok) return null;

  const parsed = parseResult.value;
  if (!isRecord(parsed)) return null;
  if (!hasExactCacheEntryKeys(parsed)) return null;
  if (parsed.appVersion !== appVersion) return null;
  if (
    typeof parsed.checkedAt !== 'number'
    || !Number.isFinite(parsed.checkedAt)
    || !Number.isInteger(parsed.checkedAt)
  ) {
    return null;
  }

  const version = parsed.version;
  if (version !== null && version !== undefined && typeof version !== 'string') {
    return null;
  }

  return {
    version: version ?? null,
    checkedAt: parsed.checkedAt,
    appVersion,
  };
}

export function isFreshUpdateCheckCacheEntry(
  entry: UpdateCheckCacheEntry,
  now: number,
  ttlMs: number,
): boolean {
  return entry.checkedAt <= now && now - entry.checkedAt < ttlMs;
}
