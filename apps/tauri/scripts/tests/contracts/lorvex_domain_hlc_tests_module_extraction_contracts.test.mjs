import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

// hlc.rs has been split into hlc/{mod,surface,parse_error,core,order,compare,serde_impls}.rs.
// The "production code only" contract now applies to hlc/mod.rs — that's the
// file that re-exports the surface and that owns the `#[cfg(test)] mod tests;`
// declaration that hooks the extracted tests/ subtree.
const hlcSource = path.join(repoRoot, 'lorvex-domain/src/hlc/mod.rs');
const hlcStateSource = path.join(repoRoot, 'lorvex-domain/src/hlc_state.rs');

const hlcFacade = path.join(repoRoot, 'lorvex-domain/src/hlc/tests.rs');
const hlcTestsDir = path.join(repoRoot, 'lorvex-domain/src/hlc/tests');

const hlcStateFacade = path.join(repoRoot, 'lorvex-domain/src/hlc_state/tests.rs');
const hlcStateTestsDir = path.join(repoRoot, 'lorvex-domain/src/hlc_state/tests');

function read(filePath) {
  return fs.readFileSync(filePath, 'utf8');
}

function testNames(source) {
  // Allow auxiliary attributes (e.g. #[should_panic(...)]) between
  // #[test] and the fn declaration so a #[test] + #[should_panic]
  // panic-safety case still registers as an owned test.
  return [
    ...source.matchAll(
      /\n\s*#\[test\]\s*\n(?:\s*#\[[^\]]*\]\s*\n)*\s*fn\s+([a-zA-Z0-9_]+)\s*\(/g,
    ),
  ].map((match) => match[1]);
}

