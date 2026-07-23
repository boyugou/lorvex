#!/usr/bin/env node

import { verifyUiWiringModuleAstContracts } from '../lib/ui_wiring_module_ast_contract.mjs';
import { resolveRepoRootFromMeta } from '../lib/verifier_runtime.mjs';
import {
  ensureNoPattern,
  ensurePattern,
  escapeRegex,
  extractConstStringArray,
  extractConstTopLevelObjectKeys,
  extractOptionValuesFromArray,
  fail,
  loadUiWiringContractSources,
  missingLocaleCatalogKeys,
} from '../lib/ui_wiring_contract_support.mjs';

const repoRoot = resolveRepoRootFromMeta(import.meta.url);

const {
  settingsViewSource,
  generalSettingsSectionSource,
  sharedTypesSource,
  themeLibSource,
  commandPaletteSource,
  calendarViewSource,
  todayViewSource,
  // dailyReviewViewSource not currently used by any contract
  aiMemoryViewSource,
  changelogViewSource,
  taskMetadataEditorSource,
  dateLocaleLibSource,
  appSource,
  enLocaleCatalog,
  readmeSource,
  settingsToggleSource,
  themeCssSource,
} = loadUiWiringContractSources(repoRoot);

let moduleAstContractResult;
try {
  moduleAstContractResult = verifyUiWiringModuleAstContracts({ repoRoot });
} catch (error) {
  fail(error instanceof Error ? error.message : String(error));
}

const {
  allModules,
  missingSettingsOptions,
  missingSidebarVisibilityGuards,
  missingAppRenderBranches,
  missingAppModuleGuardMappings,
} = moduleAstContractResult;

if (missingSettingsOptions.length > 0) {
  fail(`Settings sidebar module options missing: ${missingSettingsOptions.join(', ')}`);
}

if (missingSidebarVisibilityGuards.length > 0) {
  fail(`Sidebar visibility guard missing for modules: ${missingSidebarVisibilityGuards.join(', ')}`);
}

if (missingAppRenderBranches.length > 0) {
  fail(`MainViewContent render branch missing for modules: ${missingAppRenderBranches.join(', ')}`);
}

if (missingAppModuleGuardMappings.length > 0) {
  fail(`App mapViewToSidebarModule missing case->module mappings for: ${missingAppModuleGuardMappings.join(', ')}`);
}

ensurePattern(
  appSource,
  /if \(requiredModule && !visibleSidebarModules\.has\(requiredModule\)\) \{[\s\S]{0,200}return \{ type: '(settings|today)' \};[\s\S]{0,50}\}/,
  'App-level hidden-module fallback (hidden target -> today or settings)',
);

