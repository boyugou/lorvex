import assert from 'node:assert/strict';
import test from 'node:test';
import { createElement } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';

import { ValidatedField } from '../../../app/src/components/ui/ValidatedField';

// these tests lock in the a11y contract of
// `ValidatedField`. The visible UI plumbing (labels, borders, focus
// rings) is exercised by real-browser QA elsewhere; here we pin down
// exactly the ARIA wiring that was missing across every form in the
// app before the fix:
//
//   1. when an error is set, the input is `aria-invalid="true"`
//   2. when an error is set, `aria-errormessage` on the input points
//      at an element with the matching `id`
//   3. that matching element carries `role="alert"`
//   4. when no error is set, `aria-invalid="false"` and there is no
//      `aria-errormessage` attribute at all
//
// We render a representative `<input>` child via the render prop so
// the test exercises the same surface every production caller uses.

function renderFieldHtml(opts: {
  label: string;
  error?: string | null;
  hint?: string | null;
}): string {
  return renderToStaticMarkup(
    createElement(ValidatedField, {
      label: opts.label,
      error: opts.error ?? null,
      hint: opts.hint ?? null,
      children: ({ fieldProps }: { fieldProps: Record<string, unknown> }) =>
        createElement('input', {
          ...(fieldProps as Record<string, unknown>),
          type: 'text',
          'aria-label': opts.label,
          defaultValue: '',
        }),
    }),
  );
}

/** Parse the first `<input>` tag's attribute map from rendered HTML. */
function extractInputAttrs(html: string): Map<string, string> {
  const match = html.match(/<input\s+([^/>]*)\/?>/);
  if (!match) throw new Error(`no <input> in HTML: ${html}`);
  const body = match[1];
  if (body == null) throw new Error('no attrs captured');
  const attrs = new Map<string, string>();
  const attrRe = /([a-zA-Z0-9_:@-]+)="([^"]*)"/g;
  let m: RegExpExecArray | null;
  while ((m = attrRe.exec(body)) !== null) {
    const key = m[1];
    const value = m[2];
    if (key != null && value != null) {
      attrs.set(key, value);
    }
  }
  return attrs;
}

test('renders_error_with_aria_errormessage_id_matching_input', () => {
  const html = renderFieldHtml({ label: 'URL', error: 'URL must start with https://' });
  const attrs = extractInputAttrs(html);

  const inputId = attrs.get('id');
  assert.ok(inputId, 'input should have a stable id');

  const errorMessageId = attrs.get('aria-errormessage');
  assert.ok(errorMessageId, 'aria-errormessage should be set when error is present');

  // The referenced element must exist in the rendered output with the
  // exact id. If the id were mismatched (a classic a11y bug) screen
  // readers would announce "invalid" with no explanation.
  assert.match(
    html,
    new RegExp(`id="${errorMessageId}"[^>]*role="alert"`),
    'the aria-errormessage id should refer to a role="alert" element',
  );

  // The conventional suffix keeps the id predictable for designers
  // inspecting the DOM.
  assert.equal(errorMessageId, `${inputId}-error`);
});

test('aria_invalid_true_when_error_present', () => {
  const html = renderFieldHtml({ label: 'Minutes', error: 'Must be between 1 and 1440' });
  const attrs = extractInputAttrs(html);
  assert.equal(attrs.get('aria-invalid'), 'true');
});

test('aria_invalid_false_when_error_absent', () => {
  const html = renderFieldHtml({ label: 'Minutes' });
  const attrs = extractInputAttrs(html);
  assert.equal(attrs.get('aria-invalid'), 'false');
  // When valid, the errormessage attribute MUST NOT be emitted — an
  // attribute pointing at a missing or hidden node is a known
  // screen-reader footgun. See ValidatedField.tsx.
  assert.equal(attrs.has('aria-errormessage'), false);
});

test('error_message_has_role_alert', () => {
  const html = renderFieldHtml({ label: 'URL', error: 'URL is required' });
  assert.match(
    html,
    /role="alert"/,
    'the error paragraph must have role="alert" so NVDA/JAWS announce on mount',
  );
  assert.match(html, />URL is required</);
});

test('empty_string_error_is_treated_as_valid', () => {
  // An empty error string is falsy; the component should treat it as
  // "no error" rather than flipping into invalid state with an empty
  // announcement. Production callers often pass `validator() || null`
  // and occasionally emit ''.
  const html = renderFieldHtml({ label: 'Minutes', error: '' });
  const attrs = extractInputAttrs(html);
  assert.equal(attrs.get('aria-invalid'), 'false');
  assert.equal(attrs.has('aria-errormessage'), false);
  assert.doesNotMatch(html, /role="alert"/);
});

test('hint_renders_only_when_no_error_is_present', () => {
  const hintHtml = renderFieldHtml({ label: 'URL', hint: 'Paste a public .ics URL.' });
  assert.match(hintHtml, /Paste a public \.ics URL\./);
  assert.doesNotMatch(hintHtml, /role="alert"/);

  const errorHtml = renderFieldHtml({
    label: 'URL',
    hint: 'Paste a public .ics URL.',
    error: 'URL is required',
  });
  // When both are supplied, the error wins — hint should not render
  // alongside, otherwise screen readers hear both and the user can't
  // tell which is the active validation message.
  assert.doesNotMatch(errorHtml, /Paste a public \.ics URL\./);
  assert.match(errorHtml, /role="alert"/);
});

test('field_props_spread_onto_button_surface_aria_invalid', () => {
  // the calendar event-form's date picker uses a
  // `<button>` trigger rather than an `<input>`. ValidatedField must
  // still forward aria-invalid + aria-errormessage when the caller
  // spreads `fieldProps` onto a non-input element — otherwise the
  // red-border CSS rule fires while screen readers stay silent.
  const html = renderToStaticMarkup(
    createElement(ValidatedField, {
      label: 'Start date',
      error: 'Pick a start date before saving',
      children: ({ fieldProps }: { fieldProps: Record<string, unknown> }) =>
        createElement(
          'button',
          {
            ...(fieldProps as Record<string, unknown>),
            type: 'button',
            'aria-label': 'Start date',
          },
          '—',
        ),
    }),
  );

  const buttonMatch = html.match(/<button\s+([^>]*)>/);
  assert.ok(buttonMatch, 'expected a <button> in rendered HTML');
  const attrs = buttonMatch[1] ?? '';
  assert.match(attrs, /aria-invalid="true"/);
  assert.match(attrs, /aria-errormessage="[^"]+"/);
  assert.match(html, /role="alert"/);
});
