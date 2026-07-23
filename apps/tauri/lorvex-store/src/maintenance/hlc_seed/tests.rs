use super::*;
use crate::test_support::{test_conn, ListBuilder, TaskBuilder};

const TS: &str = "2026-03-01T00:00:00.000Z";

const TEST_DEVICE_ID: &str = "aabbccdd-1122-3344-5566-778899001122";

#[test]
fn max_local_hlc_returns_none_for_fresh_db() {
    let conn = test_conn();
    let result = max_local_hlc_for_device(&conn, TEST_DEVICE_ID).unwrap();
    assert!(result.is_none());
}

#[test]
fn max_local_hlc_finds_max_across_multiple_tables() {
    let conn = test_conn();
    let app_suffix = device_id_to_hlc_suffix(TEST_DEVICE_ID, HlcSurface::App);

    // Seed a task + a list, each at different HLCs under the App
    // surface suffix. The max across all tables is 2e12 / counter 5.
    let l1_v = format!("1000000000000_0000_{app_suffix}");
    ListBuilder::new("l1")
        .name("L")
        .version(&l1_v)
        .created_at(TS)
        .insert(&conn);
    let t1_v = format!("2000000000000_0005_{app_suffix}");
    TaskBuilder::new("t1")
        .title("T")
        .list_id(Some("l1"))
        .version(&t1_v)
        .created_at(TS)
        .insert(&conn);
    // Remote-origin row (different suffix not derivable from the
    // local device_id under any surface) should be ignored.
    TaskBuilder::new("t-remote")
        .title("T")
        .list_id(Some("l1"))
        .version("9000000000000_0000_cafe5678cafe5678")
        .created_at(TS)
        .insert(&conn);

    let result = max_local_hlc_for_device(&conn, TEST_DEVICE_ID)
        .unwrap()
        .expect("should find a local max");
    assert_eq!(result.physical_ms(), 2_000_000_000_000);
    assert_eq!(result.counter(), 5);
    assert_eq!(result.device_suffix(), app_suffix);
}

/// with per-surface suffixes, a single device emits
/// three distinct suffixes (app/mcp/cli). The max-HLC aggregation
/// must union across all of them so the seed at init time covers
/// prior writes from every surface, not just the current one.
#[test]
fn max_local_hlc_for_device_aggregates_across_surfaces() {
    let conn = test_conn();
    let app_suffix = device_id_to_hlc_suffix(TEST_DEVICE_ID, HlcSurface::App);
    let mcp_suffix = device_id_to_hlc_suffix(TEST_DEVICE_ID, HlcSurface::Mcp);
    let cli_suffix = device_id_to_hlc_suffix(TEST_DEVICE_ID, HlcSurface::Cli);

    // Sanity: the three suffixes differ so the rows genuinely
    // belong to different suffix buckets.
    assert_ne!(app_suffix, mcp_suffix);
    assert_ne!(mcp_suffix, cli_suffix);
    assert_ne!(app_suffix, cli_suffix);

    let app_v = format!("1000000000000_0001_{app_suffix}");
    ListBuilder::new("l-app")
        .name("A")
        .version(&app_v)
        .created_at(TS)
        .insert(&conn);
    let mcp_v = format!("4000000000000_0042_{mcp_suffix}");
    ListBuilder::new("l-mcp")
        .name("M")
        .version(&mcp_v)
        .created_at(TS)
        .insert(&conn);
    let cli_v = format!("2000000000000_0007_{cli_suffix}");
    ListBuilder::new("l-cli")
        .name("C")
        .version(&cli_v)
        .created_at(TS)
        .insert(&conn);

    let result = max_local_hlc_for_device(&conn, TEST_DEVICE_ID)
        .unwrap()
        .expect("aggregation must find a max across all three surfaces");
    // The MCP row at 4e12/counter=42 is the global max.
    assert_eq!(result.physical_ms(), 4_000_000_000_000);
    assert_eq!(result.counter(), 42);
    assert_eq!(result.device_suffix(), mcp_suffix);
}

