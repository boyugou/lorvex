import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { hasRustUseReexport, repoRoot } from './shared.mjs';

const FACADE_PATH = 'lorvex-sync/src/apply/child.rs';
const MODULE_DIR = 'lorvex-sync/src/apply/child';

function read(relativePath) {
  return fs.readFileSync(path.join(repoRoot, relativePath), 'utf8');
}

