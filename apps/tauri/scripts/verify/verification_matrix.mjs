#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { displayCommand, verificationDocs } from './verification_manifest.mjs';

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const writeMode = process.argv.includes('--write');

const targets = [
  {
    file: 'CONTRIBUTING.md',
    block: 'contributing',
    render: renderContributing,
  },
  {
    file: 'README.md',
    block: 'readme',
    render: renderReadme,
  },
  {
    file: 'CONTRIBUTING.md',
    block: 'contributing-pr',
    render: renderContributingPr,
  },
];

const failures = [];
for (const target of targets) {
  const absolutePath = path.join(repoRoot, target.file);
  const current = fs.readFileSync(absolutePath, 'utf8');
  const next = replaceBlock(current, target.block, target.render());
  if (next !== current) {
    if (writeMode) {
      fs.writeFileSync(absolutePath, next);
    } else {
      failures.push(target.file);
    }
  }
}

if (failures.length > 0) {
  console.error('Verification matrix drift detected in:');
  for (const failure of failures) {
    console.error(`- ${failure}`);
  }
  console.error('Run `npm run docs:verification-matrix` to refresh generated blocks.');
  process.exit(1);
}

function replaceBlock(source, blockName, rendered) {
  const start = `<!-- verification-matrix:${blockName}:start -->`;
  const end = `<!-- verification-matrix:${blockName}:end -->`;
  const startIndex = source.indexOf(start);
  const endIndex = source.indexOf(end);

  if (startIndex === -1 || endIndex === -1 || endIndex < startIndex) {
    throw new Error(`Missing verification matrix markers for ${blockName}`);
  }

  const before = source.slice(0, startIndex + start.length);
  const startLineStart = source.lastIndexOf('\n', startIndex) + 1;
  const markerLinePrefix = source.slice(startLineStart, startIndex);
  const after = source.slice(endIndex);
  return `${before}\n${rendered.trimEnd()}\n${markerLinePrefix}${after}`;
}

function renderContributing() {
  const lines = ['```bash'];
  for (const section of verificationDocs.contributing) {
    lines.push(`# ${section.title}`);
    for (const command of section.commands) {
      lines.push(displayCommand(command));
    }
    lines.push('');
  }
  lines.pop();
  lines.push('```');
  return lines.join('\n');
}

function renderReadme() {
  return [
    'Quick local verification subset. For the full canonical completion matrix, see [CONTRIBUTING.md#verification-commands](CONTRIBUTING.md#verification-commands).',
    '',
    '```bash',
    ...verificationDocs.readme.map(displayCommand),
    '```',
  ].join('\n');
}

function renderContributingPr() {
  const lines = [
    '```bash',
    ...verificationDocs.contributingPr.map(displayCommand),
    '```',
  ];
  return lines.map((line) => `   ${line}`).join('\n');
}

