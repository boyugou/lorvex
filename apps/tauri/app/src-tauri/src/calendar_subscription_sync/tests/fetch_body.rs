use super::*;

// -----------------------------------------------------------------------
// Body-read helpers
// -----------------------------------------------------------------------

/// A synthetic `Read` that emits `chunks` one read at a time and
/// then EOFs. Lets us exercise the size-cap + io-error branches
/// of `read_body_capped` without touching the network or
/// fabricating a real `reqwest::Response`.
struct ChunkReader {
    chunks: std::collections::VecDeque<std::io::Result<Vec<u8>>>,
}

impl ChunkReader {
    fn with_chunks<I: IntoIterator<Item = Vec<u8>>>(chunks: I) -> Self {
        Self {
            chunks: chunks
                .into_iter()
                .map(Ok)
                .collect::<std::collections::VecDeque<_>>(),
        }
    }

    fn with_results<I: IntoIterator<Item = std::io::Result<Vec<u8>>>>(chunks: I) -> Self {
        Self {
            chunks: chunks.into_iter().collect(),
        }
    }
}

impl std::io::Read for ChunkReader {
    fn read(&mut self, out: &mut [u8]) -> std::io::Result<usize> {
        loop {
            let Some(front) = self.chunks.front_mut() else {
                return Ok(0);
            };
            match front {
                Err(_) => {
                    let err = self.chunks.pop_front().unwrap().unwrap_err();
                    return Err(err);
                }
                Ok(bytes) if bytes.is_empty() => {
                    self.chunks.pop_front();
                    continue;
                }
                Ok(bytes) => {
                    let n = bytes.len().min(out.len());
                    out[..n].copy_from_slice(&bytes[..n]);
                    bytes.drain(..n);
                    return Ok(n);
                }
            }
        }
    }
}

#[test]
fn read_body_capped_accepts_body_under_limit() {
    let payload = b"BEGIN:VCALENDAR\r\nEND:VCALENDAR\r\n".to_vec();
    let reader = ChunkReader::with_chunks(vec![payload.clone()]);
    let got = read_body_capped(reader, 1024).expect("body under cap must succeed");
    assert_eq!(got, payload);
}

#[test]
fn read_body_capped_accepts_body_exactly_at_limit() {
    // Boundary case: the helper reads `limit + 1` bytes and
    // rejects only when the total is *strictly* greater than the
    // limit. A payload of exactly `limit` bytes must be accepted.
    let payload = vec![b'X'; 1024];
    let reader = ChunkReader::with_chunks(vec![payload]);
    let got = read_body_capped(reader, 1024).expect("exact-boundary body must succeed");
    assert_eq!(got.len(), 1024);
}

#[test]
fn read_body_capped_rejects_body_exceeding_cap() {
    // Feed arrives in multiple chunks that collectively exceed
    // the cap. The helper must surface `SizeCapExceeded` — the
    // real mitigation for a server that omits Content-Length
    // and streams gigabytes of garbage.
    let reader = ChunkReader::with_chunks(vec![
        vec![b'A'; 600],
        vec![b'B'; 600], // cumulative = 1200 > 1024
    ]);
    let err = read_body_capped(reader, 1024).expect_err("oversize body must be rejected");
    match err {
        IcsBodyReadError::SizeCapExceeded { limit } => assert_eq!(limit, 1024),
        other => panic!("expected SizeCapExceeded, got {other:?}"),
    }
}

#[test]
fn read_body_capped_surfaces_underlying_io_error() {
    // The bare `read_body_capped` helper is used for synthetic
    // in-memory streams; it propagates any underlying I/O error
    // unchanged. The mid-stream idle timeout lives one level up
    // in `read_body_capped_with_idle_timeout` and is exercised
    // by the dedicated tests below.
    let reader = ChunkReader::with_results(vec![
        Ok(b"BEGIN:VCAL".to_vec()),
        Err(std::io::Error::new(
            std::io::ErrorKind::ConnectionReset,
            "socket reset",
        )),
    ]);
    let err = read_body_capped(reader, 1024).expect_err("io error must abort the read");
    match err {
        IcsBodyReadError::Io(io_err) => {
            assert_eq!(io_err.kind(), std::io::ErrorKind::ConnectionReset);
        }
        other => panic!("expected Io error, got {other:?}"),
    }
}

#[test]
fn read_body_capped_size_error_maps_to_validation_app_error() {
    // The `into_app_error` mapping must produce a `Validation`
    // error (surfaced to the user) for cap-exceeded, and must
    // include the sanitized URL so the `last_error` diagnostic
    // tells the user which feed misbehaved.
    let err = IcsBodyReadError::SizeCapExceeded { limit: 2048 };
    let app_err = err.into_app_error("https://example.com/feed.ics");
    let msg = format!("{app_err}");
    assert!(
        msg.contains("2048"),
        "error should include the size limit, got: {msg}"
    );
    assert!(
        msg.contains("https://example.com/feed.ics"),
        "error should include the sanitized URL, got: {msg}"
    );
    assert!(matches!(app_err, AppError::Validation(_)));
}

#[test]
fn read_body_capped_io_error_maps_to_internal_app_error() {
    // I/O errors (including the socket-level idle timeout) are
    // transient — they must be classified as `Internal` so the
    // caller's error-state machine records "try again later"
    // rather than permanently marking the feed as bad.
    let io_err = std::io::Error::new(std::io::ErrorKind::TimedOut, "read timeout");
    let err = IcsBodyReadError::Io(io_err);
    let app_err = err.into_app_error("https://example.com/feed.ics");
    let msg = format!("{app_err}");
    assert!(
        msg.contains("https://example.com/feed.ics"),
        "error should include the sanitized URL, got: {msg}"
    );
    assert!(matches!(app_err, AppError::Internal(_)));
}

