use crate::hlc::*;

/// the three surface tags mixed into the suffix
/// derivation must be distinct and stable. Changing these values
/// would invalidate every persisted HLC's collision isolation, so
/// pin them here as a regression guard.
#[test]
fn hlc_surface_tags_are_distinct_and_stable() {
    assert_eq!(HlcSurface::App.as_str(), "app");
    assert_eq!(HlcSurface::Mcp.as_str(), "mcp");
    assert_eq!(HlcSurface::Cli.as_str(), "cli");
    let tags = HlcSurface::all();
    assert_eq!(tags.len(), 3);
    // All distinct.
    assert_ne!(tags[0].as_str(), tags[1].as_str());
    assert_ne!(tags[1].as_str(), tags[2].as_str());
    assert_ne!(tags[0].as_str(), tags[2].as_str());
}
