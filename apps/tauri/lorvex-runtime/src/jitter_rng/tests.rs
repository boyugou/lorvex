use super::JitterRng;
use std::collections::HashSet;

#[test]
fn from_seed_is_deterministic() {
    let mut a = JitterRng::from_seed(0xDEAD_BEEF_CAFE_F00D);
    let mut b = JitterRng::from_seed(0xDEAD_BEEF_CAFE_F00D);
    for _ in 0..64 {
        assert_eq!(
            a.next_u64(),
            b.next_u64(),
            "identical seeds must produce identical streams"
        );
    }
}

#[test]
fn from_seed_zero_does_not_wedge_at_zero() {
    // xorshift64* on a zero state returns zero forever. The
    // constructor must remap a zero seed to something non-zero so
    // that never happens.
    let mut rng = JitterRng::from_seed(0);
    let mut saw_nonzero = false;
    for _ in 0..16 {
        if rng.next_u64() != 0 {
            saw_nonzero = true;
            break;
        }
    }
    assert!(saw_nonzero, "zero seed must not wedge the stream at zero");
}

#[test]
fn next_u64_never_returns_same_value_twice_from_distinct_seeds() {
    // Not quite what the name suggests: we check that distinct
    // seeds diverge on the very first output, which is what
    // matters for cross-device decorrelation. A bad seeder that
    // collapsed several seeds to the same internal state would
    // fail this.
    let seeds: [u64; 8] = [
        1,
        2,
        3,
        0x5A5A_5A5A_5A5A_5A5A,
        0xA5A5_A5A5_A5A5_A5A5,
        0x1234_5678_9ABC_DEF0,
        0xFEDC_BA98_7654_3210,
        u64::MAX,
    ];
    let mut firsts = HashSet::new();
    for seed in seeds {
        let mut rng = JitterRng::from_seed(seed);
        let first = rng.next_u64();
        assert!(
            firsts.insert(first),
            "seed {seed:#x} produced a first value that collided with another seed"
        );
    }
}

#[test]
fn jitter_ms_respects_upper_bound() {
    let mut rng = JitterRng::from_seed(0xFEED_FACE_C0DE_BABE);
    for _ in 0..10_000 {
        let v = rng.jitter_ms(1_000);
        assert!(v < 1_000, "jitter_ms(1_000) returned {v}, outside [0,1000)");
    }
}

#[test]
fn jitter_ms_with_zero_max_returns_zero() {
    let mut rng = JitterRng::from_seed(42);
    for _ in 0..16 {
        assert_eq!(rng.jitter_ms(0), 0);
    }
}

#[test]
fn from_entropy_produces_distinct_streams_across_multiple_constructions() {
    // Construct a batch back-to-back. The seeder mixes wall-clock
    // nanos with the pid, so sequentially constructed instances
    // must still diverge on their very first output. This is the
    // property that keeps a single process from hammering the
    // same retry pattern on every reconnect cycle.
    let mut firsts = HashSet::new();
    for _ in 0..32 {
        let mut rng = JitterRng::from_entropy();
        firsts.insert(rng.next_u64());
    }
    assert!(
        firsts.len() >= 30,
        "expected near-unique first outputs across 32 constructions, got {} distinct",
        firsts.len()
    );
}
