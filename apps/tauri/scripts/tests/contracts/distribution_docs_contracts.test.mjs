import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

test('public release docs keep availability wording independent of npm private flag', () => {
  const docs = [
    ['README.md', fs.readFileSync(path.join(repoRoot, 'README.md'), 'utf8')],
    ['docs/design/DISTRIBUTION.md', fs.readFileSync(path.join(repoRoot, 'docs', 'design', 'DISTRIBUTION.md'), 'utf8')],
    ['docs/setup/GETTING_STARTED.md', fs.readFileSync(path.join(repoRoot, 'docs', 'setup', 'GETTING_STARTED.md'), 'utf8')],
  ];

  for (const [label, source] of docs) {
    assert.doesNotMatch(
      source,
      /\bpublic(?:ly)? (?:GitHub release|release availability|artifact|download|prerelease|pre-release|stable distribution|stable channel)|public artifact channel|public release line|publicly shipped/i,
      `${label} should not describe private repository release assets as public downloads`,
    );
    assert.doesNotMatch(
      source,
      /\b(?:this )?repository (?:remains|is) private\b|\bthe repo(?:sitory)? is private\b|\bprivate repository\b/i,
      `${label} should not infer repository visibility from package.json private:true`,
    );
  }

  const readme = docs.find(([label]) => label === 'README.md')?.[1] ?? '';
  const distribution = docs.find(([label]) => label === 'docs/design/DISTRIBUTION.md')?.[1] ?? '';
  const gettingStarted = docs.find(([label]) => label === 'docs/setup/GETTING_STARTED.md')?.[1] ?? '';

  assert.match(
    readme,
    /macOS developer\/reference artifacts/i,
    'README should describe current macOS Tauri artifacts as developer/reference without App Store claims',
  );
  assert.match(
    distribution,
    /Developer\/reference/i,
    'distribution guide should mark the Tauri macOS DMG as developer/reference instead of App Store-facing',
  );
  assert.match(
    gettingStarted,
    /internal or repo-visible package/i,
    'getting started should clarify that installed-app packages are internal or repo-visible today',
  );
  assert.match(
    gettingStarted,
    /Source checkout/i,
    'getting started should keep source checkout as the general path when no package is available',
  );
});

test('updater signing password docs match fail-closed release workflows', () => {
  const envExample = fs.readFileSync(path.join(repoRoot, '.env.build.example'), 'utf8');
  const distributionSource = fs.readFileSync(
    path.join(repoRoot, 'docs', 'design', 'DISTRIBUTION.md'),
    'utf8',
  );

  for (const [label, source] of [
    ['.env.build.example', envExample],
    ['docs/design/DISTRIBUTION.md', distributionSource],
  ]) {
    assert.doesNotMatch(
      source,
      /TAURI_SIGNING_PRIVATE_KEY_PASSWORD[^\n|]*(?:optional|if set)|(?:optional|if set)[^\n|]*TAURI_SIGNING_PRIVATE_KEY_PASSWORD/i,
      `${label} should not describe the updater signing password as optional`,
    );
  }

  assert.match(
    envExample,
    /TAURI_SIGNING_PRIVATE_KEY_PASSWORD=""\s+# Required password protecting the key above/,
    '.env.build.example should describe the updater signing password as required for release parity',
  );
  assert.match(
    distributionSource,
    /`TAURI_SIGNING_PRIVATE_KEY_PASSWORD`\s*\|\s*Required password protecting the updater signing private key/,
    'distribution guide should document the updater signing password as a required secret',
  );
  assert.match(
    distributionSource,
    /Release workflows fail closed unless both `TAURI_SIGNING_PRIVATE_KEY` and `TAURI_SIGNING_PRIVATE_KEY_PASSWORD` are configured/,
    'distribution guide should explain why the password is required in CI release workflows',
  );
});

test('public trust copy follows current source availability policy', () => {
  const securityMessaging = fs.readFileSync(
    path.join(repoRoot, 'docs', 'design', 'SECURITY_MESSAGING.md'),
    'utf8',
  );
  const publicFacingDocs = [
    ['docs/vision/PITCH_EN.md', fs.readFileSync(path.join(repoRoot, 'docs', 'vision', 'PITCH_EN.md'), 'utf8')],
    ['docs/vision/VISION.md', fs.readFileSync(path.join(repoRoot, 'docs', 'vision', 'VISION.md'), 'utf8')],
  ];

  assert.match(
    securityMessaging,
    /public-facing copy must not describe the core as available for public source review/i,
    'canonical security messaging should define the source-availability boundary',
  );

  for (const [label, source] of publicFacingDocs) {
    assert.doesNotMatch(
      source,
      /open-source auditable core|open source from day one|inspect every line of code that touches their data/i,
      `${label} must not claim a public open-source/auditable core before a public source surface exists`,
    );
    assert.match(
      source,
      /planned public core|public core once it exists|public source package/i,
      `${label} should describe source review as a planned public-core/source-availability path`,
    );
  }
});

