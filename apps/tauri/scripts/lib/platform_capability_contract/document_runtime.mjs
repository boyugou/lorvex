import ts from 'typescript';

import { hasCallExpressionByIdentifier, walk } from './ast.mjs';
import { assert } from './contract.mjs';

function isDocumentElementSetAttributeCall(node) {
  if (!ts.isCallExpression(node)) return false;
  if (!ts.isPropertyAccessExpression(node.expression)) return false;
  if (node.expression.name.text !== 'setAttribute') return false;

  const root = node.expression.expression;
  if (!ts.isPropertyAccessExpression(root)) return false;
  return root.name.text === 'documentElement';
}

function hasDocumentElementAttributeSet(sourceFile, attributeName) {
  let found = false;
  walk(sourceFile, (node) => {
    if (found) return;
    if (!isDocumentElementSetAttributeCall(node)) return;

    const [firstArg] = node.arguments;
    if (
      firstArg
      && (ts.isStringLiteral(firstArg) || ts.isNoSubstitutionTemplateLiteral(firstArg))
      && firstArg.text === attributeName
    ) {
      found = true;
    }
  });
  return found;
}

export function assertMainDocumentRuntimeContract({
  mainRelativePath,
  mainRuntimeRelativePath,
  mainRuntimeSourceFile,
  mainSourceFile,
}) {
  assert(
    hasCallExpressionByIdentifier(mainSourceFile, 'installMainDocumentRuntime'),
    `${mainRelativePath} must call installMainDocumentRuntime()`,
  );

  assert(
    hasDocumentElementAttributeSet(mainRuntimeSourceFile, 'data-desktop-os'),
    `${mainRuntimeRelativePath} must set documentElement data-desktop-os attribute`,
  );

  assert(
    hasDocumentElementAttributeSet(mainRuntimeSourceFile, 'data-mobile-os'),
    `${mainRuntimeRelativePath} must set documentElement data-mobile-os attribute`,
  );
}
