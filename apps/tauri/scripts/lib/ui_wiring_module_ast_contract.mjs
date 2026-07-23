import fs from 'node:fs';
import path from 'node:path';
import ts from 'typescript';
import { fileURLToPath } from 'node:url';

function resolveRepoRoot() {
  const scriptPath = fileURLToPath(import.meta.url);
  return path.resolve(path.dirname(scriptPath), '../..');
}

function readSourceFile(filePath, scriptKind) {
  if (!fs.existsSync(filePath)) {
    throw new Error(`Missing file: ${filePath}`);
  }
  const source = fs.readFileSync(filePath, 'utf8');
  return ts.createSourceFile(filePath, source, ts.ScriptTarget.Latest, true, scriptKind);
}

function readSourceTree(dirPath, scriptKind) {
  if (!fs.existsSync(dirPath)) {
    throw new Error(`Missing directory: ${dirPath}`);
  }

  const parts = [];
  const walkTree = (currentPath) => {
    const entries = fs.readdirSync(currentPath, { withFileTypes: true })
      .sort((left, right) => left.name.localeCompare(right.name));
    for (const entry of entries) {
      const fullPath = path.join(currentPath, entry.name);
      if (entry.isDirectory()) {
        walkTree(fullPath);
        continue;
      }
      if (/\.(?:ts|tsx)$/.test(entry.name)) {
        parts.push(fs.readFileSync(fullPath, 'utf8'));
      }
    }
  };

  walkTree(dirPath);
  return ts.createSourceFile(dirPath, parts.join('\n'), ts.ScriptTarget.Latest, true, scriptKind);
}

function readSidebarSource(repoRoot) {
  const sidebarDirPath = path.join(repoRoot, 'app', 'src', 'components', 'sidebar');
  if (fs.existsSync(sidebarDirPath)) {
    return readSourceTree(sidebarDirPath, ts.ScriptKind.TSX);
  }
  const sidebarPath = path.join(repoRoot, 'app', 'src', 'components', 'Sidebar.tsx');
  return readSourceFile(sidebarPath, ts.ScriptKind.TSX);
}

function walk(node, visitor) {
  visitor(node);
  ts.forEachChild(node, (child) => walk(child, visitor));
}

function unwrapInitializer(node) {
  let current = node;
  while (
    ts.isAsExpression(current)
    || ts.isSatisfiesExpression(current)
    || ts.isParenthesizedExpression(current)
    || ts.isTypeAssertionExpression(current)
  ) {
    current = current.expression;
  }
  return current;
}

function isStringLiteralNode(node) {
  return ts.isStringLiteral(node) || ts.isNoSubstitutionTemplateLiteral(node);
}

function stringLiteralValue(node) {
  return isStringLiteralNode(node) ? node.text : null;
}

function extractTopLevelConstStringArray(sourceFile, constName) {
  for (const statement of sourceFile.statements) {
    if (!ts.isVariableStatement(statement)) continue;
    for (const declaration of statement.declarationList.declarations) {
      if (!ts.isIdentifier(declaration.name) || declaration.name.text !== constName) continue;
      if (!declaration.initializer) {
        throw new Error(`Could not find const array: ${constName}`);
      }
      const initializer = unwrapInitializer(declaration.initializer);
      if (!ts.isArrayLiteralExpression(initializer)) {
        throw new Error(`Could not find const array: ${constName}`);
      }
      const values = initializer.elements
        .map((element) => stringLiteralValue(element))
        .filter((value) => typeof value === 'string');
      if (values.length === 0) {
        throw new Error(`No string values found for const array: ${constName}`);
      }
      return values;
    }
  }
  throw new Error(`Could not find const array: ${constName}`);
}

function extractSidebarModuleOptionIds(sourceFile) {
  for (const statement of sourceFile.statements) {
    if (!ts.isVariableStatement(statement)) continue;
    for (const declaration of statement.declarationList.declarations) {
      if (!ts.isIdentifier(declaration.name) || declaration.name.text !== 'SIDEBAR_MODULE_OPTIONS') continue;
      if (!declaration.initializer) continue;
      const initializer = unwrapInitializer(declaration.initializer);
      if (!ts.isArrayLiteralExpression(initializer)) continue;

      const ids = [];
      for (const element of initializer.elements) {
        if (!ts.isObjectLiteralExpression(element)) continue;
        for (const property of element.properties) {
          if (!ts.isPropertyAssignment(property)) continue;
          if (!ts.isIdentifier(property.name) || property.name.text !== 'id') continue;
          const id = stringLiteralValue(property.initializer);
          if (id) {
            ids.push(id);
          }
        }
      }

      if (ids.length === 0) {
        throw new Error('No sidebar module option ids found in SIDEBAR_MODULE_OPTIONS');
      }
      return ids;
    }
  }

  throw new Error('Could not find SIDEBAR_MODULE_OPTIONS array');
}

