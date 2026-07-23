import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

test('theme runtime is organized as thin public root plus provider, context, lifecycle, model, and runtime modules', () => {
  const rootSource = fs.readFileSync(path.join(repoRoot, 'app/src/lib/theme.tsx'), 'utf8');
  const providerSource = fs.readFileSync(path.join(repoRoot, 'app/src/lib/theme/provider.tsx'), 'utf8');
  const contextSource = fs.readFileSync(path.join(repoRoot, 'app/src/lib/theme/context.ts'), 'utf8');
  // The host-lifecycle internals (matchMedia, onFocusChanged) were lifted
  // into a sibling `lifecycle.runtime.ts`; the React-side hooks stay in
  // `lifecycle.ts`. Read both files so the structural assertion still
  // covers system-theme media query tracking and native focus wiring.
  const lifecycleSource = [
    fs.readFileSync(path.join(repoRoot, 'app/src/lib/theme/lifecycle.ts'), 'utf8'),
    fs.existsSync(path.join(repoRoot, 'app/src/lib/theme/lifecycle.runtime.ts'))
      ? fs.readFileSync(path.join(repoRoot, 'app/src/lib/theme/lifecycle.runtime.ts'), 'utf8')
      : '',
  ].join('\n');
  const modelSource = fs.readFileSync(path.join(repoRoot, 'app/src/lib/theme/model.ts'), 'utf8');
  const runtimeSource = fs.readFileSync(path.join(repoRoot, 'app/src/lib/theme/runtime.ts'), 'utf8');

  assert.match(
    rootSource,
    /export \{ ThemeProvider, useTheme \} from '\.\/theme\/provider';/,
    'theme.tsx should expose the provider surface from the dedicated provider module',
  );
  assert.match(
    rootSource,
    /export \{ APPEARANCE_PROFILE_OPTIONS, THEME_OPTIONS \} from '\.\/theme\/model';/,
    'theme.tsx should re-export option registries from the dedicated model module',
  );
  assert.doesNotMatch(
    rootSource,
    /createContext|useState|useEffect|getCurrentWindow|Promise\.all\(\[/,
    'theme.tsx should stay a thin public export surface after folder extraction',
  );

  assert.match(providerSource, /from '\.\/context';/);
  assert.match(providerSource, /from '\.\/lifecycle';/);
  assert.match(providerSource, /export function ThemeProvider\(/);
  assert.match(providerSource, /export function useTheme\(/);
  assert.doesNotMatch(
    providerSource,
    /getCurrentWindow|window\.matchMedia|Promise\.all\(\[/,
    'theme/provider.tsx should compose state and hooks, not own host lifecycle internals',
  );

  assert.match(contextSource, /export interface ThemeContextValue/);
  assert.match(contextSource, /export const ThemeContext = createContext/);
  assert.doesNotMatch(
    contextSource,
    /useState|useEffect|Promise\.all\(\[/,
    'theme/context.ts should stay pure context wiring',
  );

  assert.match(lifecycleSource, /export function useThemePreferenceBootstrap\(/);
  assert.match(lifecycleSource, /export function useThemeRuntimeLifecycle\(/);
  assert.match(
    lifecycleSource,
    /Promise\.all\(\[\s*getPreference\(PREF_THEME\),\s*getPreference\(PREF_APPEARANCE_PROFILE\),\s*\]\)/s,
    'theme/lifecycle.ts should own async preference bootstrap',
  );
  assert.match(
    lifecycleSource,
    /window\.matchMedia\('\(prefers-color-scheme: light\)'\)/,
    'theme/lifecycle.ts should own system-theme media query tracking',
  );
  assert.match(
    lifecycleSource,
    /getCurrentWindow\(\)\.onFocusChanged/,
    'theme/lifecycle.ts should own native focus re-assertion wiring',
  );
  assert.doesNotMatch(
    lifecycleSource,
    /createContext|<ThemeContext\.Provider/,
    'theme/lifecycle.ts should not own React context declarations or provider JSX',
  );

  assert.match(modelSource, /export function normalizeThemeMode\(|export const DEFAULT_THEME_MODE/);
  assert.match(modelSource, /export function normalizeAppearanceProfile\(|export const DEFAULT_APPEARANCE_PROFILE/);
  assert.match(modelSource, /export const THEME_OPTIONS = baseThemeOptions/);
  assert.match(modelSource, /export const APPEARANCE_PROFILE_OPTIONS = baseAppearanceProfileOptions/);
  assert.doesNotMatch(
    modelSource,
    /createContext|useState|useEffect|getCurrentWindow|setTheme as setNativeTheme/,
    'theme model should stay pure and not own React or native runtime wiring',
  );

  assert.match(runtimeSource, /export function getSystemTheme\(/);
  assert.match(runtimeSource, /export function applyTheme\(/);
  assert.match(runtimeSource, /export function applyNativeTheme\(/);
  assert.doesNotMatch(
    runtimeSource,
    /createContext|useState|export const THEME_OPTIONS =/,
    'theme runtime should own host bridges, not React context or option registries',
  );
});
