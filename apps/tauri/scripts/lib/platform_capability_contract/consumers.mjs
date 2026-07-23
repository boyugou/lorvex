import {
  assertExportedFunctionWithReturnType,
  findExportedFunction,
  hasCallExpressionByIdentifier,
  isCallToIdentifier,
  walk,
} from './ast.mjs';
import { assert } from './contract.mjs';

function hasUseRuntimeProfileDelegation(sourceFile) {
  const hookDeclaration = findExportedFunction(sourceFile, 'useRuntimeProfile');
  if (!hookDeclaration?.body) return false;
  let found = false;
  walk(hookDeclaration.body, (node) => {
    if (found) return;
    if (isCallToIdentifier(node, 'getRuntimeProfile')) {
      found = true;
    }
  });
  return found;
}

export function assertRuntimeProfileConsumerContracts({
  appSourceFile,
  listViewSourceFile,
  platformHookSourceFile,
  settingsSourceFile,
  syncSourceFile,
  todayViewSourceFile,
}) {
  assertExportedFunctionWithReturnType(
    platformHookSourceFile,
    'useRuntimeProfile',
    'RuntimeProfile',
    'useRuntimeProfile.ts must export useRuntimeProfile(): RuntimeProfile',
  );

  assert(
    hasUseRuntimeProfileDelegation(platformHookSourceFile),
    'useRuntimeProfile.ts must delegate to getRuntimeProfile()',
  );

  assert(
    hasCallExpressionByIdentifier(appSourceFile, 'useRuntimeProfile'),
    'App.tsx must consume useRuntimeProfile() as canonical runtime capability source',
  );

  assert(
    hasCallExpressionByIdentifier(settingsSourceFile, 'useRuntimeProfile'),
    'SettingsView.tsx must consume useRuntimeProfile() as canonical runtime capability source',
  );

  assert(
    hasCallExpressionByIdentifier(syncSourceFile, 'getRuntimeProfile'),
    'app/src/lib/sync/ must consume getRuntimeProfile() for runtime platform capability decisions',
  );

  assert(
    hasCallExpressionByIdentifier(todayViewSourceFile, 'useRuntimeProfile'),
    'TodayView.tsx must consume useRuntimeProfile() for runtime capability checks',
  );

  assert(
    hasCallExpressionByIdentifier(listViewSourceFile, 'useRuntimeProfile'),
    'ListView.tsx must consume useRuntimeProfile() for runtime capability checks',
  );
}
