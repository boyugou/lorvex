import { forwardRef } from 'react';

type ButtonVariant = 'primary' | 'secondary' | 'ghost' | 'outline';
// `xs` — text-2xs px-2.5 py-1.5 rhythm for sub-row review actions
// (StalledListRow "Open list", DeferredTaskRow rescope) where a `sm` button
// would dominate the row. Pair with `variant='outline'` for the canonical
// quiet review-row affordance.
type ButtonSize = 'xs' | 'sm' | 'banner' | 'md' | 'lg' | 'monoChip' | 'icon' | 'icon-lg';

const FOCUS_RING_STRONG = 'focus-ring-strong';
// icon-only buttons are compact controls per the documented
// focus-ring policy (index.css `@verify-exempt: focus-ring-doc`):
// `focus-ring-soft` is for icon buttons / chips, `focus-ring-strong`
// reserves its surface-0 halo for prominent / primary actions. A
// 28×28 dismiss-X is the canonical "compact control" so the strong
// halo is overkill (and the white halo on surface-2 banner contexts
// reads as a paint glitch more than a focus ring).
const FOCUS_RING_SOFT = 'focus-ring-soft';

const BASE_NO_RING =
  'inline-flex items-center justify-center gap-1.5 font-medium select-none ' +
  'rounded-r-control ' +
  'transition-[color,background-color,border-color,box-shadow,transform] duration-150 ' +
  'active:scale-[0.97] disabled:opacity-50 disabled:cursor-not-allowed disabled:active:scale-100';

// `outline` is a self-contained recipe; it does not compose with
// BASE / SIZE because the call sites it migrated from were hand-rolled
// chip-style buttons with their own rhythm (text-xs px-2.5 py-1.5,
// focus-ring-soft, no shadow ladder). Keeping the recipe whole avoids a
// pile of override-classes per consumer.
const OUTLINE_RECIPE =
  'inline-flex items-center justify-center gap-1.5 font-medium select-none ' +
  'text-xs px-2.5 py-1.5 rounded-r-control ' +
  'border border-surface-3 text-text-secondary ' +
  'transition-[color,background-color,border-color,transform] duration-150 ' +
  'hover:bg-surface-2 active:scale-[0.97] ' +
  'disabled:opacity-50 disabled:cursor-not-allowed disabled:active:scale-100 ' +
  'focus-ring-soft';

const VARIANT: Record<ButtonVariant, string> = {
  primary:
    'bg-accent text-on-accent border border-transparent hover:bg-accent-hover shadow-[var(--shadow-tooltip)] hover:shadow-[var(--shadow-popover)]',
  secondary:
    'bg-surface-2/60 text-text-secondary border border-card hover:bg-surface-2 hover:text-text-primary',
  ghost:
    'bg-accent/10 text-accent border border-accent/40 hover:bg-accent/20',
  // Sentinel — the outline variant short-circuits BASE / SIZE composition
  // below and emits OUTLINE_RECIPE wholesale.
  outline: '',
};

// sizes split by recipe shape. Padding-based rungs go through
// PADDING_SIZE; fixed-square icon rungs go through ICON_SIZE. The
// render path consults the right map per size so the two categories
// stop sharing one untyped record where every entry was either pure
// padding *or* pure square — never a meaningful blend.
type PaddingSize = Exclude<ButtonSize, 'icon' | 'icon-lg'>;
type IconSize = Extract<ButtonSize, 'icon' | 'icon-lg'>;

const PADDING_SIZE: Record<PaddingSize, string> = {
  // review-row sub-action rhythm.
  xs: 'text-2xs px-2.5 py-1.5',
  sm: 'text-xs px-3 py-1',
  banner: 'text-xs px-2.5 py-1.5',
  md: 'text-sm px-4 py-1.5',
  lg: 'text-sm px-6 py-2.5 font-semibold',
  // see recipe doc above.
  monoChip:
    'min-w-[36px] min-h-[36px] gap-1 text-3xs font-mono leading-none text-text-muted px-2.5 py-1.5',
};

const ICON_SIZE: Record<IconSize, string> = {
  // square 28px target for stand-alone icon-only buttons
  // (banner dismiss-X, toolbar close affordances). The recipe overrides
  // the BASE flex defaults to enforce a fixed-square hit area instead of
  // letting padding drive the size; pairs naturally with `variant='ghost'`
  // for a quiet, transparent affordance.
  icon: 'h-7 w-7 inline-flex items-center justify-center',
  // 36×36 ghost icon-only target for pagination/navigation
  // affordances. Mirrors the `icon` recipe at a larger
  // rhythm so the affordances match the 36px header height without
  // bespoke className overrides.
  'icon-lg': 'h-9 w-9 inline-flex items-center justify-center',
};

function sizeClass(size: ButtonSize): string {
  return size === 'icon' || size === 'icon-lg' ? ICON_SIZE[size] : PADDING_SIZE[size];
}

// sizes whose typography is meant to override the outline
// variant's default `text-xs` sans-serif. The outline recipe is
// otherwise self-contained, but `monoChip` (font-mono) and `xs`
// (text-2xs) need their own typography to land. A `Set` reads as
// "membership predicate" rather than "binary boolean over two
// disjuncts", which scales if a future size joins the override list.
const OUTLINE_SIZE_OVERRIDES: ReadonlySet<ButtonSize> = new Set(['monoChip', 'xs']);

interface ButtonProps extends React.ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: ButtonVariant;
  size?: ButtonSize;
}

export const Button = forwardRef<HTMLButtonElement, ButtonProps>(function Button(
  { variant = 'secondary', size = 'md', className = '', type = 'button', children, ...rest },
  ref,
) {
  return (
    <button
      ref={ref}
      // Wrapper component forwards a defaulted `type` prop ('button'); the
      // rule wants a static string but the wrapper exists precisely so
      // every Button has a safe default while still allowing 'submit'.
      // eslint-disable-next-line react/button-has-type
      type={type}
      // opt-in marker for the ember/midnight theme form-control
      // radius/border treatment. Bare `<button>` elements (kanban cards,
      // calendar event chips, focus-mode pill buttons, etc.) opt out by
      // default; canonical Button primitives opt in.
      data-theme-form-control="true"
      className={
        variant === 'outline'
          ? // `outline` short-circuits BASE/SIZE composition (see
            // OUTLINE_RECIPE doc). The OUTLINE_SIZE_OVERRIDES set marks the
            // sizes whose typography is meant to override the outline
            // default (text-xs sans-serif); we append the matching recipe
            // after the base so Tailwind's last-wins semantics make the
            // override stick.
            `${OUTLINE_RECIPE}${OUTLINE_SIZE_OVERRIDES.has(size) ? ` ${sizeClass(size)}` : ''} ${className}`
          : `${BASE_NO_RING} ${size === 'icon' || size === 'icon-lg' ? FOCUS_RING_SOFT : FOCUS_RING_STRONG} ${VARIANT[variant]} ${sizeClass(size)} ${className}`
      }
      {...rest}
    >
      {children}
    </button>
  );
});