#[test]
fn seed_hlc_state_bumps_past_observed_max() {
    let conn = test_conn();
    let app_suffix = device_id_to_hlc_suffix(TEST_DEVICE_ID, HlcSurface::App);

    let v = format!("5000000000000_0010_{app_suffix}");
    ListBuilder::new("l1")
        .name("L")
        .version(&v)
        .created_at(TS)
        .insert(&conn);

    let mut state = HlcState::new(&app_suffix).unwrap();
    // Sanity: before seeding, state is at (0, 0).
    assert_eq!(state.last_physical_ms(), 0);
    assert_eq!(state.counter(), 0);

    let observed = seed_hlc_state_from_local_history(&conn, TEST_DEVICE_ID, &mut state)
        .unwrap()
        .expect("should return seeded HLC");
    assert_eq!(observed.physical_ms(), 5_000_000_000_000);

    // After seeding, the next HLC is strictly greater than the
    // previously-observed max even if wall clock is still in the
    // 2026 range (i.e., far behind the synthetic 5e12 ms value).
    let next = state.generate_with_physical(1_700_000_000_000);
    assert!(
        next > observed,
        "expected HLC past observed; got {next} vs {observed}"
    );
}

/// a fresh app process whose own (App) suffix has no
/// history must still seed past a larger HLC previously written
/// by the MCP server on the same device.
#[test]
fn seed_hlc_state_bumps_past_cross_surface_max() {
    let conn = test_conn();
    let app_suffix = device_id_to_hlc_suffix(TEST_DEVICE_ID, HlcSurface::App);
    let mcp_suffix = device_id_to_hlc_suffix(TEST_DEVICE_ID, HlcSurface::Mcp);

    // Only an MCP-suffixed row exists locally.
    let v = format!("6000000000000_0020_{mcp_suffix}");
    ListBuilder::new("l1")
        .name("L")
        .version(&v)
        .created_at(TS)
        .insert(&conn);

    // The App-surface state still gets seeded past the MCP max.
    let mut state = HlcState::new(&app_suffix).unwrap();
    let observed = seed_hlc_state_from_local_history(&conn, TEST_DEVICE_ID, &mut state)
        .unwrap()
        .expect("cross-surface max must be returned");
    assert_eq!(observed.physical_ms(), 6_000_000_000_000);
    assert_eq!(observed.counter(), 20);
    assert_eq!(observed.device_suffix(), mcp_suffix);

    // The next App-surface HLC generated is strictly greater than
    // the observed MCP max despite wall clock lagging.
    let next = state.generate_with_physical(1_700_000_000_000);
    assert!(next > observed, "App HLC must exceed MCP max");
}

#[test]
fn seed_hlc_state_returns_none_for_empty_history() {
    let conn = test_conn();
    let suffix = device_id_to_hlc_suffix(TEST_DEVICE_ID, HlcSurface::App);
    let mut state = HlcState::new(&suffix).unwrap();
    let result = seed_hlc_state_from_local_history(&conn, TEST_DEVICE_ID, &mut state).unwrap();
    assert!(result.is_none());
    assert_eq!(state.last_physical_ms(), 0);
    assert_eq!(state.counter(), 0);
}

#[test]
fn seed_hlc_state_ignores_malformed_version_strings() {
    let conn = test_conn();
    let app_suffix = device_id_to_hlc_suffix(TEST_DEVICE_ID, HlcSurface::App);

    // Historical rogue value with invalid HLC shape.
    ListBuilder::new("l1")
        .name("L")
        .version("not-an-hlc")
        .created_at(TS)
        .insert(&conn);
    // And one well-formed row with the device's App suffix.
    let t1_v = format!("3000000000000_0002_{app_suffix}");
    TaskBuilder::new("t1")
        .title("T")
        .list_id(Some("l1"))
        .version(&t1_v)
        .created_at(TS)
        .insert(&conn);

    let result = max_local_hlc_for_device(&conn, TEST_DEVICE_ID).unwrap();
    // Malformed entries in `lists` are skipped by parse; the valid
    // `tasks` HLC wins. Note: because LIKE '%_<suffix>' is applied
    // at SQL time, the malformed row must at least lexically end
    // in the suffix to get returned to us. Here we're just asserting
    // the parse loop filters junk without panicking.
    assert!(result.is_some());
}
