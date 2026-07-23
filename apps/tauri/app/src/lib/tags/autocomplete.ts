// pure parsing helpers that power the `#`-prefixed tag
// autocomplete surfaced in quick-capture and the task-detail title
// editor. Kept React-free so `scripts/tests/runtime/*.test.ts` can
// exercise the grammar without pulling in the DOM.
//
// The grammar we recognise is intentionally narrow:
//
//   * A hashtag fragment is the run of tag-name characters that
//     follows a `#` which is either at the start of the string or
//     preceded by whitespace. That disambiguates from `C#` style
//     tokens inside a title like "C# roadmap".
//   * A tag-name character is [A-Za-z0-9_-] plus any non-ASCII
//     codepoint (so CJK, emoji, accented letters all work). We stop
//     at whitespace, punctuation, and `#` itself.
//   * The cursor must be INSIDE the fragment for autocomplete to
//     fire — trailing fragments after the caret are left alone.
//
// The test at `scripts/tests/runtime/hashtag_autocomplete.test.ts`
// pins every branch of the grammar so a refactor can't silently
// widen or narrow it.

/**
 * A detected hashtag fragment within a title string.
 *
 * `hashStart` is the index of the `#` itself. `fragmentEnd` is the
 * exclusive end of the matched fragment — i.e. the cursor position
 * when the user is still typing. `query` excludes the leading `#`.
 */
export interface HashtagFragment {
  hashStart: number;
  fragmentEnd: number;
  query: string;
}

/**
 * True iff `ch` may appear inside a tag name. Accepts ASCII alnum,
 * `_`, `-`, and any codepoint >= 0x80 (non-ASCII letters / CJK /
 * emoji). Rejects whitespace, ASCII punctuation, and `#` itself so
 * two hashtags back-to-back are parsed independently.
 */
function isTagNameChar(ch: string): boolean {
  if (ch.length === 0) return false;
  const code = ch.charCodeAt(0);
  // ASCII alnum
  if (code >= 0x30 && code <= 0x39) return true; // 0-9
  if (code >= 0x41 && code <= 0x5a) return true; // A-Z
  if (code >= 0x61 && code <= 0x7a) return true; // a-z
  if (code === 0x5f || code === 0x2d) return true; // _ or -
  // Any non-ASCII codepoint — lets CJK / emoji / accented chars
  // flow through without us having to ship a Unicode category table.
  if (code >= 0x80) return true;
  return false;
}

/**
 * True iff the character at `input[pos - 1]` is a valid "hashtag
 * boundary" — i.e. either the string start or ASCII whitespace.
 * Anything else (letters, punctuation, `.`) means the `#` at `pos`
 * is embedded inside another token (e.g. "C#") and must NOT trigger
 * autocomplete.
 */
function isHashBoundary(input: string, pos: number): boolean {
  if (pos === 0) return true;
  const prev = input.charAt(pos - 1);
  return prev === ' ' || prev === '\t' || prev === '\n' || prev === '\r';
}

/**
 * Find the active hashtag fragment given a title string and a caret
 * position. Returns `null` when the caret is not inside a hashtag.
 *
 * "Active" means: there is a `#` at the start of the current word
 * before the caret, AND every character between that `#` and the
 * caret is a valid tag-name character (or none — a bare `#` with
 * caret right after it is a valid empty query that opens the
 * dropdown).
 */
export function findActiveHashtagFragment(
  input: string,
  caret: number,
): HashtagFragment | null {
  if (caret < 0 || caret > input.length) return null;

  // Walk backwards from the caret looking for a `#` on a word
  // boundary. Bail out as soon as we hit a non-tag-name char that
  // isn't `#` — that means the caret isn't inside a hashtag.
  let i = caret;
  while (i > 0) {
    const ch = input.charAt(i - 1);
    if (ch === '#') {
      if (!isHashBoundary(input, i - 1)) return null;
      return {
        hashStart: i - 1,
        fragmentEnd: caret,
        query: input.slice(i, caret),
      };
    }
    if (!isTagNameChar(ch)) return null;
    i -= 1;
  }
  return null;
}

export function stripHashtagFragment(
  input: string,
  fragment: HashtagFragment,
): { text: string; caret: number } {
  const before = input.slice(0, fragment.hashStart);
  const after = input.slice(fragment.fragmentEnd);

  // Audit: if we have "foo #bar baz" and strip "#bar", we want
  // "foo baz" not "foo  baz". Drop exactly one space from whichever
  // side is adjacent to the removed fragment.
  let left = before;
  let right = after;
  if (left.endsWith(' ') && right.startsWith(' ')) {
    right = right.slice(1);
  } else if (left.endsWith(' ') && right.length === 0) {
    left = left.replace(/\s+$/, '');
  } else if (left.length === 0 && right.startsWith(' ')) {
    // Leading fragment — "#todo wire up sync" → "wire up sync",
    // not " wire up sync".
    right = right.slice(1);
  }

  return { text: left + right, caret: left.length };
}

/**
 * Case-insensitive prefix + substring ranked filter over a tag
 * list. Prefix matches come first, then substring matches, then
 * alphabetical. Already-selected tags are filtered out.
 *
 * `limit` caps the number of returned suggestions — the default of
 * 8 mirrors the comma-separated tag picker elsewhere in the UI.
 */
export function filterTagCandidates<T extends { display_name: string }>(
  candidates: readonly T[],
  query: string,
  alreadySelected: readonly string[],
  limit = 8,
): T[] {
  const q = query.trim().toLowerCase();
  const taken = new Set(alreadySelected.map((s) => s.toLowerCase()));
  const scored: Array<{ tag: T; score: number; name: string }> = [];
  for (const tag of candidates) {
    const name = tag.display_name.toLowerCase();
    if (taken.has(name)) continue;
    if (!q) {
      scored.push({ tag, score: 2, name });
      continue;
    }
    if (name.startsWith(q)) {
      scored.push({ tag, score: 0, name });
    } else if (name.includes(q)) {
      scored.push({ tag, score: 1, name });
    }
  }
  scored.sort((a, b) => {
    if (a.score !== b.score) return a.score - b.score;
    return a.name.localeCompare(b.name);
  });
  return scored.slice(0, limit).map((s) => s.tag);
}
