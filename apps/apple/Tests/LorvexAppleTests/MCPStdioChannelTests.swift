import Darwin
import Foundation
import Testing

@testable import LorvexMCPHost

/// The stdio framing over the two kinds of descriptor clients hand the
/// helper: Claude Code and Claude Desktop use Unix sockets, Codex uses pipes.
@Suite("MCP stdio channel", .timeLimit(.minutes(1)))
struct MCPStdioChannelTests {
  enum Kind: String, CaseIterable, CustomTestStringConvertible {
    case socket, pipe
    var testDescription: String { rawValue }
  }

  /// Two connected descriptors: `[read end, write end]` for a pipe, the two
  /// ends of a stream socket pair otherwise.
  private func descriptors(_ kind: Kind) throws -> (Int32, Int32) {
    var fds: [Int32] = [-1, -1]
    let status =
      kind == .socket ? socketpair(AF_UNIX, SOCK_STREAM, 0, &fds) : pipe(&fds)
    try #require(status == 0)
    return (fds[0], fds[1])
  }

  private func writeAll(_ text: String, to fd: Int32) {
    let bytes = Array(text.utf8)
    var offset = 0
    while offset < bytes.count {
      let written = bytes[offset...].withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
      if written <= 0 { return }
      offset += written
    }
  }

  @Test("lines split across reads, CRLF, blank lines and a last line without a newline", arguments: Kind.allCases)
  func readsLines(kind: Kind) async throws {
    let (readEnd, writeEnd) = try descriptors(kind)
    defer { close(readEnd) }
    let channel = MCPStdioChannel(input: readEnd, output: -1)
    let lines = channel.lines()
    let large = String(repeating: "x", count: 200_000)
    writeAll(#"{"a":1}"#, to: writeEnd)
    writeAll("\n\n  \r\n" + #"{"b":"\#(large)"}"# + "\r\n" + #"{"c":3}"#, to: writeEnd)
    close(writeEnd)
    var received: [String] = []
    for await line in lines { received.append(String(decoding: line, as: UTF8.self)) }
    #expect(received.count == 3)
    #expect(received.first == #"{"a":1}"#)
    #expect(received.dropFirst().first == #"{"b":"\#(large)"}"# + "\r")
    #expect(received.last == #"{"c":3}"#)
  }

  @Test("frames are written whole, each followed by a newline", arguments: Kind.allCases)
  func writesFrames(kind: Kind) async throws {
    let (readEnd, writeEnd) = try descriptors(kind)
    let channel = MCPStdioChannel(input: -1, output: writeEnd)
    let large = Data(repeating: UInt8(ascii: "y"), count: 300_000)
    // A blocking reader on its own thread, so it never holds a Swift
    // concurrency thread the channel's writer might need.
    let (collected, deliver) = AsyncStream.makeStream(of: Data.self)
    Thread {
      var bytes = Data()
      var buffer = [UInt8](repeating: 0, count: 65_536)
      while true {
        let count = buffer.withUnsafeMutableBytes { read(readEnd, $0.baseAddress, $0.count) }
        if count <= 0 { break }
        bytes.append(contentsOf: buffer[0..<count])
      }
      close(readEnd)
      deliver.yield(bytes)
      deliver.finish()
    }.start()
    channel.send(Data("first".utf8))
    channel.send(large)
    channel.send(Data("last".utf8))
    await channel.flush()
    close(writeEnd)
    var expected = Data("first\n".utf8)
    expected.append(large)
    expected.append(Data("\nlast\n".utf8))
    var received: Data?
    for await bytes in collected { received = bytes }
    #expect(received == expected)
  }

  @Test("the reader keeps only the unfinished line, however much it has delivered")
  func splitterReleasesDeliveredLines() {
    let line = #"{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"get_overview"}}"#
    let count = 20_000
    let stream = Array(String(repeating: line + "\n", count: count).utf8)
    var splitter = MCPLineSplitter()
    var delivered = 0
    var largestRetained = 0
    var offset = 0
    while offset < stream.count {
      let end = min(offset + 4_096, stream.count)
      delivered += splitter.append(stream[offset..<end]).count
      largestRetained = max(largestRetained, splitter.retainedByteCount)
      offset = end
    }
    #expect(delivered == count)
    #expect(splitter.finish() == nil)
    #expect(largestRetained <= line.utf8.count, "held \(largestRetained) bytes")
  }

  @Test("a write to a closed peer drops the frame instead of ending the process")
  func closedPeer() async throws {
    signal(SIGPIPE, SIG_IGN)
    let (readEnd, writeEnd) = try descriptors(.socket)
    close(readEnd)
    let channel = MCPStdioChannel(input: -1, output: writeEnd)
    channel.send(Data("lost".utf8))
    channel.send(Data("also lost".utf8))
    await channel.flush()
    close(writeEnd)
  }
}
