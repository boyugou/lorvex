import assert from 'node:assert/strict';
import test from 'node:test';

import {
  filterTagCandidates,
  findActiveHashtagFragment,
  stripHashtagFragment,
} from '../../../app/src/lib/tags/autocomplete.ts';

// Issue #2517 — pin the `#`-prefixed tag autocomplete grammar and
// ranking so a refactor can't silently change which `#` triggers
// the dropdown, which characters terminate a tag fragment, or how
// the candidate list gets ordered.

test('findActiveHashtagFragment: `#` at string start with empty query', () => {
  const frag = findActiveHashtagFragment('#', 1);
  assert.deepEqual(frag, { hashStart: 0, fragmentEnd: 1, query: '' });
});

test('findActiveHashtagFragment: `#urg` mid-title with caret at end of fragment', () => {
  const input = 'fix bug #urg';
  const frag = findActiveHashtagFragment(input, input.length);
  assert.deepEqual(frag, { hashStart: 8, fragmentEnd: 12, query: 'urg' });
});

test('findActiveHashtagFragment: caret inside the fragment returns a shorter query', () => {
  const input = 'fix bug #urgent';
  // caret after `#ur`
  const frag = findActiveHashtagFragment(input, 11);
  assert.deepEqual(frag, { hashStart: 8, fragmentEnd: 11, query: 'ur' });
});

test('findActiveHashtagFragment: no match when `#` is embedded in a token (e.g. "C#")', () => {
  // "C#" has no space before `#`, so it is NOT a hashtag start.
  assert.equal(findActiveHashtagFragment('C#', 2), null);
  assert.equal(findActiveHashtagFragment('learn C#roadmap', 15), null);
});

test('findActiveHashtagFragment: returns null when caret sits past the fragment end', () => {
  const input = 'fix #urg now';
  // caret after "now" — the char immediately before is a letter,
  // and walking back we hit a space (non-tag char, non-`#`) before
  // finding a `#`, so the lookup bails.
  assert.equal(findActiveHashtagFragment(input, input.length), null);
});

test('findActiveHashtagFragment: accepts CJK inside the fragment', () => {
  const input = 'buy 牛奶 #工作';
  const frag = findActiveHashtagFragment(input, input.length);
  assert.ok(frag);
  assert.equal(frag?.query, '工作');
});

test('stripHashtagFragment: collapses the flanking whitespace', () => {
  const input = 'fix bug #urgent today';
  const frag = findActiveHashtagFragment(input, 15);
  assert.ok(frag);
  const out = stripHashtagFragment(input, frag!);
  assert.equal(out.text, 'fix bug today');
  // The helper returns caret = left.length after the adjacent
  // space is dropped. "fix bug" (7) + no trimming leaves 8, but
  // with space-collapsing it lands at 8 ("fix bug ").
  assert.equal(out.caret, 'fix bug '.length);
});

test('stripHashtagFragment: trailing fragment trims the trailing space', () => {
  const input = 'fix bug #urg';
  const frag = findActiveHashtagFragment(input, input.length);
  assert.ok(frag);
  const out = stripHashtagFragment(input, frag!);
  assert.equal(out.text, 'fix bug');
  assert.equal(out.caret, 7);
});

test('stripHashtagFragment: leading fragment keeps the following content', () => {
  const input = '#todo wire up sync';
  const frag = findActiveHashtagFragment(input, 5);
  assert.ok(frag);
  const out = stripHashtagFragment(input, frag!);
  assert.equal(out.text, 'wire up sync');
  assert.equal(out.caret, 0);
});

test('filterTagCandidates: prefix match ranks above substring match', () => {
  const tags = [
    { display_name: 'urgent', color: null },
    { display_name: 'research-urgent', color: null },
    { display_name: 'misc', color: null },
  ];
  const out = filterTagCandidates(tags, 'urg', []);
  assert.deepEqual(out.map((t) => t.display_name), ['urgent', 'research-urgent']);
});

test('filterTagCandidates: hides already-selected tags (case-insensitive)', () => {
  const tags = [
    { display_name: 'urgent', color: null },
    { display_name: 'Urgent-tomorrow', color: null },
  ];
  const out = filterTagCandidates(tags, 'urg', ['URGENT']);
  assert.deepEqual(out.map((t) => t.display_name), ['Urgent-tomorrow']);
});

test('filterTagCandidates: empty query returns all unselected alphabetically', () => {
  const tags = [
    { display_name: 'zeta', color: null },
    { display_name: 'alpha', color: null },
    { display_name: 'beta', color: null },
  ];
  const out = filterTagCandidates(tags, '', []);
  assert.deepEqual(out.map((t) => t.display_name), ['alpha', 'beta', 'zeta']);
});

test('filterTagCandidates: honours the limit argument', () => {
  const tags = Array.from({ length: 20 }, (_, i) => ({
    display_name: `tag-${String(i).padStart(2, '0')}`,
    color: null,
  }));
  const out = filterTagCandidates(tags, '', [], 5);
  assert.equal(out.length, 5);
  assert.equal(out[0]?.display_name, 'tag-00');
  assert.equal(out[4]?.display_name, 'tag-04');
});

test('issue #2517 acceptance: "type `#urg`, assert dropdown filters"', () => {
  // Simulate typing `fix bug #urg` and asking the grammar+filter
  // pipeline what the dropdown should show.
  const title = 'fix bug #urg';
  const caret = title.length;
  const allTags = [
    { display_name: 'urgent', color: '#ff0000' },
    { display_name: 'urgent-fix', color: null },
    { display_name: 'research-urgent', color: null },
    { display_name: 'admin', color: null },
    { display_name: 'bug', color: null },
  ];
  const frag = findActiveHashtagFragment(title, caret);
  assert.ok(frag, 'expected the hashtag grammar to fire at end of "#urg"');
  const suggestions = filterTagCandidates(allTags, frag!.query, []);
  assert.deepEqual(
    suggestions.map((t) => t.display_name),
    ['urgent', 'urgent-fix', 'research-urgent'],
    'prefix matches rank above substring, and alphabetical within a rank',
  );
});
