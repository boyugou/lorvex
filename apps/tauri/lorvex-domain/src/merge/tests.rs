use super::*;

// -----------------------------------------------------------------------
// resolve_lww
// -----------------------------------------------------------------------

#[test]
fn lww_remote_wins_when_strictly_newer() {
    let local = Hlc::new(1000, 0, "10ca100100000001").unwrap();
    let remote = Hlc::new(2000, 0, "de0070e100000001").unwrap();
    assert_eq!(resolve_lww(&local, &remote), MergeOutcome::RemoteWins);
}

#[test]
fn lww_local_wins_when_strictly_newer() {
    let local = Hlc::new(3000, 0, "10ca100100000001").unwrap();
    let remote = Hlc::new(1000, 0, "de0070e100000001").unwrap();
    assert_eq!(resolve_lww(&local, &remote), MergeOutcome::LocalWins);
}

#[test]
fn lww_local_wins_on_equal_versions() {
    let local = Hlc::new(1000, 5, "aabbccddaabbccdd").unwrap();
    let remote = Hlc::new(1000, 5, "aabbccddaabbccdd").unwrap();
    assert_eq!(resolve_lww(&local, &remote), MergeOutcome::LocalWins);
}

#[test]
fn lww_remote_wins_by_counter() {
    let local = Hlc::new(1000, 0, "dec0000100000001").unwrap();
    let remote = Hlc::new(1000, 1, "dec0000200000001").unwrap();
    assert_eq!(resolve_lww(&local, &remote), MergeOutcome::RemoteWins);
}

#[test]
fn lww_local_wins_by_counter() {
    let local = Hlc::new(1000, 5, "dec0000100000001").unwrap();
    let remote = Hlc::new(1000, 3, "dec0000200000001").unwrap();
    assert_eq!(resolve_lww(&local, &remote), MergeOutcome::LocalWins);
}

#[test]
fn lww_remote_wins_by_device_suffix_tiebreak() {
    // Same physical_ms and counter, different device suffix.
    let local = Hlc::new(1000, 0, "aaaa0000aaaa0000").unwrap();
    let remote = Hlc::new(1000, 0, "bbbb0000bbbb0000").unwrap();
    // remote > local because "bbbb…" > "aaaa…"
    assert_eq!(resolve_lww(&local, &remote), MergeOutcome::RemoteWins);
}

#[test]
fn lww_local_wins_by_device_suffix_tiebreak() {
    let local = Hlc::new(1000, 0, "ffff0000ffff0000").unwrap();
    let remote = Hlc::new(1000, 0, "aaaa0000aaaa0000").unwrap();
    assert_eq!(resolve_lww(&local, &remote), MergeOutcome::LocalWins);
}

#[test]
fn lww_is_idempotent() {
    let local = Hlc::new(500, 3, "deafbeefdeafbeef").unwrap();
    let remote = Hlc::new(500, 3, "deafbeefdeafbeef").unwrap();
    // Applying the same version twice should be a no-op (local wins).
    assert_eq!(resolve_lww(&local, &remote), MergeOutcome::LocalWins);
}

// -----------------------------------------------------------------------
// tag_merge_winner
// -----------------------------------------------------------------------

#[test]
fn tag_merge_first_id_smaller() {
    let (winner, loser) = tag_merge_winner("01966a3f-0001", "01966a3f-0002");
    assert_eq!(winner, "01966a3f-0001");
    assert_eq!(loser, "01966a3f-0002");
}

#[test]
fn tag_merge_second_id_smaller() {
    let (winner, loser) = tag_merge_winner("01966a3f-0009", "01966a3f-0003");
    assert_eq!(winner, "01966a3f-0003");
    assert_eq!(loser, "01966a3f-0009");
}

#[test]
fn tag_merge_equal_ids() {
    let (winner, loser) = tag_merge_winner("same-id", "same-id");
    assert_eq!(winner, "same-id");
    assert_eq!(loser, "same-id");
}

#[test]
fn tag_merge_is_deterministic() {
    // Regardless of argument order, the winner is always the same.
    let (w1, l1) = tag_merge_winner("alpha", "beta");
    let (w2, l2) = tag_merge_winner("beta", "alpha");
    assert_eq!(w1, w2);
    assert_eq!(l1, l2);
}

#[test]
fn tag_merge_uuidv7_chronological_order() {
    // UUIDv7 strings: earlier timestamp = lexicographically smaller = winner.
    let earlier = "01966a3f-7c8b-7d4e-8000-000000000001";
    let later = "01966a40-0000-7d4e-8000-000000000001";
    let (winner, _loser) = tag_merge_winner(earlier, later);
    assert_eq!(winner, earlier, "earlier UUIDv7 should win");
}

// -----------------------------------------------------------------------
// recurrence_dedup_winner
// -----------------------------------------------------------------------

#[test]
fn recurrence_dedup_first_id_smaller() {
    let (winner, loser) = recurrence_dedup_winner("task-001", "task-002");
    assert_eq!(winner, "task-001");
    assert_eq!(loser, "task-002");
}

#[test]
fn recurrence_dedup_second_id_smaller() {
    let (winner, loser) = recurrence_dedup_winner("task-zzz", "task-aaa");
    assert_eq!(winner, "task-aaa");
    assert_eq!(loser, "task-zzz");
}

#[test]
fn recurrence_dedup_is_deterministic() {
    let (w1, l1) = recurrence_dedup_winner("x", "y");
    let (w2, l2) = recurrence_dedup_winner("y", "x");
    assert_eq!(w1, w2);
    assert_eq!(l1, l2);
}

#[test]
fn recurrence_dedup_matches_tag_merge_semantics() {
    // recurrence_dedup_winner delegates to tag_merge_winner — verify parity.
    let (tw, tl) = tag_merge_winner("id-a", "id-b");
    let (rw, rl) = recurrence_dedup_winner("id-a", "id-b");
    assert_eq!(tw, rw);
    assert_eq!(tl, rl);
}
