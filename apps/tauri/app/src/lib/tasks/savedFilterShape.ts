/**
 * shared serialize / deserialize for the filter shape
 * that every list-shaped view (AllTasks, Someday, Upcoming, Kanban,
 * Eisenhower) exposes today: a list id, a single priority, a set of
 * tags, and a search string.
 *
 * Current scope: only the subset of pills that already exist. The issue
 * calls for true combinators (OR across lists, OR/AND across tags,
 * date-range windows) — those require explicit schema additions once
 * the underlying filter UI grows the corresponding inputs.
 *
 * Each view lifts only the fields it supports out of the decoded
 * payload. Missing fields fall back to "no filter"; unknown fields
 * make the payload invalid instead of silently applying a partial
 * shape from a different contract.
 */

import { tryParseJson } from '../security/jsonParse';
import { hasOnlyKeys, isPlainRecord } from '../objectGuards';
import { isPriority, type PriorityFilterValue } from './priorityFilter';

interface SerializedViewFilters {
  /** Optional to keep the on-disk payload small when unused. */
  search?: string;
  listId?: string | null;
  priority?: PriorityFilterValue;
  tags?: string[];
  showCompleted?: boolean;
  showCancelled?: boolean;
  groupBy?: string;
  sortKey?: string;
  sortDirection?: 'asc' | 'desc';
  horizonDays?: number | null;
}

interface ViewFilterSnapshot {
  search: string;
  filterListId: string | null;
  filterPriority: PriorityFilterValue;
  selectedTags: Set<string>;
  showCompleted?: boolean;
  showCancelled?: boolean;
  groupBy?: string;
  sortKey?: string;
  sortDirection?: 'asc' | 'desc';
  horizonDays?: number | null;
}

const SAVED_FILTER_KEYS = new Set([
  'groupBy',
  'horizonDays',
  'listId',
  'priority',
  'search',
  'showCancelled',
  'showCompleted',
  'sortDirection',
  'sortKey',
  'tags',
]);

function hasOnlySavedFilterKeys(value: Record<string, unknown>): boolean {
  return hasOnlyKeys(value, SAVED_FILTER_KEYS);
}

function readOptionalString(value: unknown): string | undefined {
  return typeof value === 'string' ? value : undefined;
}

function readOptionalNullableString(value: unknown): string | null | undefined {
  if (value === null) return null;
  return typeof value === 'string' ? value : undefined;
}

function readOptionalBoolean(value: unknown): boolean | undefined {
  return typeof value === 'boolean' ? value : undefined;
}

function readOptionalPriority(value: unknown): PriorityFilterValue | undefined {
  if (value === null) return null;
  return isPriority(value) ? value : undefined;
}

function readOptionalNonNegativeInteger(value: unknown): number | null | undefined {
  if (value === null) return null;
  if (typeof value !== 'number' || !Number.isInteger(value)) return undefined;
  return value >= 0 ? value : undefined;
}

function readOptionalStringArray(value: unknown): string[] | undefined {
  if (!Array.isArray(value)) return undefined;
  const next: string[] = [];
  const seen = new Set<string>();
  for (const entry of value) {
    if (typeof entry !== 'string' || seen.has(entry)) continue;
    seen.add(entry);
    next.push(entry);
  }
  return next;
}

export function readSavedFilterEnum<const T extends string>(
  value: unknown,
  allowed: readonly T[],
): T | undefined {
  if (typeof value !== 'string') return undefined;
  return allowed.includes(value as T) ? (value as T) : undefined;
}

export function readSavedFilterNumberEnum<const T extends number | null>(
  value: unknown,
  allowed: readonly T[],
): T | undefined {
  for (const candidate of allowed) {
    if (candidate === value) return candidate;
  }
  return undefined;
}

export function serializeViewFilters(snap: ViewFilterSnapshot): string {
  // Only emit fields that carry signal so the blob stays small and a
  // textual `filter_json` diff across saves is easy to read.
  const payload: SerializedViewFilters = {};
  if (snap.search.trim()) payload.search = snap.search;
  if (snap.filterListId) payload.listId = snap.filterListId;
  if (snap.filterPriority !== null && snap.filterPriority !== undefined)
    payload.priority = snap.filterPriority;
  if (snap.selectedTags.size > 0) payload.tags = [...snap.selectedTags].sort();
  if (snap.showCompleted !== undefined) payload.showCompleted = snap.showCompleted;
  if (snap.showCancelled !== undefined) payload.showCancelled = snap.showCancelled;
  if (snap.groupBy) payload.groupBy = snap.groupBy;
  if (snap.sortKey) payload.sortKey = snap.sortKey;
  if (snap.sortDirection) payload.sortDirection = snap.sortDirection;
  if (snap.horizonDays !== undefined) payload.horizonDays = snap.horizonDays;
  return JSON.stringify(payload);
}

/**
 * Decode a stored payload back into plain fields the view controller
 * can feed into its setters.
 */
export function deserializeViewFilters(filterJson: string): SerializedViewFilters {
  const parseResult = tryParseJson(filterJson);
  if (!parseResult.ok) return {};
  const parsed = parseResult.value;
  if (!isPlainRecord(parsed)) return {};
  if (!hasOnlySavedFilterKeys(parsed)) return {};
  const decoded: SerializedViewFilters = {};
  const search = readOptionalString(parsed.search);
  if (search !== undefined) decoded.search = search;
  const listId = readOptionalNullableString(parsed.listId);
  if (listId !== undefined) decoded.listId = listId;
  const priority = readOptionalPriority(parsed.priority);
  if (priority !== undefined) decoded.priority = priority;
  const tags = readOptionalStringArray(parsed.tags);
  if (tags !== undefined) decoded.tags = tags;
  const showCompleted = readOptionalBoolean(parsed.showCompleted);
  if (showCompleted !== undefined) decoded.showCompleted = showCompleted;
  const showCancelled = readOptionalBoolean(parsed.showCancelled);
  if (showCancelled !== undefined) decoded.showCancelled = showCancelled;
  const groupBy = readOptionalString(parsed.groupBy);
  if (groupBy !== undefined) decoded.groupBy = groupBy;
  const sortKey = readOptionalString(parsed.sortKey);
  if (sortKey !== undefined) decoded.sortKey = sortKey;
  const sortDirection = readSavedFilterEnum(parsed.sortDirection, ['asc', 'desc']);
  if (sortDirection !== undefined) decoded.sortDirection = sortDirection;
  const horizonDays = readOptionalNonNegativeInteger(parsed.horizonDays);
  if (horizonDays !== undefined) decoded.horizonDays = horizonDays;
  return decoded;
}
