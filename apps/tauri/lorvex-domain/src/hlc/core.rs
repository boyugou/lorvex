//! `Hlc` value type — physical_ms + counter + device_suffix triple,
//! with construction (`new`) and parse (`parse`) entry points and the
//! `physical_ms` ceiling / fixture-version constants.

use super::parse_error::{validate_device_suffix, HlcParseError};

/// Maximum accepted `physical_ms` value (tightened in
/// #2962 H1). `9_999_999_999_999` is the largest **13-digit** integer
/// the canonical `Display` format (`{:013}_..."`) zero-pads without
/// inflating to 14 digits — anything above it would render as 14 chars
/// and lex above every legitimate 13-digit HLC forever, breaking the
/// `(physical_ms, counter, device_suffix)` lex order LWW relies on.
/// Corresponds to ~Nov 20, year 2286. A peer with a broken clock
/// (future-dated NTP, mis-set local time) could otherwise emit
/// `physical_ms` values that poison LWW cluster-wide and propagate via
/// peer apply without a manual reset on every device.
pub const MAX_HLC_PHYSICAL_MS: u64 = 9_999_999_999_999;

/// Maximum accepted in-millisecond counter value. The canonical HLC
/// wire format reserves four decimal digits for the counter segment
/// (`0000` through `9999`); larger counters widen the segment and
/// break raw string ordering.
pub const MAX_COUNTER: u32 = 9999;

/// Canonical seed version for test fixtures.
///
/// every test that hand-INSERTs a row with a literal
/// `version` column **must** use this constant (or an explicit HLC of
/// equivalent shape). The format `{13-digit-ms}_{4-digit-ctr}_{suffix}`
/// is lex-sortable, so a leading zero timestamp sorts strictly below
/// every realistic HLC produced at runtime — which means LWW gates
/// (`WHERE excluded.version > version`) never reject the test's
/// downstream mutations.
///
/// The opposite — letter-prefixed literals like `'v1'`, `'test_ver'`,
/// `'seed-v1'` — sort lex-greater than digit-prefixed HLCs (`'v' > '1'`
/// in raw byte order), so any LWW guard added to the path under test
/// silently no-ops the test mutation. The assertion then fails with a
/// confusing "row never updated" message rather than the actual root
/// cause. Use this constant. The compile-time gate
/// [`assert_test_version_safe`] (called from within tests via
/// `const _: () = assert_test_version_safe(MY_FIXTURE_VERSION);`)
/// rejects any fixture string that doesn't begin with an ASCII digit.
pub const TEST_VERSION: &str = "0000000000000_0000_a0a0a0a0a0a0a0a0";

/// Compile-time assertion that a test-fixture version string is
/// LWW-safe — i.e., starts with an ASCII digit so it sorts below
/// every realistic HLC.
///
/// Use as `const _: () = assert_test_version_safe("0000…");` in
/// test modules that define their own per-test version literals
/// (e.g., to encode an ordering relation between fixture rows).
///
/// # Panics
///
/// At compile time if `version` is empty or starts with a non-digit
/// byte. The panic message is the only feedback Rust offers for a
/// `const` panic, so it's intentionally short and points to this
/// constant for context.
pub const fn assert_test_version_safe(version: &str) {
    let bytes = version.as_bytes();
    assert!(
        !bytes.is_empty(),
        "test fixture version is empty (see lorvex_domain::hlc::TEST_VERSION)"
    );
    assert!(
        bytes[0].is_ascii_digit(),
        "test fixture version must start with an ASCII digit so LWW gates do not reject \
         test mutations (see lorvex_domain::hlc::TEST_VERSION)"
    );
}

/// A Hybrid Logical Clock value.
///
/// Implements `Ord` with lexicographic ordering by `(physical_ms, counter,
/// device_suffix)`, which matches the string-sort order of the canonical
/// display format.
///
/// Fields are private. The only construction
/// paths are [`Hlc::new`] and [`Hlc::parse`], both of which validate
/// the canonical 13-digit physical, 4-digit counter, and 16-char
/// lowercase-hex device suffix invariants. Read-only accessors
/// ([`physical_ms`](Hlc::physical_ms) / [`counter`](Hlc::counter) /
/// [`device_suffix`](Hlc::device_suffix)) expose the parts to callers
/// that need them.
/// caller write `hlc.device_suffix = "ZZ".into()` and bypass the
/// canonical-form invariants the parser maintains — `Ord` only
/// `debug_assert!`s the length, so a mutated suffix would silently
/// corrupt LWW ordering in release builds.
#[derive(Debug, Clone, Eq, PartialEq)]
pub struct Hlc {
    pub(super) physical_ms: u64,
    pub(super) counter: u32,
    pub(super) device_suffix: String,
}

