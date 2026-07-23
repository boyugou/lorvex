import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

const rootPath = path.join(repoRoot, 'app/src-tauri/src/error.rs');
const moduleDir = path.join(repoRoot, 'app/src-tauri/src/error');

function read(relativePath) {
  return fs.readFileSync(path.join(moduleDir, relativePath), 'utf8');
}

test('Tauri app error boundary is split into focused modules', () => {
  const rootSource = fs.readFileSync(rootPath, 'utf8');
  assert.match(rootSource, /Typed error enum for the Tauri app crate/);
  assert.ok(
    rootSource.split('\n').length <= 90,
    'app/src-tauri/src/error.rs should stay a small public facade',
  );
  assert.doesNotMatch(
    rootSource,
    /\npub enum AppError\b|\npub struct CommandError\b|\nimpl CommandError\b|\nimpl From<AppError> for String\b|\nfn app_error_/,
    'error.rs should not keep type, envelope, boundary, or test implementations inline',
  );

  for (const moduleName of ['boundary', 'conversions', 'envelope', 'tests', 'types']) {
    assert.match(
      rootSource,
      new RegExp(`^mod ${moduleName};$`, 'm'),
      `error.rs should register ${moduleName}.rs`,
    );
    assert.ok(
      fs.existsSync(path.join(moduleDir, `${moduleName}.rs`)),
      `${moduleName}.rs should exist under app/src-tauri/src/error/`,
    );
  }

  // CommandError / CommandErrorKind live inside `envelope.rs` and are
  // consumed via the `impl From<AppError> for String` boundary
  // conversion in `boundary.rs`. The crate-level re-export was retired
  // in commit 4dc068b43 because nothing outside the `error/` module
  // names those types directly; assert structural ownership instead so
  // a regression that re-introduces the redundant facade or moves the
  // types out of `envelope.rs` still trips this contract.
  assert.match(rootSource, /^pub use types::\{AppError, AppResult\};$/m);
  assert.doesNotMatch(
    rootSource,
    /^pub use envelope::/m,
    'error.rs should not re-export envelope items — they are an internal boundary detail',
  );

  assert.match(read('types.rs'), /\npub enum AppError\b/);
  assert.match(read('types.rs'), /\npub type AppResult<T> = Result<T, AppError>;/);

  assert.match(read('envelope.rs'), /\npub enum CommandErrorKind\b/);
  assert.match(read('envelope.rs'), /\npub struct CommandError\b/);
  assert.match(read('envelope.rs'), /\nimpl CommandError\b/);

  assert.match(read('boundary.rs'), /\nimpl From<AppError> for String\b/);
  assert.match(read('boundary.rs'), /\nfn append_app_error_boundary_log_best_effort\b/);

  assert.match(read('conversions.rs'), /\nimpl From<lorvex_sync::apply::ApplyError> for AppError\b/);
  assert.match(read('conversions.rs'), /\nimpl From<lorvex_runtime::RuntimeError> for AppError\b/);

  assert.match(read('tests.rs'), /\bfn\s+app_error_disk_full_emits_typed_envelope\b/);
  assert.match(read('tests.rs'), /\bfn\s+app_error_boundary_persists_internal_diagnostic_row\b/);
});
