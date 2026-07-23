#!/usr/bin/env node

import fs from 'node:fs';
import path from 'node:path';
import ts from 'typescript';
import { fileURLToPath } from 'node:url';

const SCRIPT_TAG = '[verify:platform-capability-matrix-contract]';

function resolveRepoRoot() {
  const scriptPath = fileURLToPath(import.meta.url);
  return path.resolve(path.dirname(scriptPath), '..', '..');
}

function fail(message) {
  throw new Error(`${SCRIPT_TAG} ${message}`);
}

function assert(condition, message) {
  if (!condition) {
    fail(message);
  }
}

function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function parseMarkdownTableRows(source, heading) {
  const sectionPattern = new RegExp(`${escapeRegExp(heading)}\\n\\n([\\s\\S]*?)(?:\\n## |\\n### |$)`);
  const sectionMatch = source.match(sectionPattern);
  assert(sectionMatch?.[1], `missing section: ${heading}`);
  const lines = sectionMatch[1]
    .split('\n')
    .map((line) => line.trim())
    .filter((line) => line.startsWith('|'));

  assert(lines.length >= 3, `${heading} must include a markdown table with at least one data row`);

  return lines.slice(2).map((line) => line
    .split('|')
    .slice(1, -1)
    .map((cell) => cell.trim()));
}

function parseTypeScriptFile(filePath, scriptKind) {
  assert(fs.existsSync(filePath), `missing required file: ${path.relative(resolveRepoRoot(), filePath)}`);
  const source = fs.readFileSync(filePath, 'utf8');
  return ts.createSourceFile(filePath, source, ts.ScriptTarget.Latest, true, scriptKind);
}

function hasExportModifier(node) {
  return Boolean(node.modifiers?.some((modifier) => modifier.kind === ts.SyntaxKind.ExportKeyword));
}

function extractPlatformCapabilityFields(platformLogicSourceFile) {
  const interfaceDecl = platformLogicSourceFile.statements.find((statement) =>
    ts.isInterfaceDeclaration(statement)
    && statement.name.text === 'RuntimeProfile'
    && hasExportModifier(statement));

  // Post-decomposition `RuntimeProfile` is declared in
  // `platform.logic.ts`; `platform.ts` re-exports the type. The
  // capability-matrix contract reads the interface members from the
  // logic module so it inspects the source-of-truth declaration.
  assert(interfaceDecl, 'platform.logic.ts must export RuntimeProfile interface');

  const fields = interfaceDecl.members
    .filter((member) => ts.isPropertySignature(member) && ts.isIdentifier(member.name))
    .map((member) => member.name.text);

  assert(fields.length > 0, 'failed to extract RuntimeProfile fields');
  return fields;
}

