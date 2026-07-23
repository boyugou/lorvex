import fs from 'node:fs';
import ts from 'typescript';

import { assert } from './contract.mjs';

function normalizeTypeText(typeText) {
  return typeText.replace(/\s+/g, ' ').trim();
}

function hasExportModifier(node) {
  return Boolean(node.modifiers?.some((modifier) => modifier.kind === ts.SyntaxKind.ExportKeyword));
}

export function walk(node, visitor) {
  visitor(node);
  ts.forEachChild(node, (child) => walk(child, visitor));
}

export function parseTypeScriptFile(filePath, scriptKind) {
  const source = fs.readFileSync(filePath, 'utf8');
  return ts.createSourceFile(filePath, source, ts.ScriptTarget.Latest, true, scriptKind);
}

function findExportedTypeAlias(sourceFile, name) {
  return sourceFile.statements.find((statement) =>
    ts.isTypeAliasDeclaration(statement)
    && statement.name.text === name
    && hasExportModifier(statement));
}

export function findExportedInterface(sourceFile, name) {
  return sourceFile.statements.find((statement) =>
    ts.isInterfaceDeclaration(statement)
    && statement.name.text === name
    && hasExportModifier(statement));
}

export function findExportedFunction(sourceFile, name) {
  return sourceFile.statements.find((statement) =>
    ts.isFunctionDeclaration(statement)
    && statement.name?.text === name
    && hasExportModifier(statement));
}

export function assertUnionLiteralType(sourceFile, typeAliasName, expectedLiterals, message) {
  const declaration = findExportedTypeAlias(sourceFile, typeAliasName);
  assert(Boolean(declaration), message);

  const typeNode = declaration.type;
  assert(ts.isUnionTypeNode(typeNode), message);

  const literals = [];
  for (const member of typeNode.types) {
    if (
      ts.isLiteralTypeNode(member)
      && (ts.isStringLiteral(member.literal) || ts.isNoSubstitutionTemplateLiteral(member.literal))
    ) {
      literals.push(member.literal.text);
    }
  }

  assert(literals.length === expectedLiterals.length, message);
  for (const expected of expectedLiterals) {
    assert(literals.includes(expected), message);
  }
}

export function assertExportedFunctionWithReturnType(sourceFile, name, expectedReturnType, message) {
  const declaration = findExportedFunction(sourceFile, name);
  assert(Boolean(declaration), message);
  assert(Boolean(declaration.type), message);
  const returnType = normalizeTypeText(declaration.type.getText(sourceFile));
  assert(returnType === expectedReturnType, message);
}

export function isCallToIdentifier(node, identifier) {
  return ts.isCallExpression(node)
    && ts.isIdentifier(node.expression)
    && node.expression.text === identifier;
}

export function hasCallExpressionByIdentifier(sourceFile, identifierName) {
  let found = false;
  walk(sourceFile, (node) => {
    if (found) return;
    if (isCallToIdentifier(node, identifierName)) {
      found = true;
    }
  });
  return found;
}
