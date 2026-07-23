import { isObjectRecord } from '../objectGuards';

export function toCamelArgKey(key: string): string {
  if (!key.includes('_')) return key;
  return key.replace(/_([a-zA-Z0-9])/g, (_, ch: string) => ch.toUpperCase());
}

export function normalizeInvokePayload(
  payload?: Record<string, unknown>,
): Record<string, unknown> | undefined {
  if (!payload) return payload;
  const normalized: Record<string, unknown> = {};
  for (const [key, descriptor] of Object.entries(Object.getOwnPropertyDescriptors(payload))) {
    if (!descriptor.enumerable || !('value' in descriptor)) {
      continue;
    }
    normalized[toCamelArgKey(key)] = descriptor.value;
  }
  return normalized;
}

function getOwnField(record: Record<string, unknown>, key: string): unknown {
  const descriptor = Object.getOwnPropertyDescriptor(record, key);
  return descriptor && 'value' in descriptor ? descriptor.value : undefined;
}

function findSafeDataProperty(value: object, key: string): unknown {
  let current: object | null = value;
  while (current) {
    const descriptor = Object.getOwnPropertyDescriptor(current, key);
    if (descriptor) return 'value' in descriptor ? descriptor.value : undefined;
    current = Object.getPrototypeOf(current) as object | null;
  }
  return undefined;
}

function findOwnSafeDataProperty(value: object, key: string): unknown {
  const descriptor = Object.getOwnPropertyDescriptor(value, key);
  return descriptor && 'value' in descriptor ? descriptor.value : undefined;
}

function toJsonSafeValue(value: unknown, seen: WeakSet<object>): unknown {
  if (value === null || typeof value === 'string' || typeof value === 'number') return value;
  if (typeof value === 'boolean') return value;
  if (typeof value !== 'object') return undefined;
  if (seen.has(value)) return undefined;

  seen.add(value);
  if (value instanceof Date) {
    const time = Date.prototype.getTime.call(value);
    seen.delete(value);
    return Number.isFinite(time) ? Date.prototype.toISOString.call(value) : null;
  }

  const toJSON = findOwnSafeDataProperty(value, 'toJSON');
  if (typeof toJSON === 'function') {
    try {
      const jsonValue = toJSON.call(value);
      seen.delete(value);
      return toJsonSafeValue(jsonValue, seen);
    } catch {
      seen.delete(value);
      return undefined;
    }
  }

  if (value instanceof String) {
    seen.delete(value);
    return String.prototype.valueOf.call(value);
  }
  if (value instanceof Number) {
    seen.delete(value);
    return Number.prototype.valueOf.call(value);
  }
  if (value instanceof Boolean) {
    seen.delete(value);
    return Boolean.prototype.valueOf.call(value);
  }

  if (Array.isArray(value)) {
    const safeArray = new Array<unknown>(value.length);
    for (let index = 0; index < value.length; index += 1) {
      const descriptor = Object.getOwnPropertyDescriptor(value, String(index));
      safeArray[index] = descriptor && 'value' in descriptor
        ? toJsonSafeValue(descriptor.value, seen)
        : undefined;
    }
    seen.delete(value);
    return safeArray;
  }

  const safeRecord: Record<string, unknown> = {};
  for (const key of Object.keys(value)) {
    const descriptor = Object.getOwnPropertyDescriptor(value, key);
    if (!descriptor || !('value' in descriptor)) continue;
    const safeValue = toJsonSafeValue(descriptor.value, seen);
    if (safeValue !== undefined) safeRecord[key] = safeValue;
  }
  seen.delete(value);
  return safeRecord;
}

function safeJsonStringify(value: object): string | null {
  try {
    const json = JSON.stringify(toJsonSafeValue(value, new WeakSet<object>()));
    return json ?? null;
  } catch {
    return null;
  }
}

