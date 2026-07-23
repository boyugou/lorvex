// Public surface for the keyboard-shortcuts module.
//
// split out of `components/KeyboardShortcutsPanel.tsx`
// alongside the new help-menu and onboarding-checklist work so the
// shortcuts cheatsheet has a clear home ( uniform-edit /
// discoverability scope) and other surfaces (Help menu, Welcome view,
// onboarding checklist) can import it without referring to a top-level
// component file.
export { default as KeyboardShortcutsPanel } from './KeyboardShortcutsPanel';
