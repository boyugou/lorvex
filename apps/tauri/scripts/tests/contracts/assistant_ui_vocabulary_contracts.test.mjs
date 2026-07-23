import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { readRustSources, repoRoot } from './shared.mjs';

test('control_app_ui field schemas reuse shared Rust constants and typed enums', () => {
  // The contract surface for the four `ControlAppUiArgs` vocabulary
  // fields (view / theme / appearance_profile / language) is now
  // expressed two ways at once:
  //
  // 1. The `Option<…>` field type names a closed Rust enum
  //    (`AssistantUiView`, `ThemeMode`, `AppearanceProfile`,
  //    `AssistantUiLanguage`) defined under
  //    `server_contract/ui_control/enums.rs`. Unknown wire variants
  //    fail to deserialize at the JSON Schema / serde layer, so the
  //    historical "X must be one of …" runtime validator is gone.
  //
  // 2. The `#[schemars(description = …)]` decorator on each field
  //    still points at a shared `CONTROL_APP_UI_*_FIELD_DESCRIPTION`
  //    constant in `server_preferences::vocabulary`, so the MCP tool
  //    schema continues to surface a human-readable allowlist for the
  //    assistant. The description constants are built with `concat!`
  //    over the same wire vocabulary tokens that the typed enums
  //    serialize to.
  const contractSource = [
    path.join(repoRoot, 'mcp-server/src/contract.rs'),
    path.join(repoRoot, 'mcp-server/src/contract/ui_control/mod.rs'),
    path.join(repoRoot, 'mcp-server/src/contract/ui_control/enums.rs'),
  ]
    .map((file) => fs.readFileSync(file, 'utf8'))
    .join('\n');
  const preferencesSource = readRustSources(
    'mcp-server/src/preferences/mod.rs',
    'mcp-server/src/preferences/vocabulary.rs',
  );

  const fieldExpectations = [
    {
      descriptionConst: 'CONTROL_APP_UI_VIEW_FIELD_DESCRIPTION',
      enumName: 'AssistantUiView',
      fieldName: 'view',
      sliceConst: 'ASSISTANT_UI_VIEWS',
    },
    {
      descriptionConst: 'CONTROL_APP_UI_THEME_FIELD_DESCRIPTION',
      enumName: 'ThemeMode',
      fieldName: 'theme',
      sliceConst: 'THEME_MODES',
    },
    {
      descriptionConst: 'CONTROL_APP_UI_APPEARANCE_PROFILE_FIELD_DESCRIPTION',
      enumName: 'AppearanceProfile',
      fieldName: 'appearance_profile',
      sliceConst: 'APPEARANCE_PROFILES',
    },
    {
      descriptionConst: 'CONTROL_APP_UI_LANGUAGE_FIELD_DESCRIPTION',
      enumName: 'AssistantUiLanguage',
      fieldName: 'language',
      sliceConst: 'ASSISTANT_UI_LANGUAGES',
    },
  ];

  for (const expectation of fieldExpectations) {
    // The wire-vocabulary slice constant must still exist as the
    // single source of truth that the parity tests in
    // `server_preferences::tests` and the guidance renderer in
    // `server_guidance_support::guide_render` join against.
    assert.match(
      preferencesSource,
      new RegExp(
        `pub\\(crate\\) const ${expectation.sliceConst}: &\\[&str\\] =\\s*&\\[`,
      ),
      `${expectation.sliceConst} should still be defined as a wire-vocabulary slice in server_preferences`,
    );
    // The MCP tool field description constant must be `concat!`-built
    // so the documentation surface is generated, not hand-rolled.
    assert.match(
      preferencesSource,
      new RegExp(
        `pub\\(crate\\) const ${expectation.descriptionConst}: &str = concat!\\(`,
      ),
      `${expectation.descriptionConst} should be a concat!-built description constant`,
    );
    // The `ControlAppUiArgs` field must be typed as the closed Rust
    // enum, with the `#[schemars(description = …)]` decorator pointing
    // at the shared description constant. The old `Option<String>`
    // shape is no longer accepted.
    assert.match(
      contractSource,
      new RegExp(
        `#\\[schemars\\(description = ${expectation.descriptionConst}\\)\\]\\s*pub\\(crate\\) ${expectation.fieldName}: Option<${expectation.enumName}>,`,
        's',
      ),
      `${expectation.fieldName} schema description should reuse ${expectation.descriptionConst} and the field must be typed as Option<${expectation.enumName}>`,
    );
    // The closed enum must live in `enums.rs` with `Deserialize` +
    // `JsonSchema` so unknown variants fail at the deserialize boundary.
    assert.match(
      contractSource,
      new RegExp(
        `pub\\(crate\\) enum ${expectation.enumName}\\b`,
      ),
      `${expectation.enumName} should be defined as a closed Rust enum in server_contract/ui_control`,
    );
  }
});