impl Hlc {
    /// Create a new HLC value.
    ///
    /// the device_suffix is lowercased at construction
    /// time. ASCII 'A' (0x41) sorts BEFORE 'a' (0x61) lexicographically,
    /// so a mixed-case cluster (one device emits `AAAA1234`, another
    /// `aaaa1234`) produces a stable but unintended LWW tie-break. If
    /// a single device ever emits both cases — e.g. DB restored from
    /// a capitalized backup and then continues writing lowercase —
    /// causal order within that device is broken. Normalize at the
    /// type boundary so every HLC in circulation is canonically
    /// lowercase regardless of caller.
    ///
    /// # Examples
    ///
    /// ```
    /// use lorvex_domain::hlc::Hlc;
    /// let hlc = Hlc::new(1_711_060_000_000, 42, "ABCDEF0123456789").unwrap();
    /// assert_eq!(hlc.physical_ms(), 1_711_060_000_000);
    /// assert_eq!(hlc.counter(), 42);
    /// // Mixed-case input is canonicalized to lowercase at the boundary.
    /// assert_eq!(hlc.device_suffix(), "abcdef0123456789");
    ///
    /// // a non-conforming suffix is rejected with a typed error.
    /// assert!(Hlc::new(0, 0, "short").is_err());
    /// assert!(Hlc::new(0, 0, "not-hex-but16chrs").is_err());
    /// ```
    ///
    /// Rejects suffixes that don't match
    /// [`HLC_DEVICE_SUFFIX_HEX_LEN`](super::HLC_DEVICE_SUFFIX_HEX_LEN) (16) characters of lowercase
    /// ASCII hex. Accepting any non-empty string would let a fixture
    /// or peer with an 8-char or letter-bearing suffix poison the
    /// type's "always canonical 16-hex" invariant — every downstream
    /// LWW comparison would silently mix two suffix shapes.
    ///
    /// Also rejects `physical_ms > MAX_HLC_PHYSICAL_MS` at
    /// construction time. `Hlc::new(u64::MAX, ...)` would otherwise
    /// produce a 14+ digit physical segment that lex-sorts above
    /// every legitimate 13-digit HLC forever, poisoning LWW cluster-
    /// wide. This matches the ceiling `Hlc::parse` has always
    /// enforced; every in-memory `Hlc` value renders in the canonical
    /// `{:013}` width regardless of how it was constructed, so no
    /// defense-in-depth clamp is required in the apply pipeline.
    pub fn new(
        physical_ms: u64,
        counter: u32,
        device_suffix: impl Into<String>,
    ) -> Result<Self, HlcParseError> {
        if physical_ms > MAX_HLC_PHYSICAL_MS {
            return Err(HlcParseError::PhysicalMsOutOfRange(physical_ms));
        }
        if counter > MAX_COUNTER {
            return Err(HlcParseError::CounterOutOfRange(counter));
        }
        let suffix = device_suffix.into().to_ascii_lowercase();
        validate_device_suffix(&suffix)?;
        Ok(Self {
            physical_ms,
            counter,
            device_suffix: suffix,
        })
    }

    /// The physical-clock component (ms since Unix epoch). Valid
    /// values fit in 13 decimal digits per the canonical display
    /// width; values up to [`MAX_HLC_PHYSICAL_MS`] are accepted by
    /// the constructor.
    #[inline]
    pub const fn physical_ms(&self) -> u64 {
        self.physical_ms
    }

    /// The monotonic counter component, break ties when two
    /// events fall in the same physical millisecond.
    #[inline]
    pub const fn counter(&self) -> u32 {
        self.counter
    }

    /// The 16-char lowercase-hex device suffix that disambiguates
    /// concurrent events from different devices.
    #[inline]
    pub fn device_suffix(&self) -> &str {
        &self.device_suffix
    }