// -----------------------------------------------------------------------
// Mid-stream idle timeout + size cap
// -----------------------------------------------------------------------

/// Reader that sleeps `delay` before returning each chunk, used
/// to simulate a throttled feed. Driving the worker thread with
/// a blocking sleep is the cleanest way to reproduce the
/// "drip-feed" behavior without a real socket, and the caller's
/// `recv_timeout` is what enforces the idle window — so this
/// covers the production code path even without network.
struct SlowReader {
    chunks: std::sync::Mutex<std::collections::VecDeque<Vec<u8>>>,
    delay: std::time::Duration,
}

impl SlowReader {
    fn new(chunks: Vec<Vec<u8>>, delay: std::time::Duration) -> Self {
        Self {
            chunks: std::sync::Mutex::new(chunks.into()),
            delay,
        }
    }
}

impl std::io::Read for SlowReader {
    fn read(&mut self, out: &mut [u8]) -> std::io::Result<usize> {
        std::thread::sleep(self.delay);
        let mut guard = self.chunks.lock().unwrap();
        loop {
            let Some(front) = guard.front_mut() else {
                return Ok(0);
            };
            if front.is_empty() {
                guard.pop_front();
                continue;
            }
            let n = front.len().min(out.len());
            out[..n].copy_from_slice(&front[..n]);
            front.drain(..n);
            return Ok(n);
        }
    }
}

#[test]
fn ics_fetch_aborts_after_idle_gap_exceeds_window() {
    // widened the idle/gap budget so the test stays
    // reliable under sanitizer + coverage instrumentation. Worker
    // sleeps 1500ms between chunks; caller's idle window is 300ms.
    // The 5× ratio remains diagnostic of the property we're testing
    // (idle-timeout fires *before* the next chunk lands), and the
    // upper bound on `elapsed` is widened in lockstep so a slow CI
    // wake-up cannot misreport.
    let reader = SlowReader::new(
        vec![b"BEGIN:VCALENDAR\n".to_vec(), b"END:VCALENDAR\n".to_vec()],
        std::time::Duration::from_millis(1500),
    );
    let start = std::time::Instant::now();
    let err =
        read_body_capped_with_idle_timeout(reader, 1024, std::time::Duration::from_millis(300))
            .expect_err("idle gap must trip the timeout");
    let elapsed = start.elapsed();
    match err {
        IcsBodyReadError::IdleTimeout { window_secs } => {
            assert_eq!(window_secs, 0, "sub-second window rounds down to 0s");
        }
        other => panic!("expected IdleTimeout, got {other:?}"),
    }
    // Must abort during the first sleep (~1500ms), well before
    // the worker would have delivered any chunk. A comfortable
    // upper bound prevents flakes on slow CI.
    assert!(
        elapsed < std::time::Duration::from_millis(3000),
        "idle-abort should fire promptly; took {elapsed:?}"
    );
}

#[test]
fn ics_fetch_aborts_when_body_exceeds_cap() {
    // Total payload = 3 KiB but cap is 1 KiB. The helper must
    // reject with `SizeCapExceeded` before the worker finishes —
    // and since the chunks arrive back-to-back (no artificial
    // delay) it never trips the idle timeout by mistake.
    let reader = SlowReader::new(
        vec![vec![b'A'; 600], vec![b'B'; 600], vec![b'C'; 600]],
        std::time::Duration::from_millis(5),
    );
    let err = read_body_capped_with_idle_timeout(reader, 1024, std::time::Duration::from_secs(5))
        .expect_err("oversize body must be rejected");
    match err {
        IcsBodyReadError::SizeCapExceeded { limit } => assert_eq!(limit, 1024),
        other => panic!("expected SizeCapExceeded, got {other:?}"),
    }
}

#[test]
fn ics_fetch_succeeds_with_normal_throughput() {
    // Chunks arrive every 20ms, well inside the 500ms idle
    // window. The helper must reassemble them into the full
    // payload without ever firing the idle timeout.
    let payload: Vec<u8> = b"BEGIN:VCALENDAR\r\nBODY\r\nEND:VCALENDAR\r\n".to_vec();
    let reader = SlowReader::new(
        vec![
            payload[..10].to_vec(),
            payload[10..20].to_vec(),
            payload[20..].to_vec(),
        ],
        std::time::Duration::from_millis(20),
    );
    let got =
        read_body_capped_with_idle_timeout(reader, 1024, std::time::Duration::from_millis(500))
            .expect("normal throughput must complete");
    assert_eq!(got, payload);
}

#[test]
fn idle_timeout_error_maps_to_internal_app_error() {
    // The idle-timeout variant must be surfaced as `Internal`
    // (transient) rather than `Validation` (permanent) so the
    // caller's error-state machine retries rather than poisoning
    // the feed's `last_error` slot forever.
    let err = IcsBodyReadError::IdleTimeout { window_secs: 10 };
    let app_err = err.into_app_error("https://example.com/feed.ics");
    let msg = format!("{app_err}");
    assert!(
        msg.contains("10s"),
        "error should name the idle window, got: {msg}"
    );
    assert!(
        msg.contains("https://example.com/feed.ics"),
        "error should include the sanitized URL, got: {msg}"
    );
    assert!(matches!(app_err, AppError::Internal(_)));
}
