import { tryParseJson } from '@/lib/security/jsonParse';

export type PlainRecord = Record<string, unknown>;

export function isObjectRecord(value: unknown): value is PlainRecord {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

export function isPlainRecord(value: unknown): value is PlainRecord {
  if (!isObjectRecord(value)) {
    return false;
  }
  const prototype = Object.getPrototypeOf(value);
  return prototype === Object.prototype || prototype === null;
}

export function hasOnlyKeys(
  value: PlainRecord,
  keys: ReadonlySet<string>,
): boolean {
  return Object.keys(value).every((key) => keys.has(key));
}

export function parseJsonRecord(raw: string): PlainRecord | null {
  const parsed = tryParseJson(raw);
  if (!parsed.ok || !isPlainRecord(parsed.value)) {
    return null;
  }
  return parsed.value;
}