    /// Parse an HLC from its canonical string format
    /// `{physical_ms}_{counter}_{device_suffix}`.
    ///
    /// # Examples
    ///
    /// ```
    /// use lorvex_domain::hlc::Hlc;
    /// let hlc = Hlc::parse("0001711060000_0042_abcdef0123456789").unwrap();
    /// assert_eq!(hlc.physical_ms(), 1_711_060_000);
    /// assert_eq!(hlc.counter(), 42);
    /// assert_eq!(hlc.device_suffix(), "abcdef0123456789");
    ///
    /// // Mixed-case suffix is normalized so peers with case drift
    /// // still compare equal under the same logical clock.
    /// let upper = Hlc::parse("0001711060000_0042_ABCDEF0123456789").unwrap();
    /// assert_eq!(upper, hlc);
    ///
    /// // Malformed inputs error rather than silently accepting.
    /// assert!(Hlc::parse("not-an-hlc").is_err());
    /// assert!(Hlc::parse("0001711060000__abcdef0123456789").is_err());
    /// assert!(Hlc::parse("0001711060000_0042_").is_err());
    /// ```
    ///
    /// # Round-trip note
    ///
    /// `parse` is strictly more permissive than `Display`: an un-padded
    /// `physical_ms` or `counter` segment (e.g. `"1711234567890_7_..."`
    /// in place of the canonical `"1711234567890_0007_..."`) parses to
    /// the same logical [`Hlc`], but [`Display`] always emits the
    /// canonical zero-padded form. The two forms compare equal under
    /// `PartialEq` (it compares numeric fields, not bytes), so logical
    /// equality is preserved across a parse-then-format cycle. SQL
    /// comparisons that compare HLCs as raw strings (e.g. the lex
    /// `version < watermark` predicate in `gc_tombstones_watermark`)
    /// rely on the canonical width — any persistence path that may
    /// have ingested an un-padded envelope from an older client must
    /// round-trip through `Hlc` (`Hlc::parse(...).to_string()`) before
    /// storing so the on-disk shape is always the canonical form.
    pub fn parse(s: &str) -> Result<Self, HlcParseError> {
        // Walk the segments via `splitn` directly instead of collecting
        // into a `Vec<&str>` — every parse on the apply hot path used
        // to allocate a 3-cap heap vec just to index into it three
        // times.
        let mut iter = s.splitn(3, '_');
        let phys_str = iter.next();
        let ctr_str = iter.next();
        let suffix = iter.next();
        let (Some(phys_str), Some(ctr_str), Some(suffix)) = (phys_str, ctr_str, suffix) else {
            return Err(HlcParseError::InvalidFormat(s.to_string()));
        };

        let physical_ms = phys_str
            .parse::<u64>()
            .map_err(|_| HlcParseError::InvalidPhysicalMs(phys_str.to_string()))?;
        if physical_ms > MAX_HLC_PHYSICAL_MS {
            return Err(HlcParseError::PhysicalMsOutOfRange(physical_ms));
        }

        let counter = ctr_str
            .parse::<u32>()
            .map_err(|_| HlcParseError::InvalidCounter(ctr_str.to_string()))?;
        if counter > MAX_COUNTER {
            return Err(HlcParseError::CounterOutOfRange(counter));
        }

        // Enforce the 16-char lowercase-hex shape on every parse. A
        // bare `.is_empty()` check would let a peer envelope with `_x`
        // or `_zzzzzz` slip through and produce an `Hlc` value that
        // violated the type's documented invariant.
        // `validate_device_suffix` runs against the lowercased form so
        // case-only differences continue to round-trip. Skip the
        // lowercase allocation on the canonical happy path
        // (post-#3060 every Hlc::to_string output is lowercase, and
        // every peer envelope written by current code goes through
        // that path) — uppercase letters only show up on legacy /
        // hand-written / malicious input.
        let normalized_suffix = if suffix.bytes().any(|b| b.is_ascii_uppercase()) {
            suffix.to_ascii_lowercase()
        } else {
            suffix.to_string()
        };
        validate_device_suffix(&normalized_suffix)?;

        Ok(Self {
            physical_ms,
            counter,
            // normalize to lowercase — same rationale as
            // `Hlc::new`. A peer that sends `_AAAA1234` must compare
            // equal to a local `_aaaa1234` if the hex payload is the
            // same.
            device_suffix: normalized_suffix,
        })
    }
}
