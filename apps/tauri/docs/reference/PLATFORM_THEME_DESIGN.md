# Platform Theme Design Reference

Design specifications for Lorvex's platform-native themes. Each theme must faithfully reproduce the visual language of its target platform.

---

## Windows 11 — Fluent Design / Mica (dark + light)

### Core Principles
- **Mica material**: Subtle desktop-wallpaper tint bleeds through the app background. Not blur — a gentle color pickup from the desktop.
- **Acrylic material**: Used for transient surfaces (flyouts, sidebars). Gaussian blur + noise texture + exclusion blend.
- **Layered elevation**: Cards/panels sit on layers differentiated by subtle fill changes, not shadows. Shadows are minimal (1-2px, very low opacity).
- **Rounded geometry**: 4px for small controls (checkbox, radio), 8px for cards/panels/buttons, 12px for flyouts/dialogs.

### Color Tokens (WinUI 3 / Windows 11)

#### Dark Mode
| Token | Value | Notes |
|-------|-------|-------|
| Layer Background | `#202020` | Mica base (app background) |
| Card Background | `#2D2D2D` | Elevated surface |
| Card Background Secondary | `#1F1F1F` | Nested/lower card |
| Smoke Fill | `#000000 30%` | Overlay backdrop |
| Stroke (Card) | `rgba(255,255,255,0.0837)` | Subtle divider |
| Stroke (Control) | `rgba(255,255,255,0.0698)` | Input/button border bottom |
| Stroke (Flyout) | `rgba(0,0,0,0.32)` | Dialog/popup border |
| Text Primary | `#FFFFFF` | Body text |
| Text Secondary | `rgba(255,255,255,0.786)` | Hint/muted text |
| Text Disabled | `rgba(255,255,255,0.3628)` | Disabled state |
| Accent Default | `#60CDFF` | Windows default accent (sky blue) |
| Accent Secondary | `rgba(96,205,255,0.9)` | Hover |
| Accent Tertiary | `rgba(96,205,255,0.8)` | Pressed |
| Subtle Fill | `rgba(255,255,255,0.0605)` | Hover background |
| Secondary Fill | `rgba(255,255,255,0.0837)` | Toggled/active background |

#### Light Mode
| Token | Value | Notes |
|-------|-------|-------|
| Layer Background | `#F3F3F3` | Mica base |
| Card Background | `#FFFFFF` | Elevated surface |
| Card Background Secondary | `#F6F6F6` | Nested/lower card |
| Stroke (Card) | `rgba(0,0,0,0.0578)` | Card border |
| Stroke (Control) | `rgba(0,0,0,0.0578)` | Control border |
| Stroke (Control Bottom) | `rgba(0,0,0,0.1622)` | Bottom edge emphasis |
| Text Primary | `rgba(0,0,0,0.8956)` | Near-black text |
| Text Secondary | `rgba(0,0,0,0.6063)` | Muted text |
| Accent Default | `#005FB8` | Windows accent blue (light) |
| Subtle Fill | `rgba(0,0,0,0.0373)` | Hover background |
| Secondary Fill | `rgba(0,0,0,0.0578)` | Active background |

### Typography
- **Font**: `Segoe UI Variable Display` for headings, `Segoe UI Variable Text` for body, `Segoe UI Variable Small` for caption
- **Sizes**: Caption 12px, Body 14px, Subtitle 20px, Title 28px
- **Weight**: Regular 400, SemiBold 600

### Component Patterns

#### Buttons
- **Filled (primary)**: bg=accent, text=black (dark) or white (light), radius 4px, no border, subtle bottom shadow `0 1px 0 rgba(0,0,0,0.15)`
- **Outline (secondary)**: bg=subtle-fill, border=control-stroke, radius 4px, bottom border slightly darker
- **Hover**: bg lightens/darkens one step
- **The "bottom-edge" border trick**: WinUI buttons have a slightly darker 1px bottom border for dimensionality

#### Inputs/Text Fields
- bg=control-fill (`rgba(255,255,255,0.0605)` dark / `rgba(255,255,255,1)` light)
- border=control-stroke, bottom border darker
- radius 4px
- Focus: 2px accent bottom border (not ring)
- Inner padding: 8px 12px

#### Navigation Sidebar (NavigationView)
- bg=layer background (Mica)
- Items: 36px height, 4px radius, full-width
- Active: pill-shaped accent background (`accent/12%`), 3px left accent indicator bar
- Icon + text, 16px icon, 14px text

#### Cards/Panels
- bg=card-background with 1px card-stroke border
- radius 8px
- Shadow: `0 2px 4px rgba(0,0,0,0.04)` (very subtle, dark mode only)
- No shadow in light mode — rely on border

#### Scrollbars (Windows 11 style)
- Thin rail (2px idle → 8px hover)
- Rounded thumb
- Dark: thumb `rgba(255,255,255,0.3)`, Light: thumb `rgba(0,0,0,0.3)`

---

## GNOME — Adwaita / libadwaita (dark + light)

