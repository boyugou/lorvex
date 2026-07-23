import ts from 'typescript';

import {
  assertExportedFunctionWithReturnType,
  assertUnionLiteralType,
  findExportedFunction,
  findExportedInterface,
  isCallToIdentifier,
  walk,
} from './ast.mjs';
import { assert } from './contract.mjs';

function statementHasUnknownReturn(statement) {
  let found = false;
  walk(statement, (node) => {
    if (found) return;
    if (!ts.isReturnStatement(node)) return;
    if (!node.expression) return;
    if (
      (ts.isStringLiteral(node.expression) || ts.isNoSubstitutionTemplateLiteral(node.expression))
      && node.expression.text === 'unknown'
    ) {
      found = true;
    }
  });
  return found;
}

function isModernMobileRuntimeGuardCondition(node) {
  if (!ts.isBinaryExpression(node)) {
    return false;
  }
  const op = node.operatorToken.kind;
  if (
    op !== ts.SyntaxKind.ExclamationEqualsEqualsToken
    && op !== ts.SyntaxKind.ExclamationEqualsToken
  ) {
    return false;
  }
  const callsMobileDetect = (side) => isCallToIdentifier(side, 'detectMobilePlatform');
  const isUnknownLiteral = (side) =>
    (ts.isStringLiteral(side) || ts.isNoSubstitutionTemplateLiteral(side))
    && side.text === 'unknown';
  return (callsMobileDetect(node.left) && isUnknownLiteral(node.right))
    || (callsMobileDetect(node.right) && isUnknownLiteral(node.left));
}

function hasDesktopPlatformMobileGuard(detectDesktopPlatformDeclaration) {
  let guarded = false;
  const body = detectDesktopPlatformDeclaration.body;
  if (!body) return false;

  walk(body, (node) => {
    if (guarded) return;
    if (!ts.isIfStatement(node)) return;
    if (!isModernMobileRuntimeGuardCondition(node.expression)) return;
    if (statementHasUnknownReturn(node.thenStatement)) {
      guarded = true;
    }
  });

  return guarded;
}

export function assertRuntimeProfileModelContracts({ platformLogicSourceFile, platformSourceFile }) {
  assertUnionLiteralType(
    platformLogicSourceFile,
    'DesktopPlatform',
    ['macos', 'windows', 'linux', 'unknown'],
    'platform.logic.ts must export DesktopPlatform union type',
  );

  assertUnionLiteralType(
    platformLogicSourceFile,
    'MobilePlatform',
    ['android', 'unknown'],
    'platform.logic.ts must export MobilePlatform union type',
  );

  assertUnionLiteralType(
    platformLogicSourceFile,
    'RuntimeClass',
    ['desktop', 'mobile', 'unknown'],
    'platform.logic.ts must export RuntimeClass union type',
  );

  assertUnionLiteralType(
    platformLogicSourceFile,
    'RuntimeId',
    ['macos', 'windows', 'linux', 'android', 'unknown'],
    'platform.logic.ts must export RuntimeId union type',
  );

  const runtimeProfileDeclaration = findExportedInterface(platformLogicSourceFile, 'RuntimeProfile');
  assert(Boolean(runtimeProfileDeclaration), 'platform.logic.ts must export RuntimeProfile interface');

  const propertyNames = new Set(
    (runtimeProfileDeclaration?.members ?? [])
      .filter((member) => ts.isPropertySignature(member) && member.name && ts.isIdentifier(member.name))
      .map((member) => member.name.text),
  );
  const requiredProperties = [
    'runtimeClass',
    'runtimeId',
    'supportedSyncBackendKinds',
    'supportsBiometricLock',
    'supportsMcpHosting',
    'supportsNativeCalendarRead',
    'nativeCalendarAdapterKind',
    'nativeCalendarActivationState',
    'trayPresentationKind',
    'supportsTitleBarOverlay',
    'supportsDesktopOverlays',
    'supportsAssistantCommandPolling',
  ];
  for (const propertyName of requiredProperties) {
    assert(propertyNames.has(propertyName), `RuntimeProfile must expose ${propertyName}`);
  }

  const forbiddenProperties = [
    'desktopPlatform',
    'mobilePlatform',
    'isMobileCompanion',
    'isMobileRuntime',
    'isDesktopRuntime',
    'isMacDesktop',
    'isWindowsDesktop',
    'isLinuxDesktop',
    'isAppleRuntime',
    'supportsTrayMenu',
    'supportsRemote providerTransport',
    'supportsFilesystemBridgeTransport',
    'supportsRemote providerBackend',
    'supportsFilesystemBridgeBackend',
    'supportsOverlayWindows',
    'supportsAssistantUiCommandPolling',
    'supportsOverlayTitleBar',
    'supportsNativeWidgets',
    'nativeCalendarSupportLevel',
  ];
  for (const propertyName of forbiddenProperties) {
    assert(!propertyNames.has(propertyName), `RuntimeProfile must not expose legacy ${propertyName}`);
  }

  assertExportedFunctionWithReturnType(
    platformSourceFile,
    'getDesktopPlatform',
    'DesktopPlatform',
    'platform.ts must export getDesktopPlatform(): DesktopPlatform',
  );
  assertExportedFunctionWithReturnType(
    platformSourceFile,
    'getMobilePlatform',
    'MobilePlatform',
    'platform.ts must export getMobilePlatform(): MobilePlatform',
  );
  assertExportedFunctionWithReturnType(
    platformSourceFile,
    'getRuntimeProfile',
    'RuntimeProfile',
    'platform.ts must export getRuntimeProfile(): RuntimeProfile',
  );

  const desktopGuardDeclaration = findExportedFunction(platformLogicSourceFile, 'detectDesktopPlatform');
  assert(
    Boolean(desktopGuardDeclaration) && hasDesktopPlatformMobileGuard(desktopGuardDeclaration),
    "detectDesktopPlatform() must guard detectMobilePlatform(...) !== 'unknown' and return 'unknown'",
  );

  assert(
    !findExportedFunction(platformSourceFile, 'supportsRemote providerTransport'),
    'platform.ts must not keep legacy supportsRemote providerTransport() helper',
  );
}
