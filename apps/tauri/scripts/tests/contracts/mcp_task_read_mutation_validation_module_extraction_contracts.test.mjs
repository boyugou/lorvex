import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

const ROOT_PATH = 'mcp-server/src/server/tests/tasks/read_and_mutation_validation.rs';
const MODULE_DIR = 'mcp-server/src/server/tests/tasks/read_and_mutation_validation';

function read(relativePath) {
  return fs.readFileSync(path.join(repoRoot, relativePath), 'utf8');
}

function assertOwnsTest(source, testName, label) {
  assert.match(source, new RegExp(`\\nfn ${testName}\\b`), `${label} should own ${testName}`);
}

