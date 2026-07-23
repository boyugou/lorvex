#!/usr/bin/env node

import path from 'node:path';
import { fileURLToPath } from 'node:url';
import ts from 'typescript';

import { parseTypeScriptFile } from '../lib/platform_capability_contract/ast.mjs';
import { assertRuntimeProfileConsumerContracts } from '../lib/platform_capability_contract/consumers.mjs';
import { SCRIPT_TAG } from '../lib/platform_capability_contract/contract.mjs';
import { assertMainDocumentRuntimeContract } from '../lib/platform_capability_contract/document_runtime.mjs';
import {
  parseSyncSourceDirectory,
  resolvePlatformCapabilityPaths,
} from '../lib/platform_capability_contract/repo_paths.mjs';
import { assertRuntimeProfileModelContracts } from '../lib/platform_capability_contract/runtime_profile.mjs';

export { SCRIPT_TAG };

function resolveRepoRoot() {
  const scriptPath = fileURLToPath(import.meta.url);
  return path.resolve(path.dirname(scriptPath), '..', '..');
}

export function verifyPlatformCapabilityContract({ repoRoot = resolveRepoRoot() } = {}) {
  const paths = resolvePlatformCapabilityPaths(repoRoot);

  const platformSourceFile = parseTypeScriptFile(paths.platformPath, ts.ScriptKind.TS);
  const platformLogicSourceFile = parseTypeScriptFile(paths.platformLogicPath, ts.ScriptKind.TS);
  const platformHookSourceFile = parseTypeScriptFile(paths.platformHookPath, ts.ScriptKind.TS);
  const mainSourceFile = parseTypeScriptFile(paths.mainPath, ts.ScriptKind.TSX);
  const mainRuntimeSourceFile = parseTypeScriptFile(paths.mainRuntimePath, ts.ScriptKind.TS);
  const appSourceFile = parseTypeScriptFile(paths.appPath, ts.ScriptKind.TSX);
  const settingsSourceFile = parseTypeScriptFile(paths.settingsPath, ts.ScriptKind.TSX);
  const syncSourceFile = parseSyncSourceDirectory(paths.syncDirPath);
  const todayViewSourceFile = parseTypeScriptFile(paths.todayViewPath, ts.ScriptKind.TSX);
  const listViewSourceFile = parseTypeScriptFile(paths.listViewPath, ts.ScriptKind.TSX);

  assertRuntimeProfileModelContracts({
    platformLogicSourceFile,
    platformSourceFile,
  });
  assertMainDocumentRuntimeContract({
    mainRelativePath: path.relative(repoRoot, paths.mainPath),
    mainRuntimeRelativePath: path.relative(repoRoot, paths.mainRuntimePath),
    mainRuntimeSourceFile,
    mainSourceFile,
  });
  assertRuntimeProfileConsumerContracts({
    appSourceFile,
    listViewSourceFile,
    platformHookSourceFile,
    settingsSourceFile,
    syncSourceFile,
    todayViewSourceFile,
  });

  return { ok: true };
}

function runCli() {
  try {
    verifyPlatformCapabilityContract();
    console.log(`${SCRIPT_TAG} Platform capability contract checks passed.`);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error(message.startsWith(SCRIPT_TAG) ? message : `${SCRIPT_TAG} ${message}`);
    process.exit(1);
  }
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  runCli();
}