test('Tauri distribution docs do not keep App Store installer signing workflow contracts', () => {
  const envExample = fs.readFileSync(path.join(repoRoot, '.env.build.example'), 'utf8');
  const distributionSource = fs.readFileSync(
    path.join(repoRoot, 'docs', 'design', 'DISTRIBUTION.md'),
    'utf8',
  );

  for (const secretName of [
    'APPLE_INSTALLER_CERTIFICATE',
    'APPLE_INSTALLER_CERTIFICATE_PASSWORD',
    'APPLE_INSTALLER_SIGNING_IDENTITY',
  ]) {
    assert.doesNotMatch(envExample, new RegExp(`export ${secretName}=""`), `.env.build.example should not document retired ${secretName}`);
    assert.doesNotMatch(distributionSource, new RegExp(`\\\`${secretName}\\\``), `distribution guide should not document retired ${secretName}`);
  }

  assert.match(
    distributionSource,
    /Mac App Store \| Superseded for Tauri \| Ship the Swift app from `apps\/apple` instead\./,
    'distribution guide should route Mac App Store work to apps/apple',
  );
});

test('distribution and macOS menu docs stay aligned with current implemented ids, localization, and canonical status vocabulary', () => {
  const distributionSource = fs.readFileSync(
    path.join(repoRoot, 'docs/design/DISTRIBUTION.md'),
    'utf8',
  );
  const macosMenuSource = fs.readFileSync(
    path.join(repoRoot, 'docs/design/MACOS_MENU_BAR.md'),
    'utf8',
  );
  const appMenuSource = fs.readFileSync(
    path.join(repoRoot, 'app/src-tauri/src/desktop_shell/app_menu.rs'),
    'utf8',
  );
  const menuI18nSource = fs.readFileSync(
    path.join(repoRoot, 'app/src-tauri/src/menu_i18n.rs'),
    'utf8',
  );

  assert.match(
    macosMenuSource,
    /`export_data` \/ `import_data`/,
    'macOS menu spec should document the implemented export_data/import_data ids',
  );
  assert.doesNotMatch(
    macosMenuSource,
    /export_snapshot|import_snapshot/,
    'macOS menu spec should not retain stale snapshot-era menu ids',
  );
  assert.match(
    macosMenuSource,
    /Menu text is localized in Rust before the frontend loads\./,
    'macOS menu spec should document current native-menu localization behavior',
  );
  assert.match(
    macosMenuSource,
    /generated from the canonical JSON locale catalogs/,
    'macOS menu spec should document generated catalog-backed native-menu localization',
  );
  for (const implementedMenuId of ['"export_data"', '"import_data"', '"view_ai_changelog"', '"view_kanban"', '"view_daily_review"', '"view_someday"']) {
    assert.match(
      appMenuSource,
      new RegExp(implementedMenuId),
      `native menu implementation should include ${implementedMenuId}`,
    );
  }
  const documentedViewMenuIds = new Set(
    Array.from(macosMenuSource.matchAll(/\|\s*[^|\n]+\s*\|\s*`(view_[a-z_]+)`\s*\|/g), (match) => match[1]),
  );
  const implementedViewMenuIds = Array.from(
    new Set(Array.from(appMenuSource.matchAll(/with_id\("(view_[a-z_]+)"/g), (match) => match[1])),
  ).sort((left, right) => left.localeCompare(right));
  assert.deepEqual(
    [...documentedViewMenuIds].sort((left, right) => left.localeCompare(right)),
    implementedViewMenuIds,
    'macOS menu View table should document every implemented native view_* menu id',
  );
  assert.match(
    macosMenuSource,
    /\| Recurring \| `view_recurring` \| `Shift\+CmdOrCtrl\+R` \| MenuItem \|/,
    'macOS menu spec should document the implemented Recurring menu item',
  );
  assert.match(
    macosMenuSource,
    /View navigation via menu works for all 14 view types/,
    'macOS menu spec should count the current 14 implemented view types',
  );
  for (const localizedKey of ['ExportData', 'ImportData', 'AiActivity']) {
    assert.match(
      menuI18nSource,
      new RegExp(`\\b${localizedKey},`),
      `native menu i18n enum should include ${localizedKey}`,
    );
  }
  assert.match(menuI18nSource, /menu_i18n\.generated\.rs/);
  assert.doesNotMatch(menuI18nSource, /\("zh",\s*MenuKey::\w+\)\s*=>/);

  const distributionTableMatch = distributionSource.match(
    /## Distribution Channels\s+([\s\S]*?)\n\nStatus vocabulary in this guide:/,
  );
  assert.ok(distributionTableMatch, 'distribution guide should keep a dedicated channel table block');
  const statusValues = (distributionTableMatch[1] ?? '')
    .split('\n')
    .filter((line) => /^\| /.test(line) && !/\|[- ]+\|/.test(line) && !/\|\s*Channel\s*\|/.test(line))
    .map((line) => line.split('|').map((cell) => cell.trim()))
    .filter((cells) => cells.length >= 4)
    .map((cells) => cells[2]);

  assert.deepEqual(
    statusValues,
    ['Developer/reference', 'Implemented', 'Implemented', 'Planned', 'Superseded for Tauri', 'Superseded for Tauri', 'Future'],
    'distribution channel table should keep canonical status values and move qualifiers into notes',
  );
  assert.match(
    distributionSource,
    /GitHub Releases \(macOS DMG\) \| Developer\/reference \| Useful for Mac-only developers; not the future Apple customer channel\./,
    'distribution guide should keep macOS Tauri scoped to developer/reference use',
  );
  assert.match(
    distributionSource,
    /Mac App Store \| Superseded for Tauri \| Ship the Swift app from `apps\/apple` instead\./,
    'distribution guide should distinguish Swift App Store ownership from Tauri direct distribution',
  );
  assert.doesNotMatch(
    distributionSource,
    /Repo-visible prerelease \(|Public prerelease \(|Implemented \(|Planned \(/,
    'distribution guide should not smuggle qualifiers into canonical status values',
  );
  assert.match(
    distributionSource,
    /Current GitHub Releases only prove the repo-visible macOS developer\/reference\s+channel\./,
    'distribution guide should not imply Windows or Linux repo-visible artifacts before releases prove them',
  );
  assert.match(
    distributionSource,
    /`v\*` for multi-platform desktop releases\.[\s\S]*`mac-v\*` for macOS-only developer\/reference prereleases\./,
    'distribution guide should explain the remaining Tauri release tag families',
  );
  for (const releaseMode of ['release_mode=dry-run', 'release_mode=artifacts', 'release_mode=publish']) {
    assert.match(
      distributionSource,
      new RegExp(releaseMode.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')),
      `distribution guide should document ${releaseMode}`,
    );
  }
  assert.match(
    distributionSource,
    /Ordinary branch and `main` pushes are verification-only/,
    'distribution guide should keep ordinary pushes out of release packaging',
  );
  assert.match(
    distributionSource,
    /Actions -> Release -> Run workflow/,
    'distribution guide should document manually dispatching the main release workflow',
  );
  assert.match(
    distributionSource,
    /Actions -> Release macOS Only -> Run workflow/,
    'distribution guide should document manually dispatching the macOS-only release workflow',
  );
  assert.doesNotMatch(distributionSource, /Actions -> Release App Store -> Run workflow/);
  assert.doesNotMatch(
    distributionSource,
    /Pushing a tag by itself does not start a release|manual-dispatch only|Tag push triggers\s+remain commented out/,
    'distribution guide should not retain the old manual-only release trigger policy',
  );
  assert.match(
    distributionSource,
    /Authenticode-signed NSIS installer \(`\.exe`\)/,
    'Windows NSIS distribution docs should describe Authenticode signing, not notarization',
  );
  assert.doesNotMatch(
    distributionSource,
    /notarized NSIS installer/i,
    'Windows NSIS distribution docs must not use macOS notarization wording',
  );
  assert.match(
    distributionSource,
    /Distribution DMGs must be signed with Developer ID and notarized/i,
    'DMG distribution docs should make signing and notarization mandatory for distributed DMGs',
  );
  assert.match(
    distributionSource,
    /unsigned local\s+smoke-test DMGs may be built without\s+credentials, but must not be distributed/i,
    'DMG distribution docs should explicitly allow unsigned local smoke-test DMGs only when they are not distributed',
  );
});
