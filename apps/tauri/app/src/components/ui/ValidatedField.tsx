/**
 * a11y: previously, zero forms used `aria-invalid` or
 * `aria-errormessage`. Validation state was communicated only via
 * red-border CSS + a conditional helper paragraph, which screen
 * readers silently ignore.
 *
 * `ValidatedField` threads a single generated id through three
 * coupled attributes:
 *
 *   1. `id` — ties `<label htmlFor>` to the input.
 *   2. `aria-invalid={Boolean(error)}` — exposed to assistive tech.
 *   3. `aria-errormessage="<id>-error"` — points at the error
 *      paragraph, which is also marked `role="alert"` so NVDA/JAWS
 *      fire an announcement the moment it mounts.
 *
 * The render-prop API (`children(props)`) lets callers thread the
 * attributes onto whichever element they need — a plain `<input>`, a
 * `<select>`, a custom `<AppSelect>`, a textarea, or (for field
 * layouts without a real `<input>`) a non-input element that still
 * needs the id/labelling wiring. It also avoids forcing every caller
 * to restructure their layout; the component supplies the label +
 * error paragraph but doesn't impose a specific input wrapper.
 *
 * The red-border CSS lives at the input level and selects on
 * `[aria-invalid=true]`. That way visual state cannot drift from
 * ARIA state: if `aria-invalid` toggles on, so does the border.
 */
import * as React from 'react';

interface ValidatedFieldRenderProps {
  /** Stable id to attach to the input/select. */
  id: string;
  /** Id of the error paragraph (for `aria-errormessage`). */
  errorMessageId: string;
  /** `true` when `error` is a non-empty string. */
  ariaInvalid: boolean;
  /**
   * Spread onto the input — handles id/ARIA wiring AND injects the
   * `validated-input` class that picks up the shared aria-invalid
   * border + ember/midnight theme treatment. Consumers must merge
   * their own `className` with `fieldProps.className` (via template
   * literal or `cn()`) — putting bare `className=` AFTER the spread
   * silently drops the validated-input hook.
   */
  fieldProps: {
    id: string;
    'aria-invalid': boolean;
    'aria-errormessage'?: string;
    className: string;
  };
}

interface ValidatedFieldProps {
  /** Optional external id. Generated via `useId()` when omitted. */
  id?: string;
  /**
   * Visible label. Rendered as a `<label>` when `showLabel` is true
   * (default). When `showLabel` is false, the label string is exposed
   * as `aria-label` on the child via the render prop's `fieldProps`
   * — set `aria-label={label}` on the input yourself in that case.
   */
  label: string;
  /** Current validation error, or null/undefined when valid. */
  error?: string | null;
  /** Descriptive hint shown only when there is no error. */
  hint?: string | null;
  /** When false, the label is not rendered as a `<label>`. */
  showLabel?: boolean;
  /** Extra classes for the outer wrapper. */
  className?: string;
  /** Extra classes for the `<label>` element. */
  labelClassName?: string;
  /** Extra classes for the error `<p>` element. */
  errorClassName?: string;
  /** Extra classes for the hint `<p>` element. */
  hintClassName?: string;
  children: (props: ValidatedFieldRenderProps) => React.ReactNode;
}

export function ValidatedField({
  id: providedId,
  label,
  error,
  hint,
  showLabel = true,
  className,
  labelClassName,
  errorClassName,
  hintClassName,
  children,
}: ValidatedFieldProps) {
  // `useId` is a hook; it must run unconditionally. Prefer the
  // externally-supplied id when the caller has one (e.g. integrates
  // with a form library that owns the id).
  const generatedId = React.useId();
  const id = providedId ?? generatedId;
  const errorMessageId = `${id}-error`;
  const ariaInvalid = Boolean(error);

  const renderProps: ValidatedFieldRenderProps = {
    id,
    errorMessageId,
    ariaInvalid,
    fieldProps: {
      id,
      'aria-invalid': ariaInvalid,
      // Only emit `aria-errormessage` when we actually have an error
      // to point at. An errormessage attribute pointing at a hidden
      // node is a common a11y footgun — some screen readers still
      // read it even when the node is display:none.
      ...(ariaInvalid ? { 'aria-errormessage': errorMessageId } : {}),
      // `validated-input` is the shared hook the aria-invalid border
      // CSS + ember/midnight theme treatment select on. Auto-injected
      // here so callers cannot forget it. Consumers compose
      // their own className: `className={`${fieldProps.className} ...`}`.
      className: 'validated-input',
    },
  };

  return (
    <div className={className ?? 'space-y-1'}>
      {showLabel ? (
        <label
          htmlFor={id}
          className={labelClassName ?? 'text-xs font-medium text-text-secondary'}
        >
          {label}
        </label>
      ) : null}
      {children(renderProps)}
      {error ? (
        <p
          id={errorMessageId}
          role="alert"
          className={errorClassName ?? 'text-xs text-danger'}
        >
          {error}
        </p>
      ) : hint ? (
        <p className={hintClassName ?? 'text-xs text-text-muted'}>{hint}</p>
      ) : null}
    </div>
  );
}
