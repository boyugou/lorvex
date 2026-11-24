import Foundation

/// MCP's stdio framing over two file descriptors: one JSON-RPC message per
/// line in each direction.
///
/// Reading runs on a dedicated thread with blocking `read(2)`, so a pipe and a
/// Unix socket behave the same and nothing polls on a timer. Writing runs on a
/// serial queue that writes each frame and its newline whole, in the order the
/// frames were sent, so concurrent responses never interleave and a client
/// that reads slowly never blocks a Swift concurrency thread. The descriptors'
/// flags are left as the client set them; a descriptor the client made
/// non-blocking is waited on with `poll(2)`.
///
/// After a failed write (the client closed its end) later frames are dropped.
/// The host ignores `SIGPIPE`, so that failure is an error code, not a signal.
final class MCPStdioChannel: @unchecked Sendable {
  private let input: Int32
  private let output: Int32
  private let writer = DispatchQueue(label: "app.lorvex.mcp.stdout")
  /// Confined to `writer`.
  private var writeFailed = false

  init(input: Int32 = STDIN_FILENO, output: Int32 = STDOUT_FILENO) {
    self.input = input
    self.output = output
  }

  /// The lines read from the input, without their newline, until the input
  /// ends or a read fails. Lines holding only JSON whitespace are skipped;
  /// bytes after the last newline are delivered as a final line when the
  /// input ends.
  func lines() -> AsyncStream<Data> {
    let input = self.input
    return AsyncStream { continuation in
      let reader = Thread {
        var splitter = MCPLineSplitter()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
          let count = buffer.withUnsafeMutableBytes { read(input, $0.baseAddress, $0.count) }
          if count < 0 {
            if errno == EINTR { continue }
            if errno == EAGAIN || errno == EWOULDBLOCK, Self.wait(for: input, events: Int16(POLLIN)) {
              continue
            }
            break
          }
          if count == 0 { break }
          for line in splitter.append(buffer[0..<count]) { continuation.yield(line) }
        }
        if let last = splitter.finish() { continuation.yield(last) }
        continuation.finish()
      }
      reader.name = "app.lorvex.mcp.stdin"
      reader.start()
    }
  }

  /// Queues `frame` and a newline to be written. Returns at once.
  func send(_ frame: Data) {
    writer.async { [self] in
      guard !writeFailed else { return }
      var bytes = frame
      bytes.append(0x0A)
      writeFailed = !bytes.withUnsafeBytes { Self.writeAll($0, to: output) }
    }
  }

  /// Returns once every frame queued before the call has been written or
  /// dropped.
  func flush() async {
    await withCheckedContinuation { continuation in
      writer.async { continuation.resume() }
    }
  }

  private static func writeAll(_ bytes: UnsafeRawBufferPointer, to output: Int32) -> Bool {
    guard let base = bytes.baseAddress else { return true }
    var offset = 0
    while offset < bytes.count {
      let written = write(output, base + offset, bytes.count - offset)
      if written >= 0 {
        offset += written
      } else if errno == EINTR {
        continue
      } else if errno == EAGAIN || errno == EWOULDBLOCK, wait(for: output, events: Int16(POLLOUT)) {
        continue
      } else {
        return false
      }
    }
    return true
  }

  /// Blocks until `descriptor` is ready for `events`; false when `poll`
  /// fails or reports the descriptor closed or invalid.
  private static func wait(for descriptor: Int32, events: Int16) -> Bool {
    var target = pollfd(fd: descriptor, events: events, revents: 0)
    while true {
      let ready = poll(&target, 1, -1)
      if ready > 0 { return target.revents & Int16(POLLNVAL) == 0 }
      if ready < 0 && errno != EINTR { return false }
    }
  }
}

/// Splits a byte stream into newline-terminated lines, keeping only the
/// unfinished line between calls.
struct MCPLineSplitter {
  private var pending = Data()
  /// How many bytes of `pending` are known to hold no newline.
  private var scanned = 0

  /// The bytes held between calls, counted from the start of the storage
  /// behind `pending`, including any a slice of it no longer shows. The helper
  /// runs for days under some clients, so this must stay the length of the
  /// unfinished line rather than grow with everything read.
  var retainedByteCount: Int { pending.endIndex }

  /// The lines `chunk` completes, without their newline, skipping lines that
  /// hold only JSON whitespace.
  mutating func append(_ chunk: ArraySlice<UInt8>) -> [Data] {
    pending.append(contentsOf: chunk)
    var lines: [Data] = []
    var lineStart = 0
    while let newline = pending[(pending.startIndex + scanned)...].firstIndex(of: 0x0A) {
      let line = pending[(pending.startIndex + lineStart)..<newline]
      if !Self.isBlank(line) { lines.append(Data(line)) }
      lineStart = newline - pending.startIndex + 1
      scanned = lineStart
    }
    // `Data.removeFirst` only moves the start index and keeps the storage;
    // copying the unfinished line is what releases the delivered ones.
    if lineStart > 0 { pending = Data(pending[(pending.startIndex + lineStart)...]) }
    scanned = pending.count
    return lines
  }

  /// The bytes after the last newline, once the input has ended, unless they
  /// are only JSON whitespace.
  func finish() -> Data? {
    Self.isBlank(pending) ? nil : pending
  }

  private static func isBlank(_ line: Data) -> Bool {
    line.allSatisfy { $0 == 0x20 || $0 == 0x09 || $0 == 0x0D || $0 == 0x0A }
  }
}