export function verifyPlatformCapabilityMatrixContract({ repoRoot = resolveRepoRoot() } = {}) {
  const platformPath = path.join(repoRoot, 'app', 'src', 'lib', 'platform', 'platform.ts');
  // `RuntimeProfile` lives in the sibling logic module since the
  // platform decomposition; we still require the façade exists so
  // downstream consumers continue to import from `./platform`.
  const platformLogicPath = path.join(repoRoot, 'app', 'src', 'lib', 'platform', 'platform.logic.ts');
  const matrixPath = path.join(repoRoot, 'docs', 'design', 'PLATFORM_CAPABILITY_MATRIX.md');
  const distributionPath = path.join(repoRoot, 'docs', 'design', 'DISTRIBUTION.md');

  for (const requiredPath of [
    platformPath,
    platformLogicPath,
    matrixPath,
    distributionPath,
  ]) {
    assert(fs.existsSync(requiredPath), `missing required file: ${path.relative(repoRoot, requiredPath)}`);
  }

  const platformLogicSourceFile = parseTypeScriptFile(platformLogicPath, ts.ScriptKind.TS);
  const matrixSource = fs.readFileSync(matrixPath, 'utf8');
  const distributionSource = fs.readFileSync(distributionPath, 'utf8');

  const capabilityFields = extractPlatformCapabilityFields(platformLogicSourceFile);

  for (const field of capabilityFields) {
    assert(
      matrixSource.includes(`\`${field}\``),
      `PLATFORM_CAPABILITY_MATRIX.md must include RuntimeProfile field: ${field}`,
    );
  }

  const runtimeLabels = [
    'macOS desktop',
    'Windows desktop',
    'Linux desktop',
    'Android mobile runtime',
  ];

  for (const label of runtimeLabels) {
    assert(
      matrixSource.includes(label),
      `PLATFORM_CAPABILITY_MATRIX.md must include runtime/channel label: ${label}`,
    );
  }

  const distributionChannels = [
    'GitHub Releases (macOS DMG)',
    'GitHub Releases (Windows EXE)',
    'GitHub Releases (Linux AppImage + .deb + .rpm)',
    'Homebrew Cask',
  ];

  for (const channel of distributionChannels) {
    assert(
      distributionSource.includes(channel),
      `DISTRIBUTION.md must include channel label: ${channel}`,
    );
    assert(
      matrixSource.includes(channel),
      `PLATFORM_CAPABILITY_MATRIX.md must include channel label: ${channel}`,
    );
  }

  const forbiddenTauriAppleTokens = [
    'iOS mobile runtime',
    '*.pkg',
  ];

  for (const token of forbiddenTauriAppleTokens) {
    assert(
      !matrixSource.includes(token),
      `PLATFORM_CAPABILITY_MATRIX.md must not keep Tauri Apple-store/mobile token: ${token}`,
    );
  }

  const allowedDistributionStatuses = new Set([
    'Developer/reference',
    'Implemented',
    'Planned',
    'Future',
    'Superseded for Tauri',
  ]);
  const expectedDistributionStatuses = new Map([
    ['GitHub Releases (macOS DMG)', 'Developer/reference'],
    ['GitHub Releases (Windows EXE)', 'Implemented'],
    ['GitHub Releases (Linux AppImage + .deb + .rpm)', 'Implemented'],
    ['Homebrew Cask', 'Planned'],
    ['Mac App Store', 'Superseded for Tauri'],
    ['iOS / iPadOS', 'Superseded for Tauri'],
    ['Android', 'Future'],
  ]);
  const distributionRows = parseMarkdownTableRows(distributionSource, '## Distribution Channels');
  const distributionStatusByChannel = new Map(
    distributionRows
      .filter((cells) => cells.length >= 3)
      .map(([channel, status, notes]) => [channel, { status, notes }]),
  );

  for (const [channel, expectedStatus] of expectedDistributionStatuses.entries()) {
    const row = distributionStatusByChannel.get(channel);
    assert(row, `DISTRIBUTION.md must include a Distribution Channels row for ${channel}`);
    assert(
      allowedDistributionStatuses.has(row.status),
      `DISTRIBUTION.md status for ${channel} must use canonical Tauri vocabulary; received: ${row.status}`,
    );
    assert(
      row.status === expectedStatus,
      `DISTRIBUTION.md status for ${channel} must be ${expectedStatus}; received: ${row.status}`,
    );
    assert(
      row.notes.length > 0,
      `DISTRIBUTION.md notes for ${channel} must carry any qualifiers instead of encoding them in the status column`,
    );
  }

  const artifactChecks = [
    { matrixToken: '*.dmg', distributionToken: '.dmg', label: 'macOS dmg release artifact' },
    { matrixToken: '*.exe', distributionToken: '.exe', label: 'Windows exe release artifact' },
    { matrixToken: '*.AppImage', distributionToken: '.AppImage', label: 'Linux AppImage release artifact' },
    { matrixToken: '*.deb', distributionToken: '.deb', label: 'Linux deb release artifact' },
    { matrixToken: '*.rpm', distributionToken: '.rpm', label: 'Linux rpm release artifact' },
  ];

  for (const check of artifactChecks) {
    assert(
      matrixSource.includes(check.matrixToken),
      `matrix missing ${check.label} token (${check.matrixToken})`,
    );
    assert(
      distributionSource.includes(check.distributionToken),
      `distribution doc missing ${check.label} token (${check.distributionToken})`,
    );
  }

  return { ok: true, capabilityFieldCount: capabilityFields.length };
}

function runCli() {
  try {
    const result = verifyPlatformCapabilityMatrixContract();
    console.log(
      `${SCRIPT_TAG} Platform capability matrix contract checks passed (${result.capabilityFieldCount} capability fields verified).`,
    );
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error(message.startsWith(SCRIPT_TAG) ? message : `${SCRIPT_TAG} ${message}`);
    process.exit(1);
  }
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  runCli();
}
