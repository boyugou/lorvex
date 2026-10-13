import Foundation
import LorvexCore
import LorvexDomain
import Testing

// Persistent probe. Mutates the production-shaped v1 backup fixture, as a damaged or
// hand-edited backup file would arrive, and imports each result into a fresh in-memory
// store. An import may succeed, report issues, or throw; it must never trap the process,
// and must stay inside a time bound.
//
// Run from apps/apple (the build must be current):
//   IMPORTFUZZ_RUN=1 IMPORTFUZZ_SEED=1 IMPORTFUZZ_ROUNDS=400 swift test --skip-build -j 4 --filter ZZImportMutationFuzzProbe
// The test is skipped unless IMPORTFUZZ_RUN is set, so a full suite run stays fast.
//
// The document about to be imported is written to `lastInputPath` first, so a trap that ends
// the process leaves the offending file behind. Findings print as `IMPORTFUZZSUMMARY`.
//
// After a restore the store is exported again, and no text in it may hold a codepoint the write
// boundary strips (bidi controls, zero-width characters, line separators): a restore path that
// writes rows directly, bypassing the validators, would leave such text behind. A finding prints
// as `IMPORTFUZZUNSANITIZED`.

private let scratch =
  ProcessInfo.processInfo.environment["LORVEX_SCRATCH_DIR"]
  ?? FileManager.default.temporaryDirectory.path
private let lastInputPath = scratch + "/importfuzz_last.json"

private struct SplitMix64: RandomNumberGenerator {
  var state: UInt64
  mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var z = state
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    return z ^ (z >> 31)
  }
}

/// A JSON tree whose numbers are written as given, so a mutation can name a value
/// (`1e999`, `-0`, `9223372036854775808`) that Foundation would not serialize.
private indirect enum Node {
  case object([(String, Node)])
  case array([Node])
  case string(String)
  case number(String)
  case bool(Bool)
  case null

  init(_ any: Any) {
    switch any {
    case let dict as [String: Any]:
      self = .object(dict.keys.sorted().map { ($0, Node(dict[$0]!)) })
    case let array as [Any]:
      self = .array(array.map(Node.init))
    case let string as String:
      self = .string(string)
    case let number as NSNumber:
      if CFGetTypeID(number) == CFBooleanGetTypeID() {
        self = .bool(number.boolValue)
      } else {
        self = .number("\(number)")
      }
    default:
      self = .null
    }
  }

  var json: String {
    switch self {
    case .object(let members):
      return "{" + members.map { "\(Node.quoted($0.0)):\($0.1.json)" }.joined(separator: ",") + "}"
    case .array(let items):
      return "[" + items.map(\.json).joined(separator: ",") + "]"
    case .string(let value): return Node.quoted(value)
    case .number(let text): return text
    case .bool(let value): return value ? "true" : "false"
    case .null: return "null"
    }
  }

  private static func quoted(_ text: String) -> String {
    var out = "\""
    for scalar in text.unicodeScalars {
      switch scalar {
      case "\"": out += "\\\""
      case "\\": out += "\\\\"
      case "\n": out += "\\n"
      case "\r": out += "\\r"
      case "\t": out += "\\t"
      default:
        if scalar.value < 0x20 {
          out += String(format: "\\u%04x", scalar.value)
        } else {
          out.unicodeScalars.append(scalar)
        }
      }
    }
    return out + "\""
  }

  /// The number of nodes in the tree, so a mutation can pick one uniformly.
  var count: Int {
    switch self {
    case .object(let members): return 1 + members.reduce(0) { $0 + $1.1.count }
    case .array(let items): return 1 + items.reduce(0) { $0 + $1.count }
    default: return 1
    }
  }

  /// Rebuilds the tree with `transform` applied to the node at preorder index `target`.
  func replacing(_ target: Int, with transform: (Node) -> Node?) -> Node {
    var index = 0
    func walk(_ node: Node) -> Node? {
      let here = index
      index += 1
      if here == target { return transform(node) }
      switch node {
      case .object(let members):
        var rebuilt: [(String, Node)] = []
        for (key, child) in members {
          if let next = walk(child) { rebuilt.append((key, next)) }
        }
        return .object(rebuilt)
      case .array(let items):
        return .array(items.compactMap(walk))
      default:
        return node
      }
    }
    return walk(self) ?? .null
  }
}

private let hostileStrings: [String] = [
  "", " ", "\u{0}", String(repeating: "a", count: 20_000), "\u{202E}rtl\u{202C}",
  "💥🧪👨‍👩‍👧‍👦", "../../etc/passwd", "'; DROP TABLE tasks; --", "2026-02-30", "9999-12-31",
  "0001-01-01", "25:61", "not-a-uuid", "00000000-0000-0000-0000-000000000000",
  "FREQ=DAILY;COUNT=999999999", "{\"a\":1}",
]

private let hostileNumbers: [String] = [
  "0", "-1", "-0", "1e999", "-1e999", "1e-999", "9223372036854775807", "9223372036854775808",
  "-9223372036854775809", "18446744073709551616", "0.5", "NaN",
]

