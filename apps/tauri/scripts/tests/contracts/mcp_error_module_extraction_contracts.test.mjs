import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

const ROOT = path.join(repoRoot, 'mcp-server/src/error.rs');
const DIR = path.join(repoRoot, 'mcp-server/src/error');

function read(relativePath) {
  return fs.readFileSync(path.join(DIR, relativePath), 'utf8');
}

/**
 * `mcp-server/src/error.rs` used to be a 777-line single file
 * mixing the `McpError` enum, `From<…>` impls, the security-
 * sensitive wire encoder, and ~30 unit tests. Splitting them into
 * `types.rs` + `conversions.rs` + `wire.rs` + `tests.rs` makes the
 * encoder independently auditable. The contract pins the post-split
 * layout so a future refactor cannot silently re-collapse the
 * boundary.
 */
test('mcp-server error.rs is a thin facade over typed/conversions/wire/tests submodules', () => {
  const rootSource = fs.readFileSync(ROOT, 'utf8');

  for (const moduleName of ['conversions', 'types', 'wire']) {
    assert.match(
      rootSource,
      new RegExp(`^mod ${moduleName};$`, 'm'),
      `error.rs should declare ${moduleName} submodule`,
    );
  }
  assert.match(
    rootSource,
    /^#\[cfg\(test\)\]\nmod tests;$/m,
    'error.rs should declare a cfg(test) tests submodule',
  );
  assert.match(
    rootSource,
    /^pub use types::McpError;$/m,
    'error.rs should re-export McpError from the types submodule',
  );

  // The facade must stay thin — no inline functions, structs, or
  // tests. (The mod-declaration block plus the rustdoc header is
  // fine.)
  assert.doesNotMatch(
    rootSource,
    /\n#\[test\]|\nfn\s+\w+|\nimpl\s+|\nstruct\s+|\nenum\s+/,
    'error.rs should not host inline fn/struct/enum/impl/test items after the split',
  );

  // Each submodule file must exist.
  for (const moduleFile of ['conversions.rs', 'types.rs', 'wire.rs', 'tests.rs']) {
    assert.ok(
      fs.existsSync(path.join(DIR, moduleFile)),
      `mcp-server/src/error/${moduleFile} should exist`,
    );
  }

  // types.rs owns the enum declarations + the ErrorKind retryable /
  // docs_hint policy.
  const typesSource = read('types.rs');
  assert.match(typesSource, /pub enum McpError\s*\{/);
  assert.match(typesSource, /pub\(crate\) enum ErrorKind\s*\{/);
  // Allow `const fn` after the workspace clippy::missing_const_for_fn
  // sweep promoted side-effect-free signatures to const.
  assert.match(typesSource, /pub\(super\) (?:const )?fn retryable\(self\) -> bool/);
  assert.match(typesSource, /pub\(super\) (?:const )?fn docs_hint\(self\) -> Option<&'static str>/);

  // conversions.rs owns From impls but NOT From<McpError> for String —
  // that wire-format encoder lives in wire.rs.
  const conversionsSource = read('conversions.rs');
  assert.match(conversionsSource, /impl From<lorvex_store::StoreError> for McpError/);
  assert.match(conversionsSource, /impl From<lorvex_sync::error::SyncError> for McpError/);
  assert.match(conversionsSource, /impl From<serde_json::Error> for McpError/);
  assert.match(conversionsSource, /impl From<String> for McpError/);
  assert.doesNotMatch(
    conversionsSource,
    /impl From<McpError> for String/,
    'conversions.rs must not host the wire encoder — it belongs in wire.rs',
  );

  // wire.rs owns sanitize / classify / encode helpers + the protocol
  // boundary `From<McpError> for String`.
  const wireSource = read('wire.rs');
  for (const fn of [
    'fn sanitize_error_message',
    'fn extract_quoted_id',
    'fn sync_error_kind_from_message',
    'fn classify_sql_error',
    'fn classify_sync_error',
    'fn encode_payload',
  ]) {
    // Allow `const fn` after the workspace clippy::missing_const_for_fn
    // sweep promoted side-effect-free signatures to const.
    assert.match(
      wireSource,
      new RegExp(`pub\\(super\\) (?:const )?${fn}\\(`),
      `wire.rs should host ${fn}`,
    );
  }
  assert.match(wireSource, /impl From<McpError> for String/);

  // tests.rs is the cfg(test) submodule body — no nested
  // `mod tests { }` wrapper, since the file IS the tests module.
  const testsSource = read('tests.rs');
  assert.doesNotMatch(
    testsSource,
    /^#\[cfg\(test\)\]\s*\nmod tests \{/m,
    'tests.rs should not nest a `mod tests { }` block — the file IS the tests module',
  );
  assert.match(
    testsSource,
    /use super::types::\{ErrorKind, McpError\};/,
    'tests.rs should reach types via super::types',
  );
  assert.match(
    testsSource,
    /use super::wire::\{[\s\S]*?sanitize_error_message,[\s\S]*?\};/,
    'tests.rs should reach wire helpers via super::wire',
  );

  // Cross-cutting: the test set should still cover every named test
  // from the pre-split file (representative sample).
  for (const expected of [
    'cancellation_stays_as_short_literal',
    'user_message_with_error_prefix_gets_structured',
    'sql_busy_variant_emits_db_busy_kind_retryable_true',
    'sync_variant_emits_sync_conflict_kind_with_docs_hint',
    'timeout_prose_maps_to_sync_conflict',
    'sanitize_caps_very_long_messages',
    'extract_quoted_id_handles_canonical_shape',
    'sync_error_kind_classifier_matches_expected_prose',
    'sql_classifier_distinguishes_busy_from_other_failures',
    'sync_classifier_maps_network_drop_to_sync_conflict',
    'encode_payload_omits_empty_optional_fields',
  ]) {
    assert.match(
      testsSource,
      new RegExp(`fn\\s+${expected}\\s*\\(`),
      `tests.rs should still contain ${expected} after the split`,
    );
  }
});
