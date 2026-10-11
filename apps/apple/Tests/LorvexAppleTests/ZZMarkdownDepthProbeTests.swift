import Foundation
import Markdown
import Testing

@testable import LorvexMarkdownUI

// Scratch probe (git-excluded): builds MarkdownNote from deeply nested input on
// the main thread, whose stack is the one SwiftUI view bodies run on.
// PROBE_KIND = quote | dash | ordered | emph | quotedash, PROBE_N = nesting count.

@MainActor
@Test
func zzMarkdownDepthProbe() {
  let env = ProcessInfo.processInfo.environment
  guard let kind = env["PROBE_KIND"], let n = env["PROBE_N"].flatMap(Int.init) else { return }
  if kind == "spawn" {
    // Per-call cost of the deep-stack thread hop, with empty work and with a typical note.
    let typical = "## Plan\n\nShip **native** detail rendering with _care_.\n\n- Parse notes\n- Render SwiftUI\n- Check `code`\n\n> Keep MCP semantics intact.\n"
    let t0 = Date()
    for _ in 0..<n { _ = MarkdownDeepStack.run { 1 } }
    let hop = Date().timeIntervalSince(t0) / Double(n)
    let t1 = Date()
    for _ in 0..<n { _ = MarkdownNote(typical) }
    let full = Date().timeIntervalSince(t1) / Double(n)
    print("PROBE kind=spawn n=\(n) hopMicros=\(hop * 1e6) typicalNoteMicros=\(full * 1e6)")
    return
  }
  let source: String
  switch kind {
  case "quote": source = String(repeating: ">", count: n) + " x"
  case "dash": source = String(repeating: "- ", count: n) + "x"
  case "ordered": source = String(repeating: "1. ", count: n) + "x"
  case "emph": source = String(repeating: "_a ", count: n) + String(repeating: "a_ ", count: n)
  case "quotedash": source = String(repeating: "> - ", count: n) + "x"
  default: return
  }
  let start = Date()
  if env["PROBE_STAGE"] == "parse" {
    let document = Document(parsing: source)
    print("PROBE kind=\(kind) n=\(n) stage=parse children=\(document.childCount) seconds=\(Date().timeIntervalSince(start))")
    return
  }
  let note = MarkdownNote(source)
  let elapsed = Date().timeIntervalSince(start)
  print("PROBE kind=\(kind) n=\(n) chars=\(source.count) blocks=\(note.blocks.count) seconds=\(elapsed)")
}