/// `valueOnly` keeps the document's shape and replaces scalars, so the manifest counts and the
/// whole-backup preflight still pass more often and the hostile values reach the apply code.
private func mutated(_ root: Node, valueOnly: Bool, rng: inout SplitMix64) -> Node {
  var tree = root
  for _ in 0..<Int.random(in: 1...4, using: &rng) {
    let target = Int.random(in: 0..<tree.count, using: &rng)
    let pick =
      valueOnly
      ? [1, 2, 3, 4, 8].randomElement(using: &rng) ?? 2
      : Int.random(in: 0..<10, using: &rng)
    let string = hostileStrings.randomElement(using: &rng) ?? ""
    let number = hostileNumbers.randomElement(using: &rng) ?? "0"
    tree = tree.replacing(target) { node in
      if valueOnly {
        switch node {
        case .object, .array: return node
        default: break
        }
      }
      switch pick {
      case 0: return nil  // delete the member or element
      case 1: return .null
      case 2: return .string(string)
      case 3: return .number(number)
      case 4: return .bool(Bool.random(using: &rng))
      case 5: return .array([node, node])  // wrong shape, duplicated
      case 6: return .object([("value", node)])  // wrong shape, wrapped
      case 7:
        if case .array(let items) = node { return .array(items + items) }  // duplicate ids
        if case .object(let members) = node, let first = members.first {
          return .object(members + [first])  // a repeated key
        }
        return node
      case 8:
        if case .string(let text) = node { return .string(text + string) }
        return .string(string)
      default:
        if case .array(let items) = node { return .array(items.reversed()) }
        return .null
      }
    }
  }
  return tree
}

/// Byte-level damage: a truncated file, a flipped byte, a spliced-in chunk.
private func damaged(_ data: Data, rng: inout SplitMix64) -> Data {
  var bytes = [UInt8](data)
  guard !bytes.isEmpty else { return data }
  switch Int.random(in: 0..<4, using: &rng) {
  case 0:
    bytes.removeLast(Int.random(in: 1...min(bytes.count, 400), using: &rng))
  case 1:
    bytes[Int.random(in: 0..<bytes.count, using: &rng)] = UInt8.random(in: 0...255, using: &rng)
  case 2:
    let at = Int.random(in: 0..<bytes.count, using: &rng)
    bytes.insert(contentsOf: [0xFF, 0xFE, 0x00, 0x7B, 0x22], at: at)
  default:
    let from = Int.random(in: 0..<bytes.count, using: &rng)
    let to = min(bytes.count, from + Int.random(in: 1...64, using: &rng))
    bytes.insert(contentsOf: bytes[from..<to], at: Int.random(in: 0..<bytes.count, using: &rng))
  }
  return Data(bytes)
}

/// The first string anywhere in `value` that holds a codepoint the sanitizer strips.
private func firstUnsanitizedString(in value: Any) -> String? {
  switch value {
  case let text as String:
    return UnicodeHygiene.containsStrippedCodepoint(text) ? text : nil
  case let array as [Any]:
    for item in array { if let hit = firstUnsanitizedString(in: item) { return hit } }
    return nil
  case let dictionary as [String: Any]:
    for (_, item) in dictionary { if let hit = firstUnsanitizedString(in: item) { return hit } }
    return nil
  default:
    return nil
  }
}

@Suite("Import mutation fuzz probe", .serialized)
struct ZZImportMutationFuzzProbeTests {
  @Test(
    "A damaged backup is refused or restored in part, and never traps",
    .enabled(if: ProcessInfo.processInfo.environment["IMPORTFUZZ_RUN"] != nil))
  func damagedBackupsNeverTrap() async throws {
    let environment = ProcessInfo.processInfo.environment
    let seed = UInt64(environment["IMPORTFUZZ_SEED"] ?? "1") ?? 1
    let rounds = Int(environment["IMPORTFUZZ_ROUNDS"] ?? "400") ?? 400
    let baseData = Data(BackupV1GoldenFixture.singleFileJSON.utf8)
    let base = Node(try JSONSerialization.jsonObject(with: baseData))

    var rng = SplitMix64(state: seed)
    var refused = 0
    var restored = 0
    var slow: [String] = []
    var unsanitized: [String] = []
    for round in 0..<rounds {
      let document: Data
      if round % 4 == 3 {
        document = damaged(baseData, rng: &rng)
      } else {
        document = Data(mutated(base, valueOnly: round % 2 == 0, rng: &rng).json.utf8)
      }
      try? document.write(to: URL(fileURLWithPath: lastInputPath))

      let started = Date()
      do {
        let (plan, decoded) = try LorvexDataImporter.plan(from: document)
        let service = try makeInMemoryCore()
        _ = await LorvexDataImporter.apply(plan: plan, decoded: decoded, using: service)
        restored += 1
        if let exported = try? await service.exportData(entities: [], format: "json"),
          let tree = try? JSONSerialization.jsonObject(with: Data(exported.utf8)),
          let hit = firstUnsanitizedString(in: tree)
        {
          let scalars = hit.unicodeScalars.prefix(40).map { String(format: "U+%04X", $0.value) }
          unsanitized.append("round \(round): \(scalars.joined(separator: " "))")
          print("IMPORTFUZZUNSANITIZED seed=\(seed) round=\(round) \(scalars.joined(separator: " "))")
        }
      } catch {
        refused += 1
      }
      let seconds = Date().timeIntervalSince(started)
      if seconds > 5 { slow.append("round \(round): \(seconds) s") }
    }
    print("IMPORTFUZZSUMMARY seed=\(seed) rounds=\(rounds) refused=\(refused) planned=\(restored) slow=\(slow)")
    #expect(slow.isEmpty, "imports that took over five seconds: \(slow)")
    #expect(unsanitized.isEmpty, "restored text that holds stripped codepoints: \(unsanitized.prefix(5))")
  }
}
