import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

const SKIP_PATH_PREFIXES = [
  '.worktrees/',
  'app/src-tauri/target/',
  'docs/archive/',
  'node_modules/',
  'target/',
];

const mcpSource = ['mcp-server', 'src'].join('/');
const deletedFlatMcpPathPrefix = [mcpSource, 'server'].join('/') + '_';
const taskValidationModule = ['server', 'task', 'validation'].join('_');
const taskValidationFile = [taskValidationModule, 'rs'].join('.');
const vecLimitsModule = ['server', 'vec', 'limits'].join('_');
const vecLimitsFile = [vecLimitsModule, 'rs'].join('.');
const taskBatchDir = ['server', 'task', 'batch'].join('_');
const workflowRouterDir = ['server', 'workflow', 'router'].join('_');

const DELETED_FLAT_PATH_REFERENCES = [
  deletedFlatMcpPathPrefix,
  ['server', '*/'].join('_'),
  [mcpSource, taskValidationFile].join('/'),
  [mcpSource, vecLimitsFile].join('/'),
  [mcpSource, taskBatchDir, 'complete.rs'].join('/'),
  [mcpSource, workflowRouterDir].join('/'),
  taskValidationModule,
  taskValidationFile,
  vecLimitsModule,
  vecLimitsFile,
  taskBatchDir,
  [taskBatchDir, 'complete.rs'].join('/'),
  workflowRouterDir,
];

function activeRepoFiles() {
  return execFileSync('git', ['ls-files', '-z', '--cached', '--others', '--exclude-standard'], {
    cwd: repoRoot,
  })
    .toString('utf8')
    .split('\0')
    .filter(Boolean)
    .filter((relativePath) => !SKIP_PATH_PREFIXES.some((prefix) => relativePath.startsWith(prefix)))
    .filter((relativePath) => {
      const absolutePath = path.join(repoRoot, relativePath);
      return fs.existsSync(absolutePath) && fs.statSync(absolutePath).isFile();
    });
}

test('active repo text does not reference deleted flat MCP paths', () => {
  const violations = [];
  const staleReferenceBuffers = DELETED_FLAT_PATH_REFERENCES.map((staleReference) => ({
    staleReference,
    buffer: Buffer.from(staleReference, 'utf8'),
  }));

  for (const relativePath of activeRepoFiles()) {
    const source = fs.readFileSync(path.join(repoRoot, relativePath));

    for (const { staleReference, buffer } of staleReferenceBuffers) {
      if (source.includes(buffer)) {
        violations.push(`${relativePath}: ${staleReference}`);
      }
    }
  }

  assert.deepEqual(violations, []);
});
