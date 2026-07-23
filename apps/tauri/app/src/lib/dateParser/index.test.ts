import { describe, expect, it } from 'vitest';

import { parseDateFromText } from './index';

// Pin a deterministic reference so chrono's "tomorrow" / "next week" math is
// stable across machines and clock drift. 2026-04-15 (Wed) sits comfortably
// mid-week, mid-month, mid-year — easy to reason about for forward-date tests.
const REF = new Date('2026-04-15T12:00:00Z');

describe('parseDateFromText — empty / no-op input', () => {
  it('returns null for empty / whitespace-only text', () => {
    expect(parseDateFromText('', 'en', REF)).toBeNull();
    expect(parseDateFromText('   ', 'en', REF)).toBeNull();
  });

  it('returns null when the text contains no date phrase', () => {
    expect(parseDateFromText('finish the proposal', 'en', REF)).toBeNull();
  });

  it('returns null when removing the date would leave an empty title', () => {
    // Bare "tomorrow" with no surrounding task content means there is nothing
    // left to capture — the parser must refuse rather than return a blank
    // cleanTitle that downstream code would try to submit.
    expect(parseDateFromText('tomorrow', 'en', REF)).toBeNull();
  });
});

describe('parseDateFromText — English', () => {
  it('extracts ISO dates and trims them from the title', () => {
    const result = parseDateFromText('finish paper 2026-05-01', 'en', REF);
    expect(result).not.toBeNull();
    expect(result?.cleanTitle).toBe('finish paper');
    expect(result?.matchedText).toBe('2026-05-01');
    expect(result?.date.getFullYear()).toBe(2026);
    expect(result?.date.getMonth()).toBe(4); // May
  });

  it('extracts the leading "by" affix together with the date', () => {
    const result = parseDateFromText('finish paper by friday', 'en', REF);
    expect(result).not.toBeNull();
    expect(result?.cleanTitle).toBe('finish paper');
    expect(result?.matchedText.toLowerCase()).toContain('friday');
    expect(result?.matchedText.toLowerCase()).toContain('by');
  });

  it('extracts the leading "due" affix', () => {
    const result = parseDateFromText('report due tomorrow', 'en', REF);
    expect(result).not.toBeNull();
    expect(result?.cleanTitle).toBe('report');
  });

  it('normalizes punctuation spacing in the cleaned title', () => {
    // The trailing period must stay glued to "report" after the date phrase
    // is removed — without normalizeCleanTitle this would emit "report  ."
    const result = parseDateFromText('finish report on 2026-05-01.', 'en', REF);
    expect(result?.cleanTitle).toBe('finish report.');
  });

  it('falls back to forward-date semantics for relative dates', () => {
    const result = parseDateFromText('ship feature next monday', 'en', REF);
    expect(result).not.toBeNull();
    // chrono is configured forwardDate: true — the parsed date must be in the
    // future relative to REF.
    expect(result!.date.getTime()).toBeGreaterThan(REF.getTime());
  });
});

describe('parseDateFromText — locale fallbacks', () => {
  it('falls back from unknown locales to the English casual parser', () => {
    const result = parseDateFromText('milestone on 2026-06-01', 'xx-YY', REF);
    expect(result).not.toBeNull();
    expect(result?.cleanTitle).toBe('milestone');
  });

  it('uses the language prefix when the exact locale tag is unknown', () => {
    // "en-NZ" is not in the chrono table, but "en" is — this hits the
    // langPrefix branch in getChronoInstance + resolveHeuristicLocale.
    const result = parseDateFromText('finish paper by friday', 'en-NZ', REF);
    expect(result).not.toBeNull();
    expect(result?.cleanTitle).toBe('finish paper');
  });
});

describe('parseDateFromText — CJK collision avoidance', () => {
  it('drops weekday-only matches that look like a title continuation', () => {
    // chrono can latch onto "mon" inside "monitoring"; the
    // looksLikeTitleContinuation guard must reject that match. See the
    // weekdayContinuationCollision branch.
    const result = parseDateFromText('monitoring dashboard', 'en', REF);
    expect(result).toBeNull();
  });
});

describe('parseDateFromText — return shape', () => {
  it('always returns a Date instance for `date`', () => {
    const result = parseDateFromText('finish paper 2026-05-01', 'en', REF);
    expect(result?.date).toBeInstanceOf(Date);
  });

  it('matchedText slices from the original input verbatim', () => {
    const text = 'finish paper by 2026-05-01 and rest';
    const result = parseDateFromText(text, 'en', REF);
    expect(result).not.toBeNull();
    // The matched fragment must appear exactly in the source text.
    expect(text.includes(result!.matchedText)).toBe(true);
  });
});
