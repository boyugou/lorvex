import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

const rootPath = path.join(repoRoot, 'lorvex-sync/tests/apply_integration.rs');
const testsDir = path.join(repoRoot, 'lorvex-sync/tests/apply_integration');

function read(relativePath) {
  return fs.readFileSync(path.join(testsDir, relativePath), 'utf8');
}