/// Inline tests must not survive on the production source file:
/// any `#[cfg(test)] mod tests { … }` block in `hlc.rs` /
/// `hlc_state.rs` would silently re-collapse the split layout
/// because cargo would happily compile both the inline block AND
/// the sibling extracted module side by side, defeating the
/// audit-pass goal of keeping each production file focused on
/// one responsibility (#3273).
function assertProductionFileHasNoInlineTests(source, label) {
  // The post-split shape is `#[cfg(test)] mod tests;` — a bare
  // declaration, not a block. Anything followed by `{` reintroduces
  // inline tests inside the production file.
  assert.doesNotMatch(
    source,
    /#\[cfg\(test\)\]\s*\nmod\s+\w+\s*\{/,
    `${label} must not keep inline #[cfg(test)] mod blocks`,
  );
  // Forbid every shape of inline test/proptest at the top level so a
  // future refactor can't drop a sibling `#[cfg(test)] mod foo { ... }`
  // back into the production file.
  assert.doesNotMatch(
    source,
    /\n#\[test\]/,
    `${label} must not keep #[test] functions inline`,
  );
  assert.doesNotMatch(
    source,
    /\nproptest!\s*\{/,
    `${label} must not keep proptest! macros inline`,
  );
}

function assertOwnsTests(source, expectedNames, label) {
  const names = testNames(source);
  assert.deepEqual(
    names.filter((name) => expectedNames.includes(name)).sort(),
    expectedNames.toSorted(),
    `${label} should own its expected test functions`,
  );
  assert.equal(new Set(names).size, names.length, `${label} test names should stay unique`);
}

function assertFacadeShape(facadePath, expectedSubmodules, label) {
  const source = read(facadePath);
  for (const moduleName of expectedSubmodules) {
    assert.match(
      source,
      new RegExp(`^mod ${moduleName};$`, 'm'),
      `${label} should register ${moduleName}`,
    );
  }
  const lineCount = source.trimEnd().split('\n').length;
  assert.ok(
    lineCount <= expectedSubmodules.length + 4,
    `${label} should stay a thin facade, got ${lineCount} lines`,
  );
  assert.doesNotMatch(
    source,
    /\n#\[test\]|\nfn\s+\w+|\nconst\s+\w+|\nstruct\s+\w+|\nimpl\s+|\nproptest!/,
    `${label} should not keep tests, fixtures, or proptest blocks inline`,
  );
}

test('lorvex-domain hlc.rs keeps production code only', () => {
  const source = read(hlcSource);
  assertProductionFileHasNoInlineTests(source, 'hlc.rs');
  assert.match(
    source,
    /\n#\[cfg\(test\)\]\s*\nmod tests;\s*$/,
    'hlc.rs should declare the extracted tests submodule at the bottom',
  );
});

test('lorvex-domain hlc_state.rs keeps production code only', () => {
  const source = read(hlcStateSource);
  assertProductionFileHasNoInlineTests(source, 'hlc_state.rs');
  assert.match(
    source,
    /\n#\[cfg\(test\)\]\s*\nmod tests;\s*$/,
    'hlc_state.rs should declare the extracted tests submodule at the bottom',
  );
});

test('lorvex-domain hlc tests stay split by responsibility', () => {
  assert.ok(
    fs.existsSync(hlcTestsDir),
    'lorvex-domain/src/hlc/tests/ should contain the extracted hlc test modules',
  );

  const moduleFiles = fs
    .readdirSync(hlcTestsDir)
    .filter((fileName) => fileName.endsWith('.rs'))
    .sort();
  assert.deepEqual(moduleFiles, [
    'device_suffix.rs',
    'display.rs',
    'ordering.rs',
    'parse.rs',
    'physical_ms_ceiling.rs',
    'proptests.rs',
    'serde.rs',
    'surface.rs',
    'test_version.rs',
  ]);

  assertFacadeShape(
    hlcFacade,
    [
      'device_suffix',
      'display',
      'ordering',
      'parse',
      'physical_ms_ceiling',
      'proptests',
      'serde',
      'surface',
      'test_version',
    ],
    'hlc/tests.rs',
  );

  assertOwnsTests(
    read(path.join(hlcTestsDir, 'display.rs')),
    [
      'display_at_max_renders_exactly_thirteen_digit_physical_ms',
      'display_format',
      'display_zero_pads_counter',
      'display_zero_pads_physical_ms',
    ],
    'hlc/tests/display.rs',
  );

  assertOwnsTests(
    read(path.join(hlcTestsDir, 'parse.rs')),
    [
      'parse_empty_device_suffix',
      'parse_invalid_counter',
      'parse_invalid_format_no_underscores',
      'parse_invalid_format_one_underscore',
      'parse_invalid_physical_ms',
      'parse_normalizes_uppercase_device_suffix_to_lowercase',
      'parse_roundtrip',
      'parse_zero_padded_roundtrip',
    ],
    'hlc/tests/parse.rs',
  );

  assertOwnsTests(
    read(path.join(hlcTestsDir, 'device_suffix.rs')),
    [
      'device_suffix_with_underscores_is_rejected',
      'new_normalizes_device_suffix_to_lowercase',
      'new_rejects_non_hex_device_suffix',
      'new_rejects_short_device_suffix',
      'parse_rejects_non_hex_device_suffix',
      'parse_rejects_overlong_device_suffix',
    ],
    'hlc/tests/device_suffix.rs',
  );

  assertOwnsTests(
    read(path.join(hlcTestsDir, 'physical_ms_ceiling.rs')),
    [
      'new_accepts_physical_ms_at_max',
      'new_rejects_physical_ms_one_past_max',
      'new_rejects_physical_ms_past_ceiling',
      'parse_accepts_physical_ms_at_max',
      'parse_rejects_physical_ms_one_past_max',
      'parse_rejects_physical_ms_past_ceiling',
    ],
    'hlc/tests/physical_ms_ceiling.rs',
  );

  assertOwnsTests(
    read(path.join(hlcTestsDir, 'ordering.rs')),
    [
      'comparison_equal',
      'lexicographic_ordering_matches_component_ordering',
      'ordering_by_counter_when_physical_ms_equal',
      'ordering_by_device_suffix_when_physical_ms_and_counter_equal',
    ],
    'hlc/tests/ordering.rs',
  );

  assertOwnsTests(
    read(path.join(hlcTestsDir, 'serde.rs')),
    ['serde_deserialize_invalid', 'serde_roundtrip'],
    'hlc/tests/serde.rs',
  );

  assertOwnsTests(
    read(path.join(hlcTestsDir, 'surface.rs')),
    ['hlc_surface_tags_are_distinct_and_stable'],
    'hlc/tests/surface.rs',
  );

  assertOwnsTests(
    read(path.join(hlcTestsDir, 'test_version.rs')),
    [
      'assert_test_version_safe_rejects_empty',
      'assert_test_version_safe_rejects_letter_prefix',
      'assert_test_version_safe_rejects_test_ver_literal',
      'test_version_is_lww_safe',
    ],
    'hlc/tests/test_version.rs',
  );

  // Proptests live in a single proptest! block that spans every
  // property; the contract pins the file's existence and the
  // expected proptest names registered inside the macro.
  const proptestsSource = read(path.join(hlcTestsDir, 'proptests.rs'));
  assert.match(
    proptestsSource,
    /proptest!\s*\{/,
    'hlc/tests/proptests.rs should keep its proptest! block',
  );
  for (const expected of [
    'parse_never_panics',
    'parse_never_panics_ascii',
    'new_display_parse_roundtrip',
    'new_rejects_physical_ms_past_ceiling_proptest',
    'new_rejects_noncanonical_suffix',
  ]) {
    assert.match(
      proptestsSource,
      new RegExp(`fn\\s+${expected}\\s*\\(`),
      `hlc/tests/proptests.rs should declare proptest ${expected}`,
    );
  }
});

test('lorvex-domain hlc_state tests stay split by responsibility', () => {
  assert.ok(
    fs.existsSync(hlcStateTestsDir),
    'lorvex-domain/src/hlc_state/tests/ should contain the extracted hlc_state test modules',
  );

  const moduleFiles = fs
    .readdirSync(hlcStateTestsDir)
    .filter((fileName) => fileName.endsWith('.rs'))
    .sort();
  assert.deepEqual(moduleFiles, [
    'construction.rs',
    'generate.rs',
    'overflow.rs',
    'proptests.rs',
    'receive.rs',
  ]);

  assertFacadeShape(
    hlcStateFacade,
    ['construction', 'generate', 'overflow', 'proptests', 'receive'],
    'hlc_state/tests.rs',
  );

  assertOwnsTests(
    read(path.join(hlcStateTestsDir, 'generate.rs')),
    [
      'advance_clock_resets_counter',
      'backward_clock_increments_counter',
      'generate_clamps_far_future_physical_ms_to_ceiling',
      'generate_uses_wall_clock',
      'monotonically_increasing',
      'same_ms_increments_counter',
    ],
    'hlc_state/tests/generate.rs',
  );

  assertOwnsTests(
    read(path.join(hlcStateTestsDir, 'receive.rs')),
    [
      'receive_updates_state_local_ahead',
      'receive_updates_state_remote_ahead',
      'receive_updates_state_same_physical',
      'receive_wall_clock_ahead_resets_counter',
      'update_on_receive_at_ceiling_holds_state_at_ceiling',
    ],
    'hlc_state/tests/receive.rs',
  );

  assertOwnsTests(
    read(path.join(hlcStateTestsDir, 'overflow.rs')),
    [
      'counter_overflow_on_receive_clamps_to_ceiling',
      'counter_overflow_on_receive_recovers',
      'counter_overflow_recovers_by_advancing_physical',
      'generate_saturating_on_max_u32_local_counter',
      'receive_saturating_on_max_u32_remote_counter',
    ],
    'hlc_state/tests/overflow.rs',
  );

  assertOwnsTests(
    read(path.join(hlcStateTestsDir, 'construction.rs')),
    [
      'device_suffix_propagated',
      'hlc_new_rejects_physical_ms_past_ceiling',
      'new_rejects_invalid_device_suffix',
    ],
    'hlc_state/tests/construction.rs',
  );

  const proptestsSource = read(path.join(hlcStateTestsDir, 'proptests.rs'));
  assert.match(
    proptestsSource,
    /proptest!\s*\{/,
    'hlc_state/tests/proptests.rs should keep its proptest! block',
  );
  for (const expected of [
    'generate_with_physical_never_panics',
    'update_on_receive_never_panics',
    'generate_sequence_is_strictly_monotonic',
  ]) {
    assert.match(
      proptestsSource,
      new RegExp(`fn\\s+${expected}\\s*\\(`),
      `hlc_state/tests/proptests.rs should declare proptest ${expected}`,
    );
  }
});
