#!/usr/bin/env node
import { spawn } from 'node:child_process';
import { access } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';

import { displayLabel, releaseBuildGates, releasePreflightGates } from '../verify/verification_manifest.mjs';

const cargoBin = await resolveCargoBin();
const gates = process.env.PREFLIGHT_BUILD === '1'
  ? [...releasePreflightGates, ...releaseBuildGates]
  : releasePreflightGates;

const results = [];
for (const gate of gates) {
  const label = displayLabel(gate);
  const startedAt = Date.now();
  console.log(`\n==> ${label}`);
  const code = await runGate(gate);
  results.push({
    label,
    status: code === 0 ? 'PASS' : 'FAIL',
    durationSeconds: Math.max(0, Math.round((Date.now() - startedAt) / 1000)),
  });
}

printSummary(results);
process.exit(results.some((result) => result.status === 'FAIL') ? 1 : 0);

async function resolveCargoBin() {
  const configured = process.env.CARGO_BIN ?? process.env.CARGO ?? 'cargo';
  if (await commandExists(configured)) {
    return configured;
  }

  const homeCargo = path.join(os.homedir(), '.cargo', 'bin', 'cargo');
  if (await commandExists(homeCargo)) {
    return homeCargo;
  }

  return configured;
}

async function commandExists(command) {
  if (command.includes(path.sep)) {
    try {
      await access(command);
      return true;
    } catch {
      return false;
    }
  }

  const pathValue = process.env.PATH ?? '';
  for (const candidateDir of pathValue.split(path.delimiter)) {
    if (!candidateDir) continue;
    try {
      await access(path.join(candidateDir, command));
      return true;
    } catch {
      // keep scanning PATH
    }
  }
  return false;
}

function runGate(gate) {
  const command = commandForGate(gate);
  return new Promise((resolve) => {
    const child = spawn(command.bin, command.args, { stdio: 'inherit' });
    child.on('error', (error) => {
      console.error(`[release-preflight] failed to start ${displayLabel(gate)}: ${error.message}`);
      resolve(1);
    });
    child.on('close', (code, signal) => {
      if (signal) {
        console.error(`[release-preflight] ${displayLabel(gate)} terminated by ${signal}`);
        resolve(1);
        return;
      }
      resolve(code ?? 1);
    });
  });
}

function commandForGate(gate) {
  switch (gate.kind) {
    case 'npm':
      return {
        bin: 'npm',
        args: ['run', '-s', ...(gate.workspace ? ['-w', gate.workspace] : []), gate.script, ...(gate.args ?? [])],
      };
    case 'cargo':
      return { bin: cargoBin, args: gate.args };
    case 'shell':
      return { bin: gate.command[0], args: gate.command.slice(1) };
    default:
      throw new Error(`unsupported release preflight gate kind: ${gate.kind}`);
  }
}

function printSummary(summaryResults) {
  console.log('\n==> Preflight summary');
  console.log(`${'GATE'.padEnd(50)} ${'RESULT'.padEnd(6)} TIME`);
  console.log('-'.repeat(70));

  for (const result of summaryResults) {
    const color = result.status === 'PASS' ? '\x1b[32m' : '\x1b[31m';
    console.log(
      `${result.label.padEnd(50)} ${color}${result.status.padEnd(6)}\x1b[0m ${result.durationSeconds}s`,
    );
  }

  if (summaryResults.every((result) => result.status === 'PASS')) {
    console.log('\n\x1b[32mAll gates passed.\x1b[0m');
  } else {
    console.log('\n\x1b[31mOne or more gates failed; review output above.\x1b[0m');
  }
}
