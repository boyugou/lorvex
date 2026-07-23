import assert from 'node:assert/strict';

export interface ToolResultPayload {
  content?: Array<{ type?: string; text?: string }>;
  isError?: boolean;
}

export function getFirstTextContent(result: unknown): string {
  const payload = result as ToolResultPayload;
  const firstText = payload.content?.find((part) => part.type === 'text' && typeof part.text === 'string');
  assert.ok(firstText, 'Expected MCP tool result to include a text content block');
  return firstText.text!;
}

export function parseJsonContent<T>(result: unknown): T {
  const parsed = JSON.parse(getFirstTextContent(result));
  if (
    parsed &&
    typeof parsed === 'object' &&
    !Array.isArray(parsed) &&
    'code' in parsed &&
    !('kind' in parsed)
  ) {
    return { ...parsed, kind: (parsed as { code: unknown }).code } as T;
  }
  return parsed as T;
}

export function asToolResultPayload(result: unknown): ToolResultPayload {
  return result as ToolResultPayload;
}

export function requireValue<T>(value: T | null | undefined, label: string): T {
  if (value === null || value === undefined) {
    assert.fail(label);
  }
  return value;
}

export function requireArrayItem<T>(items: readonly T[], index: number, label: string): T {
  return requireValue(items[index], label);
}

export function requireRecordValue<T>(record: Record<string, T>, key: string, label: string): T {
  return requireValue(record[key], label);
}

/**
 * MCP task-mutation tools wrap the task body in an envelope per commit
 * db666b64. Shapes:
 *   create_task   → { task, next_occurrence, newly_unblocked, advice }
 *   complete_task → { completed, next_occurrence, newly_unblocked }
 *   cancel_task   → { cancelled, next_occurrence, dependency_updates }
 * `update_task`, `reopen_task`, `defer_task`, reminder tools, and checklist
 * tools still return the flat task object.
 *
 * Callers pass the envelope key explicitly (defaults to `'task'`) so one
 * helper covers all three mutation shapes.
 */
export function parseTaskEnvelope<T extends Record<string, unknown>>(
  result: unknown,
  key: 'task' | 'completed' | 'cancelled' = 'task',
): T {
  const raw = parseJsonContent<Record<string, unknown>>(result);
  if (raw && typeof raw === 'object' && key in raw && raw[key]) {
    return raw[key] as T;
  }
  // Backwards-compat: return the raw body as-is if the envelope key is
  // absent (e.g., tools that weren't migrated to the wrapped shape).
  return raw as unknown as T;
}
