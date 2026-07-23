use lorvex_domain::hlc::{Hlc, HlcSurface};
use lorvex_runtime::SurfaceHlcRuntime;

fn seed_device(runtime: &SurfaceHlcRuntime, device_id: &str, surface: HlcSurface) {
    runtime
        .ensure_initialized(device_id.to_string(), surface, |_state| Ok::<_, String>(()))
        .expect("initialize shared HLC runtime");
}

#[test]
fn shared_runtime_generates_monotonic_surface_versions() {
    let runtime = SurfaceHlcRuntime::new();
    seed_device(
        &runtime,
        "01900000-1111-7222-8333-444455556666",
        HlcSurface::Mcp,
    );

    let a = runtime.generate_version().expect("first version");
    let b = runtime.generate_version().expect("second version");
    let c = runtime.generate_version().expect("third version");

    assert!(a < b, "first < second: {a} < {b}");
    assert!(b < c, "second < third: {b} < {c}");
}

#[test]
fn shared_runtime_seeds_past_local_history_before_first_generate() {
    let runtime = SurfaceHlcRuntime::new();
    let prior = Hlc::new(9_999_999_999_900, 42, "ffffffffffffffff").expect("canonical test HLC");

    runtime
        .ensure_initialized(
            "01900000-1111-7222-8333-444455556666".to_string(),
            HlcSurface::Cli,
            |state| {
                state.update_on_receive(&prior, 0);
                Ok::<_, String>(())
            },
        )
        .expect("initialize with seed");

    let generated = runtime.generate_hlc().expect("generate after seed");
    assert!(
        generated > prior,
        "generated HLC {generated} must be greater than seeded prior {prior}"
    );
}

#[test]
fn shared_runtime_observes_remote_versions_and_ignores_malformed_input() {
    let runtime = SurfaceHlcRuntime::new();
    seed_device(
        &runtime,
        "01900000-1111-7222-8333-444455556666",
        HlcSurface::App,
    );
    let remote = "9999999999999_0050_de0070e100000001";

    runtime
        .observe_remote_version_str(remote, |_version, _error| {})
        .expect("valid remote observation");
    runtime
        .observe_remote_version_str("not-a-valid-hlc", |_version, _error| {})
        .expect("malformed remote is ignored");

    let generated = runtime.generate_hlc().expect("generate after remote");
    let remote_hlc = Hlc::parse(remote).expect("remote parses");
    assert!(
        generated > remote_hlc,
        "generated HLC {generated} must exceed observed remote {remote_hlc}"
    );
}

#[test]
fn shared_runtime_reset_allows_tests_to_swap_device_suffixes() {
    let runtime = SurfaceHlcRuntime::new();
    seed_device(
        &runtime,
        "01900000-1111-7222-8333-444455556666",
        HlcSurface::Cli,
    );
    let first = runtime.generate_version().expect("first device version");

    runtime.reset_for_tests();
    seed_device(
        &runtime,
        "01900000-aaaa-bbbb-cccc-ddddeeeeffff",
        HlcSurface::Cli,
    );
    let second = runtime.generate_version().expect("second device version");

    assert_ne!(
        &first[first.len() - 16..],
        &second[second.len() - 16..],
        "reset must allow a subsequent initialization to use a different device suffix"
    );
}
