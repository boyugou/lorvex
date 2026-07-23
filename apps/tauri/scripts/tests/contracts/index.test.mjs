import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const currentFile = fileURLToPath(import.meta.url);
const contractsDir = path.dirname(currentFile);

function discoverContractTests(dir) {
  const files = [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      files.push(...discoverContractTests(full));
      continue;
    }
    if (!entry.isFile() || !entry.name.endsWith('.test.mjs')) {
      continue;
    }
    if (full === currentFile) {
      continue;
    }
    files.push(full);
  }
  return files;
}

const contractTestFiles = discoverContractTests(contractsDir).sort((left, right) =>
  path.relative(contractsDir, left).localeCompare(path.relative(contractsDir, right)),
);

for (const fileName of contractTestFiles) {
  await import(pathToFileURL(fileName).href);
}
