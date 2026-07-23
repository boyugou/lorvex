//! emit the absolute path of the canonical schema SQL
//! that lives in the sibling `lorvex-store` crate, so the runtime
//! fixture-vs-production parity test can `include_str!` it via the
//! generated `LORVEX_STORE_SCHEMA_SQL_PATH` env var.
//!
//! Pre-fix the test hard-coded a relative path
//! (`../../lorvex-store/src/schema/001_schema.sql`). That path silently
//! resolved correctly from the current monorepo layout but would
//! produce a confusing "file not found at compile time" if either
//! crate moved. Computing the path at build time keeps the test
//! resilient to layout changes — if the schema file disappears the
//! `cargo:rerun-if-changed=` directive still triggers a rebuild and
//! the include_str! site emits a clear error pointing at the missing
//! source rather than at a stale string literal.

use std::path::PathBuf;

fn main() {
    // The runtime crate lives at `<repo>/lorvex-runtime`. The store's
    // canonical schema lives at `<repo>/lorvex-store/src/schema/`.
    // Walk up one directory from `CARGO_MANIFEST_DIR` and join the
    // expected sub-path; emit the resolved absolute path so the test
    // can `include_str!(env!("LORVEX_STORE_SCHEMA_SQL_PATH"))`.
    let manifest_dir =
        std::env::var("CARGO_MANIFEST_DIR").expect("CARGO_MANIFEST_DIR is always set by cargo");
    let mut path = PathBuf::from(manifest_dir);
    path.pop(); // drop `lorvex-runtime`
    path.push("lorvex-store");
    path.push("src");
    path.push("schema");
    path.push("001_schema.sql");

    // Fail the build loudly when the schema file is missing; the sibling
    // crate may have moved or someone deleted the parity source. The
    // include_str! site below would otherwise produce a confusing
    // "file not found" pointing at the env var rather than the actual
    // problem.
    assert!(
        path.is_file(),
        "lorvex-runtime build.rs: expected production schema at {} \
         — adjust this build script if `lorvex-store` moved.",
        path.display()
    );

    println!("cargo:rerun-if-changed={}", path.display());
    println!("cargo:rerun-if-changed=build.rs");
    println!(
        "cargo:rustc-env=LORVEX_STORE_SCHEMA_SQL_PATH={}",
        path.display()
    );
}
