const PREFIX_SCORE = 1000;
const WORD_START_SCORE = 500;
const SUBSTRING_SCORE = 100;
const FUZZY_SCORE = 10;

export function scoreMatch(query: string, text: string): number | null {
  const q = query.trim().toLowerCase();
  const t = text.toLowerCase();
  if (q.length === 0) return 0;

  if (t.startsWith(q)) {
    // Shorter matches rank higher within a tier so "Work" beats
    // "Workshop" for query "work".
    return PREFIX_SCORE - Math.max(t.length - q.length, 0);
  }

  // Word-start: query begins a word inside the text. Treat non-letter
  // runs as word boundaries so "groc" matches "Grocery list" via the
  // space, "#budget" via the `#`, etc.
  for (let i = 1; i < t.length; i++) {
    if (isWordBoundary(t, i) && t.startsWith(q, i)) {
      return WORD_START_SCORE - i;
    }
  }

  const substringIdx = t.indexOf(q);
  if (substringIdx !== -1) {
    return SUBSTRING_SCORE - substringIdx;
  }

  // Fuzzy subsequence: does every char of q appear in order inside t?
  // This is deliberately loose — we only use it as the lowest tier so a
  // prefix or substring match always wins, and the palette already caps
  // the result list at a reasonable count so fuzzy noise doesn't flood
  // the visible area.
  if (isFuzzySubsequence(q, t)) return FUZZY_SCORE;

  return null;
}

function isWordBoundary(text: string, index: number): boolean {
  const prev = text[index - 1];
  if (prev === undefined) return false;
  // Letters / digits are word chars; anything else (space, punct, CJK
  // punctuation, emoji separators) starts a new word.
  return !/[\p{L}\p{N}]/u.test(prev);
}

function isFuzzySubsequence(query: string, text: string): boolean {
  let cursor = 0;
  for (const ch of text) {
    if (cursor >= query.length) return true;
    if (ch === query[cursor]) cursor++;
  }
  return cursor >= query.length;
}