function extractCanShowModuleArgsFromSource(sourceFile) {
  const ids = new Set();
  let hasDynamicGuard = false;

  const visit = (node, insideFunctionBody = false) => {
    const nextInsideFunctionBody = insideFunctionBody
      || ts.isFunctionDeclaration(node)
      || ts.isFunctionExpression(node)
      || ts.isArrowFunction(node)
      || ts.isMethodDeclaration(node);

    if (nextInsideFunctionBody && ts.isCallExpression(node)) {
      if (ts.isIdentifier(node.expression) && node.expression.text === 'canShowModule') {
        const [firstArg] = node.arguments;
        const id = firstArg ? stringLiteralValue(firstArg) : null;
        if (id) {
          ids.add(id);
        } else if (firstArg) {
          // Dynamic argument (e.g. `canShowModule(def.module)`) means the sidebar
          // tree is delegating module visibility through a shared data-driven path.
          hasDynamicGuard = true;
        }
      }
    }

    ts.forEachChild(node, (child) => visit(child, nextInsideFunctionBody));
  };

  visit(sourceFile);
  return { ids, hasDynamicGuard };
}

function isViewTypeAccess(node) {
  return ts.isPropertyAccessExpression(node)
    && ts.isIdentifier(node.expression)
    && node.expression.text === 'view'
    && node.name.text === 'type';
}

function extractViewTypeComparisonsFromFunction(sourceFile, functionName) {
  const declaration = findFunctionDeclaration(sourceFile, functionName);
  if (!declaration?.body) {
    throw new Error(`Could not find function declaration: ${functionName}`);
  }

  const viewTypes = new Set();
  walk(declaration.body, (node) => {
    if (ts.isSwitchStatement(node) && isViewTypeAccess(node.expression)) {
      for (const clause of node.caseBlock.clauses) {
        if (!ts.isCaseClause(clause)) continue;
        const value = stringLiteralValue(clause.expression);
        if (value) {
          viewTypes.add(value);
        }
      }
      return;
    }

    if (!ts.isBinaryExpression(node)) return;
    if (
      node.operatorToken.kind !== ts.SyntaxKind.EqualsEqualsEqualsToken
      && node.operatorToken.kind !== ts.SyntaxKind.EqualsEqualsToken
    ) {
      return;
    }

    if (isViewTypeAccess(node.left)) {
      const right = stringLiteralValue(node.right);
      if (right) {
        viewTypes.add(right);
      }
      return;
    }

    if (isViewTypeAccess(node.right)) {
      const left = stringLiteralValue(node.left);
      if (left) {
        viewTypes.add(left);
      }
    }
  });
  return viewTypes;
}

function findFunctionDeclaration(sourceFile, functionName) {
  return sourceFile.statements.find((statement) =>
    ts.isFunctionDeclaration(statement)
    && statement.name?.text === functionName);
}

function extractSidebarModuleMapRecord(sourceFile) {
  for (const statement of sourceFile.statements) {
    if (!ts.isVariableStatement(statement)) continue;
    for (const declaration of statement.declarationList.declarations) {
      if (!ts.isIdentifier(declaration.name) || declaration.name.text !== 'SIDEBAR_MODULE_MAP') continue;
      if (!declaration.initializer) continue;
      const initializer = unwrapInitializer(declaration.initializer);
      if (!ts.isObjectLiteralExpression(initializer)) continue;

      const mappings = new Map();
      for (const property of initializer.properties) {
        if (!ts.isPropertyAssignment(property)) continue;
        const viewType = ts.isIdentifier(property.name)
          ? property.name.text
          : stringLiteralValue(property.name);
        const moduleId = stringLiteralValue(property.initializer);
        if (!viewType || moduleId == null) continue;
        mappings.set(viewType, moduleId);
      }

      if (mappings.size > 0) {
        return mappings;
      }
    }
  }

  return null;
}

