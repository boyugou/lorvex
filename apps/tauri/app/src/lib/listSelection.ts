import { tryParseJson } from './security/jsonParse';
import { hasOnlyKeys, isPlainRecord as isRecord } from './objectGuards';

const NO_LIST_SELECTION_KIND = 'none';
const LIST_SELECTION_KIND = 'list';
const NO_LIST_SELECTION_KEYS = new Set(['kind']);
const LIST_SELECTION_KEYS = new Set(['kind', 'id']);

export function encodeListSelectionValue(listId: string | null | undefined): string {
  if (listId == null) {
    return JSON.stringify({ kind: NO_LIST_SELECTION_KIND });
  }

  return JSON.stringify({ kind: LIST_SELECTION_KIND, id: listId });
}

export function decodeListSelectionValue(value: string): string | null {
  const parseResult = tryParseJson(value);
  if (!parseResult.ok) return null;

  const parsed = parseResult.value;
  if (!isRecord(parsed)) return null;

  if (parsed.kind === NO_LIST_SELECTION_KIND && hasOnlyKeys(parsed, NO_LIST_SELECTION_KEYS)) {
    return null;
  }
  if (
    parsed.kind === LIST_SELECTION_KIND
    && typeof parsed.id === 'string'
    && hasOnlyKeys(parsed, LIST_SELECTION_KEYS)
  ) {
    return parsed.id;
  }

  return null;
}