### Core Principles
- **Flat with subtle depth**: Not truly flat — buttons have gentle gradients, inputs have inner shadows.
- **Uniform rounding**: 12px for windows/cards, 8px for controls/buttons, 6px for smaller items.
- **Header bar integration**: Title bar and toolbar are one unified header bar.
- **Strong visual hierarchy**: Clear distinction between sidebar, content, and elevated surfaces.
- **Row-based navigation**: Sidebar items are full-width rows with generous height.

### Color Tokens (Adwaita/libadwaita)

#### Dark Mode
| Token | Value | Notes |
|-------|-------|-------|
| Window Background | `#242424` | Main window bg |
| Header Bar | `#303030` | Title/toolbar bar |
| Card Background | `#383838` | Cards, elevated |
| Sidebar Background | `#2A2A2A` | Navigation sidebar |
| View Background | `#1E1E1E` | Content/list view |
| Borders | `rgba(255,255,255,0.12)` | General border |
| Text Primary | `#FFFFFF` | |
| Text Secondary | `rgba(255,255,255,0.7)` | |
| Text Disabled | `rgba(255,255,255,0.5)` | |
| Accent (Blue) | `#3584E4` | Default blue |
| Accent Hover | `#5DA2F0` | |
| Suggested Action | `#3584E4` | Primary button bg |
| Destructive | `#E5534B` | |
| Success | `#57E389` | |
| Warning | `#F8E45C` | |

#### Light Mode
| Token | Value | Notes |
|-------|-------|-------|
| Window Background | `#FAFAFA` | Main window bg |
| Header Bar | `#E8E8E8` → `#DCDCDC` gradient | Top-to-bottom |
| Card Background | `#FFFFFF` | Cards, elevated |
| Sidebar Background | `#EBEBEB` | Navigation sidebar |
| View Background | `#FFFFFF` | Content area |
| Borders | `rgba(0,0,0,0.15)` | |
| Text Primary | `rgba(0,0,0,0.8)` | Not pure black |
| Text Secondary | `rgba(0,0,0,0.55)` | |
| Accent (Blue) | `#1C71D8` | Slightly darker for contrast |
| Suggested Action | `#3584E4` | |

### Typography
- **Font**: System default — `Cantarell`, `Inter`, `Noto Sans`, or whatever GNOME is configured to use
- **Sizes**: Caption 10px, Body 14px, Heading 18px, Title 24px
- **Weight**: Regular 400, Bold 700 (Adwaita uses bold sparingly)

### Component Patterns

#### Buttons
- **Raised (default)**: Very subtle gradient (dark: `linear-gradient(to bottom, rgba(255,255,255,0.05), transparent)`, light: `linear-gradient(to bottom, rgba(255,255,255,0.8), rgba(255,255,255,0.4))`)
- border 1px solid rgba border
- radius 8px (6px for smaller)
- shadow: `0 1px 2px rgba(0,0,0,0.07)` (light), `0 1px 2px rgba(0,0,0,0.2)` (dark)
- **Suggested (primary)**: bg=accent, text=white, same gradient overlay
- **Flat**: No border, no bg, just text with hover fill
- Minimum height 34px, padding 8px 16px

#### Inputs (Entries)
- bg=view-background (dark: `#1E1E1E`, light: `#FFFFFF`)
- border 1px solid
- **Inset shadow**: `inset 0 1px 2px rgba(0,0,0,0.15)` — this is characteristic
- radius 8px
- Focus: 2px accent outline (not glow)
- Height 34px, padding 8px 12px

#### Sidebar Navigation
- bg=sidebar-background
- Items: 38px tall, 8px radius, 4px horizontal padding within sidebar
- Active: bg=accent, text=white (or subtle accent tint in newer versions)
- Hover: subtle background fill
- Separator lines between sections

#### Cards (AdwActionRow, AdwPreferencesGroup)
- bg=card-background
- border 1px solid border-color
- radius 12px
- Top border slightly lighter (inner highlight): `box-shadow: inset 0 1px 0 rgba(255,255,255,0.05)` (dark)
- Grouped rows within cards (like Settings groups)

#### Header Bar
- bg=gradient (light) or solid (dark)
- Bottom border 1px solid
- Integrates window controls, title, and toolbar items
- Not applicable to our sidebar app, but influences the top-bar feel

---

## macOS — Liquid Glass (dark + light)

### Core Principles
- **Glass is a material**: Translucent surfaces that reflect/refract underlying content. Applied sparingly to navigation-layer surfaces.
- **Never glass on glass**: Don't layer glass on glass — use a container for shared sampling.
- **Capsule shapes**: Default button/control shape is capsule (pill). Rounded rectangles for panels.
- **Container-concentric radii**: Inner radius = outer radius - padding (nested rounding).
- **Vibrant text**: Text on glass automatically gets brightness/saturation adjustment.
- **Deference to content**: UI recedes behind content; glass panels float above, content stays solid.

### Material Specifications (CSS approximation)

#### Glass Effect
```css
/* Standard glass panel */
backdrop-filter: blur(20px) saturate(180%);
background: rgba(255, 255, 255, 0.15); /* light */
background: rgba(20, 20, 20, 0.22); /* dark */
border: 1px solid rgba(255, 255, 255, 0.2);
box-shadow: 0 8px 32px rgba(0, 0, 0, 0.12);
```