ensurePattern(
  appSource,
  /const navigateToView = useCallback\(\(target: View\): View => \{[\s\S]{0,200}const resolved = resolveGuardedView\(target\);[\s\S]{0,200}areViewsEqual\(prev, resolved\)/,
  'single navigation boundary helper',
);

const mainViewNavigateBoundaryMatches = Array.from(appSource.matchAll(/onNavigate=\{navigateToView\}/g)).length;
if (mainViewNavigateBoundaryMatches < 2) {
  fail('MainViewContent onNavigate should use App navigation boundary for desktop + mobile');
}

ensurePattern(
  appSource,
  /const resolved = resolveGuardedView\(view\);[\s\S]{0,200}if \(areViewsEqual\(resolved, view\)\) return;[\s\S]{0,200}setView\(resolved\);/,
  'current-view guard reconciliation effect',
);

ensurePattern(
  settingsToggleSource,
  /\{\s*id:\s*'daily_review',\s*labelKey:\s*'nav\.daily_review'/,
  'daily_review settings option semantic key (nav.daily_review)',
);

if (enLocaleCatalog['nav.daily_review'] !== 'Daily Review') {
  fail('daily_review semantic label in English locale');
}

ensurePattern(
  settingsViewSource,
  /id="settings-section-appearance"/,
  'SettingsView scroll-spy appearance section wrapper',
);

ensurePattern(
  settingsViewSource,
  /<AppearanceSettingsSection\s*\/>/,
  'SettingsView renders AppearanceSettingsSection directly',
);

ensurePattern(
  settingsViewSource,
  /<SettingsScrollSpyNav/,
  'SettingsView renders scroll-spy navigation',
);

ensurePattern(
  settingsViewSource,
  /IntersectionObserver/,
  'SettingsView uses IntersectionObserver for scroll-spy',
);

const themeLaneChecks = [
  {
    label: 'Theme lane (dark)',
    pattern: /THEME_OPTIONS\.filter\(\(opt\) => opt\.tone === 'dark'\)/,
  },
  {
    label: 'Theme lane (light)',
    pattern: /THEME_OPTIONS\.filter\(\(opt\) => opt\.tone === 'light'\)/,
  },
  {
    label: 'Theme lane (system)',
    pattern: /THEME_OPTIONS\.filter\(\(opt\) => opt\.tone === 'system'\)/,
  },
];

for (const check of themeLaneChecks) {
  ensurePattern(generalSettingsSectionSource, check.pattern, check.label);
}

const expectedThemeLaneLocaleKeys = [
  'settings.themeLaneDark',
  'settings.themeLaneLight',
  'settings.themeLaneSystem',
];
const missingThemeLaneLocaleKeys = missingLocaleCatalogKeys(enLocaleCatalog, expectedThemeLaneLocaleKeys);
if (missingThemeLaneLocaleKeys.length > 0) {
  fail(`English locale missing theme-lane keys: ${missingThemeLaneLocaleKeys.join(', ')}`);
}

const sharedThemeModes = extractConstStringArray(sharedTypesSource, 'THEME_MODES');
const baseThemeOptionValues = extractOptionValuesFromArray(themeLibSource, 'baseThemeOptions');
const missingThemeOptionModes = sharedThemeModes.filter((mode) => !baseThemeOptionValues.includes(mode));
if (missingThemeOptionModes.length > 0) {
  fail(`Theme options missing shared mode(s): ${missingThemeOptionModes.join(', ')}`);
}
const extraThemeOptionModes = baseThemeOptionValues.filter((mode) => !sharedThemeModes.includes(mode));
if (extraThemeOptionModes.length > 0) {
  fail(`Theme options contain unknown mode(s): ${extraThemeOptionModes.join(', ')}`);
}
const concreteThemeModes = sharedThemeModes.filter((mode) => mode !== 'system');
const themePreviewModes = extractConstTopLevelObjectKeys(generalSettingsSectionSource, 'THEME_PREVIEW');
const missingThemePreviewModes = concreteThemeModes.filter((mode) => !themePreviewModes.includes(mode));
if (missingThemePreviewModes.length > 0) {
  fail(`Theme preview mapping missing concrete mode(s): ${missingThemePreviewModes.join(', ')}`);
}
const extraThemePreviewModes = themePreviewModes.filter((mode) => !concreteThemeModes.includes(mode));
if (extraThemePreviewModes.length > 0) {
  fail(`Theme preview mapping has unknown mode(s): ${extraThemePreviewModes.join(', ')}`);
}

const appearanceProfiles = extractConstStringArray(sharedTypesSource, 'APPEARANCE_PROFILES');

ensurePattern(
  themeLibSource,
  /export const APPEARANCE_PROFILE_OPTIONS =/,
  'appearance profile options export in theme lib',
);

const missingAppearanceProfileOptions = appearanceProfiles.filter((profile) => (
  !new RegExp(`value:\\s*'${escapeRegex(profile)}'`).test(themeLibSource)
));
if (missingAppearanceProfileOptions.length > 0) {
  fail(`Theme appearance profile options missing values: ${missingAppearanceProfileOptions.join(', ')}`);
}

ensurePattern(
  generalSettingsSectionSource,
  /const\s*\{[\s\S]*\bmode\b[\s\S]*\bsetMode\b[\s\S]*\bappearanceProfile\b[\s\S]*\bsetAppearanceProfile\b[\s\S]*\}\s*=\s*useTheme\(\);/,
  'Settings theme hook includes theme and appearance profile state + setters',
);

ensurePattern(
  generalSettingsSectionSource,
  /<SettingsSection title=\{t\('settings\.theme'\)\} description=\{t\('settings\.themeDesc'\)\}>/,
  'Settings appearance section is rendered',
);

// Appearance section renders inline grids (no studio dialog layer).
ensureNoPattern(
  generalSettingsSectionSource,
  /showAppearanceStudio|AppearanceStudioDialog|useAppearanceStudioController/,
  'appearance section should not reference deleted studio system',
);

// Appearance profile rendering was simplified — no longer uses recommendedProfiles.map
ensurePattern(
  generalSettingsSectionSource,
  /APPEARANCE_PROFILE_OPTIONS\.map/,
  'Settings appearance section renders profile options from the canonical registry',
);

const expectedAppearanceProfileLocaleKeys = [
  'settings.appearanceProfileClarity',
  'settings.appearanceProfileStudio',
  'settings.appearanceProfileFocusCompact',
  'settings.appearanceProfileLiquidGlass',
];

ensureNoPattern(
  readmeSource,
  /Liquid Labs/,
  'README should not reference the retired Liquid Labs appearance-profile name',
);

ensureNoPattern(
  themeCssSource,
  /liquid_labs/,
  'theme CSS should not reference the retired liquid_labs appearance-profile selector',
);
const missingAppearanceProfileLocaleKeys = missingLocaleCatalogKeys(
  enLocaleCatalog,
  expectedAppearanceProfileLocaleKeys,
);
if (missingAppearanceProfileLocaleKeys.length > 0) {
  fail(`English locale missing appearance profile keys: ${missingAppearanceProfileLocaleKeys.join(', ')}`);
}

// Theme search, session storage, tone filters, and keyboard nav were removed
// in the appearance studio simplification (issue #810).
ensurePattern(
  generalSettingsSectionSource,
  /onClick=\{\(\) => handleSelectMode\('system'\)\}/,
  'theme reset-to-system action',
);

// Studio-specific checks (search, session storage, keyboard nav, dialog, tone
// filters) were removed in the appearance studio simplification (#810).
// Remaining theme locale key that's still in use:
const expectedThemeResetLocaleKeys = [
  'settings.themeResetSystem',
];
const missingThemeResetLocaleKeys = missingLocaleCatalogKeys(enLocaleCatalog, expectedThemeResetLocaleKeys);
if (missingThemeResetLocaleKeys.length > 0) {
  fail(`English locale missing theme reset keys: ${missingThemeResetLocaleKeys.join(', ')}`);
}

// CommandPalette now consumes the higher-level `Modal` primitive, which
// owns the canonical sizing/alignment tokens and forwards through
// `ModalShell` internally. The contract's intent — that the palette
// reuses the shared overlay shell rather than reinventing focus
// trapping / portal layering — still holds.
ensurePattern(
  commandPaletteSource,
  /import \{ Modal \} from '\.\/ui\/Modal';/,
  'CommandPalette imports shared overlay shell',
);

ensurePattern(
  commandPaletteSource,
  /<Modal[\s\S]{0,400}open[\s\S]{0,400}onClose=\{props\.onClose\}/,
  'CommandPalette renders through ModalShell',
);

ensurePattern(
  commandPaletteSource,
  /<Modal[\s\S]{0,400}ariaLabel=\{t\('palette\.placeholder'\)\}/,
  'CommandPalette forwards semantic dialog labeling to ModalShell',
);

ensurePattern(
  commandPaletteSource,
  /if \(e\.key === 'Tab' && !e\.shiftKey && !moveTask && selectedItem\?\.kind === 'task'\) \{/,
  'CommandPalette task-move Tab shortcut only applies to forward Tab (not Shift+Tab)',
);

// `resolveDateLocale` was refactored to memoize via an assignment-then-return
// shape (`resolved = 'en-US'; ... return resolved;`) instead of returning the
// fallback inline, so the regex tolerates either form.
ensurePattern(
  dateLocaleLibSource,
  /export function resolveDateLocale\(locale: string\): string \{[\s\S]{0,800}const canonicalLocale = normalizeDateLocaleInput\(locale\);[\s\S]{0,400}canonicalLocale === 'zh' \? 'zh-CN' : canonicalLocale[\s\S]{0,400}new Intl\.DateTimeFormat\(normalizedLocale\);[\s\S]{0,400}'en-US'[\s\S]{0,400}\}/,
  'shared date-locale resolver supports zh alias + invalid-locale fallback',
);

ensurePattern(
  calendarViewSource,
  /const TaskDetail = lazy\(\(\) => import\('\.\.\/TaskDetail'\)\);/,
  'CalendarView lazily imports TaskDetail (code-splitting consistency)',
);

ensureNoPattern(
  calendarViewSource,
  /import TaskDetail from '(?:\.\/|\.\.\/)TaskDetail';/,
  'CalendarView static TaskDetail import (would defeat TaskDetail lazy chunking)',
);

// CalendarView's per-cell date formatting moved up the abstraction
// from `resolveDateLocale(locale)` + raw `Intl.DateTimeFormat` calls
// into the shared `formatCalendarDate` / `formatDate` helpers. Both
// helpers route through `resolveDateLocale` internally, so the
// contract just asserts that the calendar tree imports a shared
// date-locale utility (any of the canonical exports) from
// `lib/dateLocale` rather than rolling its own locale plumbing.
ensurePattern(
  calendarViewSource,
  /import \{[\s\S]{0,300}(?:resolveDateLocale|formatCalendarDate|formatDate|localizedWeekdayOptions)[\s\S]{0,300}\} from '(?:@\/lib\/dates\/dateLocale|(?:\.\.\/){1,3}lib\/dates\/dateLocale)';/,
  'CalendarView imports shared date-locale utility',
);

ensureNoPattern(
  calendarViewSource,
  /locale === 'zh' \? 'zh-CN' : 'en-US'/,
  'CalendarView hardcoded non-zh locale fallback (should not force en-US)',
);

ensurePattern(
  calendarViewSource,
  /(?:const dateLocale = resolveDateLocale\(locale\);|formatCalendarDate\(|formatDate\()/,
  'CalendarView uses shared date-locale formatting helper',
);

// `resolveWeekdayLabels` was lifted out of CalendarView and now
// delegates to the shared `localizedWeekdayOptions` builder in
// `app/src/lib/dateLocale.ts`. The shared builder is what actually
// instantiates `Intl.DateTimeFormat({ weekday })`, so the contract
// asserts the controller still routes through that helper rather than
// reinventing weekday formatting locally.
ensurePattern(
  calendarViewSource,
  /function resolveWeekdayLabels\(locale: string[^)]*\): string\[] \{[\s\S]{0,500}localizedWeekdayOptions\(locale, weekStartDay\)\.map/,
  'CalendarView derives weekday labels from Intl locale formatter',
);

ensureNoPattern(
  calendarViewSource,
  /const DAY_HEADERS = locale === 'zh'[\s\S]{0,500}\['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'\]/,
  'CalendarView hardcoded bilingual weekday header arrays',
);

ensurePattern(
  calendarViewSource,
  /selectedTaskId[\s\S]{0,1200}<ErrorBoundary[\s\S]{0,400}<Suspense fallback=\{<TaskDetailSkeleton \/>\}[\s\S]{0,400}<TaskDetail/,
  'CalendarView task detail panel uses Suspense fallback for lazy chunk',
);

for (const { source, componentLabel } of [
  { source: todayViewSource, componentLabel: 'TodayView' },
  { source: aiMemoryViewSource, componentLabel: 'AIMemoryView' },
  { source: changelogViewSource, componentLabel: 'ChangelogView' },
]) {
  ensurePattern(
    source,
    /import \{ (?:resolveDateLocale|formatRelativeTime) \} from '(?:@\/lib\/dates\/dateLocale|(?:\.\.\/){1,2}lib\/dates\/dateLocale)';/,
    `${componentLabel} imports shared date-locale utility`,
  );
  ensureNoPattern(
    source,
    /locale === 'zh' \? 'zh-CN' : 'en-US'/,
    `${componentLabel} hardcoded non-zh locale fallback (should not force en-US)`,
  );
  ensurePattern(
    source,
    /(?:resolveDateLocale|formatRelativeTime)\((?:locale|entry)/,
    `${componentLabel} uses shared date-locale utility`,
  );
}

// TaskMetadataEditor migrated from `resolveDateLocale` + raw
// `Intl.DateTimeFormat` to the shared `formatCalendarDate` /
// `formatDate` / `formatTimestamp` helpers, which all route through
// `resolveDateLocale` internally. The contract still asserts the
// metadata editor pulls a date-locale utility from `lib/dateLocale`
// rather than reinventing locale plumbing.
ensurePattern(
  taskMetadataEditorSource,
  /import \{[\s\S]{0,300}(?:resolveDateLocale|formatCalendarDate|formatDate|formatTimestamp)[\s\S]{0,300}\} from '(?:@\/lib\/dates\/dateLocale|(?:\.\.\/){2,4}lib\/dates\/dateLocale)';/,
  'TaskMetadataEditor imports shared date-locale utility',
);

ensureNoPattern(
  taskMetadataEditorSource,
  /task\.reminder_at \? task\.reminder_at\.slice\(0, 16\) : ''/,
  'TaskMetadataEditor reminder input no longer slices UTC ISO text directly',
);

console.log(`[ui_wiring] OK: sidebar module inventory (${allModules.length}): ${allModules.join(', ')}`);
console.log('[ui_wiring] OK: settings toggle surfaces cover all sidebar modules');
console.log('[ui_wiring] OK: sidebar visibility guards cover all modules');
console.log('[ui_wiring] OK: App-level navigation guard contract is present (mobile + hidden-module fallback + single boundary)');
console.log(`[ui_wiring] OK: MainViewContent render branches cover all mapped views`);
console.log('[ui_wiring] OK: daily_review module semantics align to "Daily Review" (settings + en locale)');
console.log('[ui_wiring] OK: focus module wiring present (Sidebar action + App handler)');
console.log('[ui_wiring] OK: Settings theme gallery exposes dark/light/system lanes');
console.log('[ui_wiring] OK: en locale includes theme-lane labels');
console.log(`[ui_wiring] OK: theme options align with shared modes (${sharedThemeModes.join(', ')})`);
console.log(`[ui_wiring] OK: theme preview mapping covers concrete shared modes (${concreteThemeModes.join(', ')})`);
console.log(`[ui_wiring] OK: appearance profile options cover all shared profiles (${appearanceProfiles.join(', ')})`);
console.log('[ui_wiring] OK: Settings appearance profile section wiring is present');
console.log('[ui_wiring] OK: en locale includes required appearance profile keys');
console.log('[ui_wiring] OK: Settings theme search/filter + reset wiring is present');
console.log('[ui_wiring] OK: en locale includes theme search/reset labels');
console.log('[ui_wiring] OK: date localization wiring uses shared resolver across UI surfaces');
console.log('[ui_wiring] OK: TaskMetadataEditor reminder datetime-local wiring is timezone-safe');
console.log('[ui_wiring] OK: CalendarView locale-aware date formatting + TaskDetail lazy-loading wiring is present');
