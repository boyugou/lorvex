import path from 'node:path';

export const COMMON_PLACEHOLDERS = ['{{DATE}}', '{{EVIDENCE_TARGET}}', '{{EVIDENCE_TARGET_SLUG}}', '{{COMMIT}}'];
export const MANUAL_GATE_FRESHNESS_DAYS = 14;
export const MANUAL_GATE_OUTPUT_DIR_ENV = 'LORVEX_MANUAL_GATE_OUTPUT_DIR';
export const MANUAL_GATE_OUTPUT_DIR = 'artifacts/manual-gates';

export function manualGateOutputDirFromEnv(env = process.env) {
  const configured = env[MANUAL_GATE_OUTPUT_DIR_ENV]?.trim();
  return configured || MANUAL_GATE_OUTPUT_DIR;
}

export function resolveManualGateOutputRoot(repoRoot, env = process.env) {
  const configured = manualGateOutputDirFromEnv(env);
  if (path.isAbsolute(configured)) {
    return configured;
  }
  return path.join(repoRoot, ...configured.split('/'));
}

export const TEMPLATE_SPECS = {
  base: {
    outputSlug: 'manual-gate-template',
    templatePath: 'docs/execution/templates/manual-gate-base.md.tmpl',
    requiredHeadings: [
      '## Metadata',
      '## Gate Outcome',
      '## Checklist Coverage',
      '## Deviations',
      '## Follow-up',
    ],
  },
  'mcp-e2e': {
    outputSlug: 'mcp-e2e',
    templatePath: 'docs/execution/templates/manual-gate-mcp-e2e.md.tmpl',
    requiredHeadings: [
      '## Evidence Metadata',
      '## Evidence Freshness',
      '## Overall Outcome',
      '## Workflow Matrix',
      '## Failure-Handling Coverage',
      '## Artifacts',
      '## Issue Comment Draft',
    ],
  },
  'ui-regression': {
    outputSlug: 'ui-regression',
    templatePath: 'docs/execution/templates/manual-gate-ui-regression.md.tmpl',
    requiredHeadings: [
      '## Evidence Metadata',
      '## Evidence Freshness',
      '## Overall Outcome',
      '## Menu Bar Checklist Summary',
      '## Settings Checklist Summary',
      '## Defects and Follow-up',
      '## Issue Comment Draft',
    ],
  },
  'sync-recovery': {
    outputSlug: 'sync-recovery',
    templatePath: 'docs/execution/templates/manual-gate-sync-recovery.md.tmpl',
    requiredHeadings: [
      '## Evidence Metadata',
      '## Evidence Freshness',
      '## Overall Outcome',
      '## Fast Triage Snapshot',
      '## Failure Mode Coverage',
      '## Post-Recovery Verification',
      '## Issue Comment Draft',
    ],
  },
};

export const EXPECTED_DOC_REFERENCES = [
  {
    docPath: 'docs/execution/MCP_E2E_VALIDATION.md',
    requiredSnippets: [
      'docs/execution/templates/manual-gate-mcp-e2e.md.tmpl',
      'npm run docs:manual-gate:report -- --template mcp-e2e --date YYYY-MM-DD --issue <current-issue> --commit <git-sha>',
      '--pr <current-pr>',
      '--release-target <release-target>',
      'artifacts/manual-gates/',
      'Evidence permalink',
      'npm run verify:manual-gate-templates',
      'npm run verify:manual-gate-evidence',
    ],
  },
  {
    docPath: 'docs/execution/MENUBAR_REGRESSION_CHECKLIST.md',
    requiredSnippets: [
      'docs/execution/templates/manual-gate-ui-regression.md.tmpl',
      'npm run docs:manual-gate:report -- --template ui-regression --date YYYY-MM-DD --issue <current-issue> --commit <git-sha>',
      '--pr <current-pr>',
      '--release-target <release-target>',
      'artifacts/manual-gates/',
      'Evidence permalink',
      'npm run verify:manual-gate-evidence',
    ],
  },
  {
    docPath: 'docs/execution/SETTINGS_REGRESSION_CHECKLIST.md',
    requiredSnippets: [
      'docs/execution/templates/manual-gate-ui-regression.md.tmpl',
      'npm run docs:manual-gate:report -- --template ui-regression --date YYYY-MM-DD --issue <current-issue> --commit <git-sha>',
      '--pr <current-pr>',
      '--release-target <release-target>',
      'artifacts/manual-gates/',
      'Evidence permalink',
      'npm run verify:manual-gate-evidence',
    ],
  },
  {
    docPath: 'docs/execution/SYNC_RECOVERY_PLAYBOOK.md',
    requiredSnippets: [
      'docs/execution/templates/manual-gate-sync-recovery.md.tmpl',
      'npm run docs:manual-gate:report -- --template sync-recovery --date YYYY-MM-DD --issue <current-issue> --commit <git-sha>',
      '--pr <current-pr>',
      '--release-target <release-target>',
      'artifacts/manual-gates/',
      'Evidence permalink',
      'npm run verify:manual-gate-evidence',
    ],
  },
];
