/**
 * IPC payload builder.
 *
 * Reduces repetitive `if (value !== undefined) payload.key = value` boilerplate
 * across IPC wrapper modules.
 */

/**
 * Build a payload object from one or more records, omitting keys whose values are
 * `undefined`. Later records override earlier records.
 *
 * Values that are explicitly `null` are preserved (they signal "clear this field"
 * to the backend's nullable protocol).
 */
export function buildPayload(...sources: readonly Record<string, unknown>[]): Record<string, unknown> {
  const payload: Record<string, unknown> = {};
  for (const fields of sources) {
    for (const [key, descriptor] of Object.entries(Object.getOwnPropertyDescriptors(fields))) {
      if (!descriptor.enumerable || !('value' in descriptor)) {
        continue;
      }
      const { value } = descriptor;
      if (value !== undefined) {
        payload[key] = value;
      }
    }
  }
  return payload;
}

