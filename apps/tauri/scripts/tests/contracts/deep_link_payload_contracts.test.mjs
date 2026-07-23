import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { readAppSources, readIpcSources, readRustSources } from './shared.mjs';

function readRouteStringsFromRustPayload(source) {
  return Array.from(
    source.matchAll(/route:\s*"([^"]+)"\.to_string\(\)/g),
    (item) => item[1],
  );
}

function readRouteStringsFromTsInterface(source) {
  const match = source.match(/export interface DeepLinkTarget \{\s*route:\s*([^;]+);/);
  assert.ok(match, 'Expected DeepLinkTarget route union in ipc.ts');
  return Array.from(match[1].matchAll(/'([^']+)'/g), (item) => item[1]);
}

function readApplyDeepLinkHandledRoutes(source) {
  const match = source.match(/const applyDeepLinkTarget = useCallback\(\(target: DeepLinkTarget \| null\) => \{([\s\S]*?)\n  \}, \[(?:navigateToView, openQuickCapture|openQuickCapture, navigateToView|navigateToView)\]\);/);
  assert.ok(match, 'Expected applyDeepLinkTarget in App.tsx');
  return {
    body: match[1],
    routes: Array.from(match[1].matchAll(/target\.route === '([^']+)'/g), (item) => item[1]),
  };
}

test('deep-link payload routes stay aligned between Rust serialization and TypeScript transport types', () => {
  const rustSource = readRustSources('app/src-tauri/src/deep_link/target.rs');
  const tsSource = readIpcSources();

  const rustRoutes = [...new Set(readRouteStringsFromRustPayload(rustSource))].sort();
  const tsRoutes = readRouteStringsFromTsInterface(tsSource).sort();

  assert.deepEqual(
    tsRoutes,
    rustRoutes,
    'DeepLinkTarget route union should match the Rust DeepLinkTargetPayload serialization routes exactly',
  );
});

test('App deep-link handler explicitly handles every transported route with the expected task selection semantics', () => {
  const appSource = readAppSources();
  const tsSource = readIpcSources();

  const tsRoutes = readRouteStringsFromTsInterface(tsSource).sort();
  const { body, routes } = readApplyDeepLinkHandledRoutes(appSource);

  assert.deepEqual(
    routes.sort(),
    tsRoutes,
    'applyDeepLinkTarget should explicitly handle every DeepLinkTarget route from ipc.ts',
  );
  assert.match(
    body,
    /if \(target\.route === 'task'\) \{\s*const taskId = typeof target\.task_id === 'string' \? target\.task_id : null;\s*navigateToView\(\{ type: 'today' }\);\s*if \(taskId === null\) \{\s*setSelectedTaskId\(null\);\s*return;\s*}\s*setSelectedTaskId\(taskId\);/,
    'task deep-links should preserve the exact task_id string and only clear selection when the payload omits task_id entirely',
  );
  assert.match(
    body,
    /if \(target\.route === 'quick_capture'\) \{\s*setSelectedTaskId\(null\);\s*(?:setShowCapture\(true\)|openQuickCapture\(\));\s*return;\s*}/,
    'quick capture deep-links should open the capture overlay through the canonical helper and clear any selected task detail',
  );
  assert.match(
    body,
    /if \(target\.route === 'today'\) \{\s*navigateToView\(\{ type: 'today' }\);\s*setSelectedTaskId\(null\);/,
    'today deep-links should route to Today and clear any selected task detail',
  );
});
