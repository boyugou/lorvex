type JsonParseResult =
  | { ok: true; value: unknown }
  | { ok: false; error: unknown };

export function tryParseJson(raw: string): JsonParseResult {
  try {
    return { ok: true, value: JSON.parse(raw) };
  } catch (error) {
    return { ok: false, error };
  }
}

export function parseJsonValueOrNull(raw: string): unknown {
  const parsed = tryParseJson(raw);
  return parsed.ok ? parsed.value : null;
}

export function tryParseOptionalJson<T>(
  raw: string | null,
  validator?: (value: unknown) => value is T,
): { value: T | null; error: unknown | null } {
  if (!raw) {
    return { value: null, error: null };
  }
  const parsed = tryParseJson(raw);
  if (!parsed.ok) {
    return { value: null, error: parsed.error };
  }
  if (validator && !validator(parsed.value)) {
    return {
      value: null,
      error: new SyntaxError(
        `JSON payload did not match expected shape: ${raw.slice(0, 200)}`,
      ),
    };
  }
  return { value: parsed.value as T, error: null };
}