#### Glass Intensity Presets
| Level | Blur | BG Opacity | Shadow | Radius |
|-------|------|-----------|--------|--------|
| Soft | 16px | 0.22 | `0 4px 20px rgba(0,0,0,0.12)` | 16px |
| Medium | 24px | 0.18 | `0 8px 32px rgba(0,0,0,0.15)` | 20px |
| Heavy | 32px | 0.14 | `0 12px 48px rgba(0,0,0,0.2)` | 24px |

### Color Tokens (macOS 26)

#### Dark Mode
| Token | Value | Notes |
|-------|-------|-------|
| Window Background | `#1E1E1E` or transparent (glass) | |
| Sidebar | Glass material, ~`rgba(30,30,32,0.72)` | Translucent |
| Content Background | `#1C1C1E` | Solid content area |
| Elevated Surface | `#2C2C2E` | Cards/panels |
| Grouped Background | `#2C2C2E` | Settings groups |
| Separator | `rgba(255,255,255,0.15)` | |
| Text Primary | `#FFFFFF` | |
| Text Secondary | `#8E8E93` (systemGray) | |
| Text Tertiary | `#48484A` (systemGray2) | |
| Accent (Blue) | `#0A84FF` | System blue |
| Tint on glass | Accent at 0.3 opacity | |

#### Light Mode
| Token | Value | Notes |
|-------|-------|-------|
| Window Background | `#FFFFFF` or glass | |
| Sidebar | Glass, ~`rgba(255,255,255,0.72)` | |
| Content Background | `#FFFFFF` | |
| Elevated Surface | `#F2F2F7` (systemGray6) | |
| Grouped Background | `#FFFFFF` on `#F2F2F7` | |
| Separator | `rgba(0,0,0,0.12)` | |
| Text Primary | `#000000` | |
| Text Secondary | `#8E8E93` | |
| Accent (Blue) | `#007AFF` | |

### Typography
- **Font**: `-apple-system`, SF Pro Text (body), SF Pro Display (headings)
- **Sizes**: Caption2 11px, Caption 12px, Body 13px, Title3 15px, Title2 17px, Title 20px, LargeTitle 26px
- **Weight**: Regular 400, Medium 500, Semibold 600

### Component Patterns

#### Buttons
- **Default capsule**: Fully rounded (999px radius), glass material background, vibrant text
- **Filled (primary)**: bg=accent, text=white, capsule shape
- **Bordered**: 1px border, glass bg, capsule
- **Plain**: Text only, no bg/border, accent color
- Minimum height: 28px (small), 34px (medium)
- Padding: 6px 14px

#### Sidebar Navigation (Source List)
- Glass material background (translucent)
- Items: 28px height, 6px radius
- Active: bg=`rgba(accent, 0.25)`, text=accent or primary
- Active indicator: 2px left bar in accent color (optional)
- Section headers: 11px uppercase, muted color

#### Text Fields
- bg=elevated surface or glass
- border: 1px solid separator
- radius: 8px (standard) or capsule (search fields)
- Focus: accent ring, 2px
- Height 28px, padding 4px 8px

#### Cards/Groups
- bg=grouped-background
- radius: 12px
- border: 1px solid separator
- No shadow (or very subtle: `0 1px 3px rgba(0,0,0,0.06)`)
- Inner rows separated by hairline borders

#### Scrollbars (macOS style)
- Overlay scrollbars (appear on scroll, fade on idle)
- Rounded thumb, 8px wide on hover, 6px idle
- Dark: `rgba(255,255,255,0.4)`, Light: `rgba(0,0,0,0.3)`

---

## Implementation Strategy

### CSS Custom Properties Per Theme
Each theme defines:
1. **Color tokens** via `--color-surface-*`, `--color-accent`, `--color-text-*`
2. **Structural tokens** via `--theme-radius-*`, `--theme-shadow-*`
3. **Material tokens** via `--theme-blur`, `--theme-bg-opacity`, `--theme-border-opacity`

### Theme-Specific Selectors
```css
:root[data-theme='mica'] { /* Dark Mica tokens */ }
:root[data-theme='mica_light'] { /* Light Mica tokens */ }
:root[data-theme='adwaita'] { /* Dark Adwaita tokens */ }
:root[data-theme='adwaita_light'] { /* Light Adwaita tokens */ }
:root[data-theme='liquid'] { /* Dark Liquid Glass tokens */ }
:root[data-theme='liquid_light'] { /* Light Liquid Glass tokens */ }
```

### Component Override Targets
1. Buttons: `:root[data-theme='xxx'] button:not([class*='rounded-full'])`
2. Inputs: `:root[data-theme='xxx'] input, textarea, select`
3. Cards: `.desktop-card`, `.rounded-xl`, `.rounded-2xl`
4. Sidebar: `.profile-material-shell`, `.liquid-sidebar-shell`
5. Panels: `.profile-material-panel`, `.liquid-settings-panel`
6. Nav items: sidebar `NavItem` via `data-active` attribute
7. Scrollbars: `::-webkit-scrollbar-thumb`