export function extractNestedErrorMessage(error: unknown, depth = 0): string | null {
  if (depth > 3 || error == null) return null;
  if (typeof error === 'string') return error;
  if (error instanceof Error) {
    const message = findSafeDataProperty(error, 'message');
    if (typeof message === 'string' && message) return message;
    const nested = extractNestedErrorMessage(findSafeDataProperty(error, 'cause'), depth + 1);
    if (nested) return nested;
    const json = safeJsonStringify(error);
    if (json && json !== '{}') return json;
    return null;
  }
  if (isObjectRecord(error)) {
    const directFields = ['message', 'error', 'details', 'reason'] as const;
    for (const key of directFields) {
      const value = getOwnField(error, key);
      if (typeof value === 'string' && value.trim()) return value;
    }
    const cause = getOwnField(error, 'cause');
    if (cause !== undefined) {
      const nested = extractNestedErrorMessage(cause, depth + 1);
      if (nested) return nested;
    }
  }
  if (typeof error === 'object') {
    const json = safeJsonStringify(error);
    if (json && json !== '{}') return json;
  }
  return null;
}

export function toIpcErrorMessage(error: unknown): string {
  const nested = extractNestedErrorMessage(error);
  if (nested) return nested;
  if (error instanceof Error) return '[object Error]';
  return String(error);
}

/**
 * Returns true when the error string looks like a Rust/JNI/objc2 /
 * filesystem-path / mutex-poison internal leak rather than a
 * human-authored user-facing message.
 */
export function looksLikeBackendInternal(message: string): boolean {
  const lower = message.toLowerCase();
  const INTERNAL_MARKERS = [
    'poisonerror',
    'lock poisoned',
    'javavm',
    'jni thread',
    'rusqlite::',
    'objc2',
    'refcell',
    'mutex<',
    'borrow',
    'provider sdk',
    'codesign',
    'javam',
    'failed to locate current executable',
    'failed to parse filesystem bridge sync envelope',
    'failed to lock writer connection',
    'failed to attach jni',
    'failed to get javavm',
  ];
  if (INTERNAL_MARKERS.some((marker) => lower.includes(marker))) return true;
  if (/\s(\/Users\/|\/private\/|\/var\/folders\/|[A-Z]:\\\\)/.test(message)) return true;
  return false;
}

// typed `CommandError` envelope dispatch. When an IPC
// error string parses as a JSON envelope, the toast layer routes
// disk-full through its dedicated banner and falls through to
// `fallback` here. For typed envelopes whose human-facing message
// is the same sanitized string for every variant ('disk_full',
// 'internal', 'serialization'), prefer the caller's
// fallback over the generic Rust message. Validation / not_found /
// timeout / tauri carry intent-specific messages safe to surface.
function classifyTypedEnvelope(
  raw: string,
): { kind: string; message: string } | null {
  if (!raw.startsWith('{')) return null;
  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    return null;
  }
  if (typeof parsed !== 'object' || parsed === null || Array.isArray(parsed)) return null;
  const record = parsed as Record<string, unknown>;
  const kind = record.kind;
  const message = record.message;
  if (typeof kind !== 'string' || typeof message !== 'string') return null;
  return { kind, message };
}

const SANITIZED_ENVELOPE_KINDS = new Set([
  'disk_full',
  'internal',
  'serialization',
]);

export function toUserFacingErrorMessage(error: unknown, fallback: string): string {
  const raw = extractNestedErrorMessage(error);
  if (!raw) return fallback;
  const envelope = classifyTypedEnvelope(raw);
  if (envelope !== null) {
    if (SANITIZED_ENVELOPE_KINDS.has(envelope.kind)) return fallback;
    const message = envelope.message.trim();
    if (!message) return fallback;
    const MAX_TOAST_LEN = 200;
    return message.length > MAX_TOAST_LEN
      ? `${message.slice(0, MAX_TOAST_LEN)}\u2026`
      : message;
  }
  // Legacy / non-envelope path: third-party `String`-typed rejects
  // (plugin errors, unwrap chains) still flow through here.
  const firstLine = (raw.split(/\n\s+at\s/)[0] ?? '').trim();
  if (!firstLine) return fallback;
  if (looksLikeBackendInternal(firstLine)) return fallback;
  const MAX_TOAST_LEN = 200;
  if (firstLine.length > MAX_TOAST_LEN) {
    return `${firstLine.slice(0, MAX_TOAST_LEN)}\u2026`;
  }
  return firstLine;
}
