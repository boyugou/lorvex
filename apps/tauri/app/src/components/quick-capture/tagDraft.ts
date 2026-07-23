import { MAX_TAG_NAME_LENGTH } from '@lorvex/shared/validation';

/**
 * Truncate to MAX_TAG_NAME_LENGTH **code points**, not UTF-16 code
 * units. `String#slice` operates on code units, so a multi-code-unit
 * emoji at the boundary would be cut in half and produce a lone
 * surrogate. `Array.from(str)` iterates by code point and
 * preserves surrogate pairs intact.
 */
function normalizeQuickCaptureTagName(value: string): string {
  return Array.from(value.trim()).slice(0, MAX_TAG_NAME_LENGTH).join('');
}

function clampToCodePoints(value: string, max: number): string {
  // Cheap fast path — if the byte length suggests no surrogate pairs
  // are at the boundary, the spread is a no-op.
  if (value.length <= max) return value;
  return Array.from(value).slice(0, max).join('');
}

function appendUniqueTag(tokens: string[], tag: string): void {
  const normalized = normalizeQuickCaptureTagName(tag);
  if (!normalized) return;
  const key = normalized.toLowerCase();
  if (tokens.some((token) => token.toLowerCase() === key)) return;
  tokens.push(normalized);
}

export function parseQuickCaptureTagDraft(input: string): string[] {
  const tags: string[] = [];
  for (const segment of input.split(',')) {
    appendUniqueTag(tags, segment);
  }
  return tags;
}

function serializeQuickCaptureTagDraft(tags: readonly string[]): string {
  const normalized: string[] = [];
  for (const tag of tags) {
    appendUniqueTag(normalized, tag);
  }
  return normalized.length > 0 ? `${normalized.join(', ')}, ` : '';
}

export function serializeQuickCaptureSubmissionTags(input: string): string[] | null {
  const tags = parseQuickCaptureTagDraft(input);
  return tags.length > 0 ? tags : null;
}

export function appendQuickCaptureTagDraft(input: string, tag: string): string {
  return serializeQuickCaptureTagDraft([
    ...parseQuickCaptureTagDraft(input),
    tag,
  ]);
}

export function currentQuickCaptureTagToken(input: string): string {
  const lastComma = input.lastIndexOf(',');
  return (lastComma === -1 ? input : input.slice(lastComma + 1)).trimStart();
}

export function replaceCurrentQuickCaptureTagToken(input: string, selected: string): string {
  const lastComma = input.lastIndexOf(',');
  const prefix = lastComma === -1 ? '' : input.slice(0, lastComma);
  return serializeQuickCaptureTagDraft([
    ...parseQuickCaptureTagDraft(prefix),
    selected,
  ]);
}

export function clampQuickCaptureTagDraftInput(input: string): string {
  if (!input) return input;
  const segments = input.split(',');
  let mutated = false;
  const clamped = segments.map((segment) => {
    const leading = segment.match(/^\s*/)?.[0] ?? '';
    const trailing = segment.match(/\s*$/)?.[0] ?? '';
    const inner = segment.slice(leading.length, segment.length - trailing.length);
    // Count code points, not code units, so multi-code-unit emoji
    // don't get cut in half at the boundary.
    const innerCodePoints = Array.from(inner);
    if (innerCodePoints.length <= MAX_TAG_NAME_LENGTH) return segment;
    mutated = true;
    return `${leading}${clampToCodePoints(inner, MAX_TAG_NAME_LENGTH)}${trailing}`;
  });
  return mutated ? clamped.join(',') : input;
}