function extractMapViewToSidebarModuleMap(sourceFile) {
  const recordMappings = extractSidebarModuleMapRecord(sourceFile);
  if (recordMappings) {
    return recordMappings;
  }

  const declaration = findFunctionDeclaration(sourceFile, 'mapViewToSidebarModule');
  if (!declaration?.body) {
    throw new Error('mapViewToSidebarModule declaration not found');
  }

  const mappings = new Map();
  walk(declaration.body, (node) => {
    if (!ts.isSwitchStatement(node) || !isViewTypeAccess(node.expression)) return;

    for (const clause of node.caseBlock.clauses) {
      if (!ts.isCaseClause(clause)) continue;
      const viewType = stringLiteralValue(clause.expression);
      if (!viewType) continue;
      if (mappings.has(viewType)) {
        throw new Error(`App.tsx mapViewToSidebarModule contains duplicate case for view type: ${viewType}`);
      }

      const returnStatement = clause.statements.find((statement) =>
        ts.isReturnStatement(statement)
        && statement.expression
        && stringLiteralValue(statement.expression));
      if (!returnStatement || !returnStatement.expression) continue;
      const moduleId = stringLiteralValue(returnStatement.expression);
      if (moduleId) {
        mappings.set(viewType, moduleId);
      }
    }
  });

  if (mappings.size === 0) {
    throw new Error('mapViewToSidebarModule mappings not found');
  }

  return mappings;
}

export function verifyUiWiringModuleAstContracts({ repoRoot = resolveRepoRoot() } = {}) {
  const sidebarModulesPath = path.join(repoRoot, 'app', 'src', 'lib', 'sidebarModules.ts');
  const generalSettingsDirPath = path.join(
    repoRoot,
    'app',
    'src',
    'components',
    'settings',
    'general',
  );
  const appPath = path.join(repoRoot, 'app', 'src', 'App.tsx');
  const appShellDirPath = path.join(repoRoot, 'app', 'src', 'app-shell');
  const mainViewContentPath = path.join(repoRoot, 'app', 'src', 'components', 'MainViewContent.tsx');

  const sidebarModulesSourceFile = readSourceFile(sidebarModulesPath, ts.ScriptKind.TS);
  const generalSettingsSectionSourceFile = readSourceTree(generalSettingsDirPath, ts.ScriptKind.TSX);
  const sidebarSourceFile = readSidebarSource(repoRoot);
  const appSourceFile = fs.existsSync(appShellDirPath)
    ? readSourceTree(appShellDirPath, ts.ScriptKind.TSX)
    : readSourceFile(appPath, ts.ScriptKind.TSX);
  const mainViewContentSourceFile = readSourceFile(mainViewContentPath, ts.ScriptKind.TSX);

  const primaryModules = extractTopLevelConstStringArray(sidebarModulesSourceFile, 'SIDEBAR_PRIMARY_MODULES');
  const secondaryModules = extractTopLevelConstStringArray(sidebarModulesSourceFile, 'SIDEBAR_SECONDARY_MODULES');
  const allModules = Array.from(new Set([...primaryModules, ...secondaryModules]));

  const settingsOptionIds = new Set(extractSidebarModuleOptionIds(generalSettingsSectionSourceFile));
  const sidebarGuardResult = extractCanShowModuleArgsFromSource(sidebarSourceFile);
  // If the sidebar uses a dynamic guard (e.g. canShowModule(def.module)), all modules are covered.
  const sidebarGuardIds = sidebarGuardResult.hasDynamicGuard
    ? new Set(allModules)
    : sidebarGuardResult.ids;
  const mainViewTypes = extractViewTypeComparisonsFromFunction(mainViewContentSourceFile, 'MainViewContent');
  const mapViewMappings = extractMapViewToSidebarModuleMap(appSourceFile);

  const actionOnlyModules = new Set(['focus']);
  const moduleViewMap = new Map();
  for (const [viewType, moduleId] of mapViewMappings.entries()) {
    if (!allModules.includes(moduleId)) continue;
    if (actionOnlyModules.has(moduleId)) continue;
    if (moduleViewMap.has(moduleId)) {
      throw new Error(`mapViewToSidebarModule contains duplicate module mapping for: ${moduleId}`);
    }
    moduleViewMap.set(moduleId, viewType);
  }

  const missingSettingsOptions = allModules.filter((moduleId) => !settingsOptionIds.has(moduleId));
  const missingSidebarVisibilityGuards = allModules.filter((moduleId) => !sidebarGuardIds.has(moduleId));
  const missingAppRenderBranches = Array.from(moduleViewMap.entries())
    .filter(([, viewType]) => !mainViewTypes.has(viewType))
    .map(([moduleId]) => moduleId);
  const missingAppModuleGuardMappings = allModules
    .filter((moduleId) => !actionOnlyModules.has(moduleId))
    .filter((moduleId) => !moduleViewMap.has(moduleId));

  return {
    allModules,
    missingSettingsOptions,
    missingSidebarVisibilityGuards,
    missingAppRenderBranches,
    missingAppModuleGuardMappings,
  };
}
