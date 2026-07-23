import fs from 'node:fs';
import path from 'node:path';
import ts from 'typescript';

import { readSourceTree } from '../verifier_runtime.mjs';
import { assert } from './contract.mjs';

export function resolvePlatformCapabilityPaths(repoRoot) {
  const paths = {
    appPath: path.join(repoRoot, 'app', 'src', 'App.tsx'),
    listViewPath: path.join(repoRoot, 'app', 'src', 'components', 'ListView.tsx'),
    mainPath: path.join(repoRoot, 'app', 'src', 'main.tsx'),
    mainRuntimePath: path.join(repoRoot, 'app', 'src', 'main.runtime.ts'),
    platformHookPath: path.join(repoRoot, 'app', 'src', 'lib', 'useRuntimeProfile.ts'),
    platformLogicPath: path.join(repoRoot, 'app', 'src', 'lib', 'platform', 'platform.logic.ts'),
    platformPath: path.join(repoRoot, 'app', 'src', 'lib', 'platform', 'platform.ts'),
    settingsPath: path.join(repoRoot, 'app', 'src', 'components', 'SettingsView.tsx'),
    syncDirPath: path.join(repoRoot, 'app', 'src', 'lib', 'sync'),
    todayViewPath: path.join(repoRoot, 'app', 'src', 'components', 'TodayView.tsx'),
  };

  assert(fs.existsSync(paths.platformPath), 'missing app/src/lib/platform/platform.ts');
  assert(fs.existsSync(paths.platformLogicPath), 'missing app/src/lib/platform/platform.logic.ts');
  assert(fs.existsSync(paths.platformHookPath), 'missing app/src/lib/useRuntimeProfile.ts');
  assert(fs.existsSync(paths.mainPath), 'missing app/src/main.tsx');
  assert(fs.existsSync(paths.mainRuntimePath), 'missing app/src/main.runtime.ts');
  assert(fs.existsSync(paths.appPath), 'missing app/src/App.tsx');
  assert(fs.existsSync(paths.settingsPath), 'missing app/src/components/SettingsView.tsx');
  assert(fs.existsSync(paths.syncDirPath) && fs.statSync(paths.syncDirPath).isDirectory(),
    'missing app/src/lib/sync/ directory');
  assert(fs.existsSync(paths.todayViewPath), 'missing app/src/components/TodayView.tsx');
  assert(fs.existsSync(paths.listViewPath), 'missing app/src/components/ListView.tsx');

  return paths;
}

export function parseSyncSourceDirectory(syncDirPath) {
  const source = readSourceTree(syncDirPath);
  return ts.createSourceFile(syncDirPath, source, ts.ScriptTarget.Latest, true, ts.ScriptKind.TS);
}
