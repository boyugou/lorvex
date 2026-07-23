# Apple Surface Wireframes

As-built ASCII wireframes of the Apple app's surfaces, transcribed from the
SwiftUI source. Each file diagrams a surface's layout, inventories the regions
with the `file:line` that renders each and the data each shows, lists the
as-built interactions, and notes improvement candidates (clearly marked as not
yet implemented). They document the current design and give a spatial frame for
reasoning about changes without a running device — the method described in
`../UX_POLISH_LOG.md`.

These are working analysis artifacts (my-app-only, no external references). When
a surface's layout changes materially, update its wireframe in the same change.

## Surfaces

| Surface | Idiom | File |
|---|---|---|
| macOS shell | sidebar + workspace split; task detail in an on-demand inspector | [`macos-shell.md`](macos-shell.md) |
| macOS Calendar week grid | time grid (hour gutter × day columns) | [`macos-calendar-week-grid.md`](macos-calendar-week-grid.md) |
| iPhone tab shell + Today | compact tab bar + push navigation | [`ios-tab-shell.md`](ios-tab-shell.md) |

## Not yet captured

These surfaces still need a wireframe; add them here as they are worked
(macOS Tasks list/table, macOS Task detail, macOS Focus, macOS Eisenhower +
Dependencies, iPad split / adaptive list-detail, mobile Calendar day/week,
mobile Task detail, watchOS, CarPlay, Widgets, visionOS).
