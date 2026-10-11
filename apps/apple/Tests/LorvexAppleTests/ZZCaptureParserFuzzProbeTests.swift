import Foundation
import LorvexCore
import Testing

// Persistent, git-excluded probe. Feeds the capture parser lines mutated from the parser's own
// test suites and checks that nothing traps, stalls, or breaks a result invariant.
//
// Run from apps/apple (the build must be current):
//   FUZZ_RUN=1 FUZZ_SEED=1 FUZZ_PER_LANG=120 swift test --skip-build -j 4 --filter ZZCaptureParserFuzzProbe
// The test is skipped unless FUZZ_RUN is set, so a full suite run stays fast. FUZZ_STRICT=1 also
// reports a title that keeps a combining mark with no letter before it; FUZZ_NFD=1 also compares each
// line's decomposed form with its precomposed form.
//
// The line about to be parsed is written to `lastInputPath` first, so a trap that ends the process
// leaves the offending line behind (read it with `cat -v`). Findings are collected per kind and
// written to `findingsPath` at the end; the summary prints as `FUZZSUMMARY`.

private let scratch =
  ProcessInfo.processInfo.environment["LORVEX_SCRATCH_DIR"]
  ?? FileManager.default.temporaryDirectory.path
private let lastInputPath = scratch + "/fuzz_last.txt"
private let findingsPath = scratch + "/fuzz_findings.txt"

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

private let languageByFileWord: [String: String] = [
  "Arabic": "ar", "Bengali": "bn", "Dutch": "nl", "French": "fr", "German": "de", "Greek": "el",
  "Hebrew": "he", "Hindi": "hi", "Indonesian": "id", "Italian": "it", "Japanese": "ja",
  "Korean": "ko", "Malay": "ms", "Marathi": "mr", "Persian": "fa", "Polish": "pl",
  "Portuguese": "pt", "Romanian": "ro", "Russian": "ru", "Spanish": "es", "Tamil": "ta",
  "Telugu": "te", "Thai": "th", "Turkish": "tr", "Ukrainian": "uk", "Urdu": "ur",
  "Vietnamese": "vi",
]

private let allLanguages = Array(languageByFileWord.values) + ["en", "zh-Hans", "zh-Hant"]

private let lists: [LorvexCaptureParser.ListOption] = [
  .init(id: "l1", name: "Work", aliases: ["work"]),
  .init(id: "l2", name: "Offsite 2026"),
  .init(id: "l3", name: "收件箱", aliases: ["Inbox"]),
  .init(id: "l4", name: "Mañana"),
]

private func testsDirectory() -> URL {
  var url = URL(fileURLWithPath: #filePath)
  url.deleteLastPathComponent()
  return url
}

/// The single-line string literals of `source`, unescaped; a literal with an interpolation is skipped.
private func stringLiterals(in source: String) -> [String] {
  guard let regex = try? NSRegularExpression(pattern: #""((?:[^"\\\n]|\\.)*)""#) else { return [] }
  let ns = source as NSString
  var out: [String] = []
  for match in regex.matches(in: source, range: NSRange(location: 0, length: ns.length)) {
    let raw = ns.substring(with: match.range(at: 1))
    if raw.isEmpty || raw.contains("\\(") { continue }
    var text = String.UnicodeScalarView()
    let scalars = Array(raw.unicodeScalars)
    var i = 0
    var ok = true
    while i < scalars.count, ok {
      let c = scalars[i]
      guard c == "\\" else { text.append(c); i += 1; continue }
      guard i + 1 < scalars.count else { ok = false; break }
      switch scalars[i + 1] {
      case "n": text.append("\n"); i += 2
      case "t": text.append("\t"); i += 2
      case "r": text.append("\r"); i += 2
      case "0": text.append("\0"); i += 2
      case "\"": text.append("\""); i += 2
      case "\\": text.append("\\"); i += 2
      case "'": text.append("'"); i += 2
      case "u":
        guard i + 2 < scalars.count, scalars[i + 2] == "{",
          let close = ((i + 3)..<min(i + 12, scalars.count)).first(where: { scalars[$0] == "}" }),
          let value = UInt32(String(String.UnicodeScalarView(scalars[(i + 3)..<close])), radix: 16),
          let scalar = Unicode.Scalar(value)
        else { ok = false; break }
        text.append(scalar)
        i = close + 1
      default: ok = false
      }
    }
    if ok { out.append(String(text)) }
  }
  return out
}

private struct Seed {
  let text: String
  let languages: [String]
}

private func loadSeeds() -> [Seed] {
  let directory = testsDirectory()
  guard
    let files = try? FileManager.default.contentsOfDirectory(atPath: directory.path)
      .filter({ $0.hasPrefix("CaptureParser") && $0.hasSuffix("Tests.swift") }).sorted()
  else { return [] }
  var seeds: [Seed] = []
  for file in files {
    guard let source = try? String(contentsOf: directory.appending(path: file), encoding: .utf8)
    else { continue }
    let stem = file.dropFirst("CaptureParser".count).dropLast("Tests.swift".count)
    let languages: [String]
    if let code = languageByFileWord[String(stem)] {
      languages = code == "mr" ? ["mr", "hi"] : [code]
    } else {
      languages = ["en", "zh-Hans"]
    }
    var seen = Set<String>()
    for literal in stringLiterals(in: source) {
      let units = literal.utf16.count
      guard units >= 2, units <= 160, literal.contains(where: { $0.isLetter || $0.isNumber }),
        seen.insert(literal).inserted
      else { continue }
      seeds.append(Seed(text: literal, languages: languages))
    }
  }
  return seeds
}

// MARK: Mutations

private let bigNumbers = [
  "9223372036854775807", "9223372036854775808", "99999999999999999999",
  "153722867280912931", "153722867280912930", "1317624576693539402", "384307168202282326",
  "6405119470038039", "2562047788015216", "106751991167301", "4611686018427387904",
  "0000000000000000000000005", String(repeating: "9", count: 40), "2147483648", "4294967296",
  "65536", "100000", "1000000", "99999",
]

private let noise: [String] = [
  "😀", "👨‍👩‍👧‍👦", "🏳️‍🌈", "\u{200D}", "\u{200B}", "\u{200E}", "\u{200F}", "\u{202E}", "\u{FEFF}",
  "\u{0301}", "\u{0308}", "\u{FE0F}", "\u{0E31}", "\u{064B}", "\u{05B0}", "\u{094D}", "\u{1100}\u{1161}",
  "\u{0000}", "\u{0085}", "\u{2028}", "\u{2029}", "\r\n", "\u{00A0}", "\u{3000}", "ß", "ẞ", "İ", "ı",
  "ŉ", "ǰ", "ΐ", "ﬃ", "ǅ", "\u{1F1E8}\u{1F1F3}", "٣", "۴", "४", "০", "๕", "４５", "①", "½", "Ⅷ", "十", "〇",
]

private let spaceVariants = [
  " ", "\u{00A0}", "\u{3000}", "\u{2009}", "\u{200B}", "\t", "\u{202F}", "\u{FEFF}", "\u{2003}",
]

/// Replaces each maximal run of decimal digits (any script) by `replacement`'s digits in that
/// run's own script.
private func replacingDigitRuns(_ text: String, with replacement: String, onlyRun: Int? = nil) -> String? {
  var out = String.UnicodeScalarView()
  var runIndex = 0
  var changed = false
  let scalars = Array(text.unicodeScalars)
  var i = 0
  while i < scalars.count {
    let s = scalars[i]
    if s.properties.numericType == .decimal, let value = s.properties.numericValue {
      let zero = s.value - UInt32(value)
      var j = i
      while j < scalars.count, scalars[j].properties.numericType == .decimal { j += 1 }
      if onlyRun == nil || onlyRun == runIndex {
        for digit in replacement.unicodeScalars {
          if let d = digit.properties.numericValue, digit.properties.numericType == .decimal,
            let mapped = Unicode.Scalar(zero + UInt32(d))
          {
            out.append(mapped)
          } else {
            out.append(digit)
          }
        }
        changed = true
      } else {
        out.append(contentsOf: scalars[i..<j])
      }
      runIndex += 1
      i = j
    } else {
      out.append(s)
      i += 1
    }
  }
  return changed ? String(out) : nil
}

private func digitRunCount(_ text: String) -> Int {
  var count = 0
  var inRun = false
  for s in text.unicodeScalars {
    let isDigit = s.properties.numericType == .decimal
    if isDigit, !inRun { count += 1 }
    inRun = isDigit
  }
  return count
}

private func mutations(of text: String, rng: inout SplitMix64) -> [(String, String)] {
  var out: [(String, String)] = []
  func add(_ name: String, _ value: String?) {
    if let value, value != text { out.append((name, value)) }
  }
  let scalars = Array(text.unicodeScalars)
  func build(_ array: [Unicode.Scalar]) -> String {
    var view = String.UnicodeScalarView()
    view.append(contentsOf: array)
    return String(view)
  }

  // Huge digit runs, all runs at once and one run at a time.
  let runs = digitRunCount(text)
  if runs > 0 {
    for big in bigNumbers.shuffled(using: &rng).prefix(7) {
      add("digits-all \(big.prefix(12))", replacingDigitRuns(text, with: big))
      add("digits-one \(big.prefix(12))", replacingDigitRuns(text, with: big, onlyRun: Int.random(in: 0..<runs, using: &rng)))
    }
    add("decimal-big", replacingDigitRuns(text, with: String(repeating: "9", count: 25) + ".5"))
    add("decimal-big-comma", replacingDigitRuns(text, with: String(repeating: "9", count: 20) + ",5"))
    add("decimal-tiny", replacingDigitRuns(text, with: "0.0000000000000000001"))
    add("digits-zero", replacingDigitRuns(text, with: "0"))
    add("digits-99", replacingDigitRuns(text, with: "99"))
    add("digits-neg", replacingDigitRuns(text, with: "-5"))
    add("digits-2400", replacingDigitRuns(text, with: "24:60"))
  }
  // Structure.
  if scalars.count > 2 {
    add("truncate", build(Array(scalars.prefix(Int.random(in: 1..<scalars.count, using: &rng)))))
    var dropped = scalars
    dropped.remove(at: Int.random(in: 0..<dropped.count, using: &rng))
    add("drop-one", build(dropped))
    var swapped = scalars
    let k = Int.random(in: 0..<(scalars.count - 1), using: &rng)
    swapped.swapAt(k, k + 1)
    add("swap-adjacent", build(swapped))
  }
  add("repeat3", [text, text, text].joined(separator: " "))
  add("upper", text.uppercased())
  add("lower", text.lowercased())
  add("title-fold", text.capitalized)
  // Noise.
  for _ in 0..<3 {
    var array = scalars
    let n = noise.randomElement(using: &rng) ?? ""
    let at = Int.random(in: 0...array.count, using: &rng)
    array.insert(contentsOf: Array(n.unicodeScalars), at: at)
    add("noise-insert", build(array))
  }
  add("noise-tail", text + (noise.randomElement(using: &rng) ?? ""))
  add("noise-head", (noise.randomElement(using: &rng) ?? "") + text)
  add("spaces", String(text.map { $0 == " " ? Character(spaceVariants.randomElement(using: &rng) ?? " ") : $0 }))
  add("crlf", text.replacingOccurrences(of: " ", with: ["\r\n", "\n", "\r", "\u{2028}", "\u{0085}"].randomElement(using: &rng) ?? "\n"))
  add("hash-all", text.split(separator: " ").map { "#\($0)" }.joined(separator: " "))
  add("punct", text + [".", "!", "?", "。", "、", "،", "؟", "…", ")", "(", "\"", "”"].randomElement(using: &rng)!)
  return out
}

// MARK: Checks

private struct Findings {
  private(set) var counts: [String: Int] = [:]
  private(set) var examples: [String: [String]] = [:]
  var maxOffset = 0
  var maxOffsetInput = ""
  var slowest: [(Double, String)] = []
  var parses = 0

  mutating func add(_ kind: String, _ input: String) {
    counts[kind, default: 0] += 1
    if examples[kind, default: []].count < 8 { examples[kind, default: []].append(input) }
  }

  mutating func noteTime(_ seconds: Double, _ input: String) {
    slowest.append((seconds, input))
    slowest.sort { $0.0 > $1.0 }
    if slowest.count > 12 { slowest.removeLast() }
  }
}

private func hasStrayMark(_ text: String) -> Bool {
  var previous: Unicode.Scalar?
  for scalar in text.unicodeScalars {
    if scalar.properties.isGraphemeExtend, previous == nil || previous!.properties.isWhitespace { return true }
    previous = scalar
  }
  return false
}

private func check(_ input: String, _ parsed: LorvexCaptureParse, findings: inout Findings) {
  if let m = parsed.estimatedMinutes, !(1...1440).contains(m) { findings.add("estimate-range \(m)", input) }
  if let s = parsed.startMinutes, !(0...1439).contains(s) { findings.add("start-range \(s)", input) }
  for (name, value) in [
    ("planned", parsed.plannedDayOffset), ("due", parsed.dueDayOffset),
    ("repeatStart", parsed.recurrenceStartOffset),
  ] {
    guard let value else { continue }
    if abs(value) > findings.maxOffset { findings.maxOffset = abs(value); findings.maxOffsetInput = input }
    if abs(value) > 3660 { findings.add("offset-huge \(name)", input) }
  }
  if let rule = parsed.recurrence {
    if let i = rule.interval, !(1...10_000).contains(i) { findings.add("interval-range", input) }
    if let c = rule.count, c < 1 { findings.add("count-range", input) }
    if let days = rule.byMonthDay, days.contains(where: { !(1...31).contains($0) && $0 != -1 }) {
      findings.add("bymonthday-range", input)
    }
  }
  let trimmed = parsed.title.trimmingCharacters(in: .whitespacesAndNewlines)
  if trimmed != parsed.title { findings.add("title-untrimmed", input) }
  if parsed.title.contains(where: { $0.isNewline }) { findings.add("title-newline", input) }
  // The parser reads the line with its letters composed, so a phrase is looked up in the composed
  // line. Whitespace is ignored: a phrase read after another was removed keeps the gap it left.
  let single = LorvexCaptureParser.singleLine(input)
  func solid(_ text: String) -> [UInt32] {
    text.precomposedStringWithCanonicalMapping.unicodeScalars.filter { !$0.properties.isWhitespace }.map(\.value)
  }
  let singleScalars = solid(single)
  for phrase in parsed.phrases {
    let needle = solid(phrase.text)
    var found = needle.isEmpty
    if !found, singleScalars.count >= needle.count {
      for start in 0...(singleScalars.count - needle.count)
      where Array(singleScalars[start..<(start + needle.count)]) == needle {
        found = true
        break
      }
    }
    if !found {
      findings.add("phrase-not-in-input", input)
      break
    }
  }
  // A title gains no mark that has lost its letter (one that starts it or follows a space). Only
  // under FUZZ_STRICT: a mutation that glues a combining mark after a Latin keyword leaves the mark
  // behind, and real text does not.
  if ProcessInfo.processInfo.environment["FUZZ_STRICT"] != nil, hasStrayMark(parsed.title),
    !hasStrayMark(single)
  {
    findings.add("title-stray-mark", input)
  }
  if parsed.title.utf16.count > single.utf16.count { findings.add("title-longer-than-input", input) }
}


/// The fields of a parse that a line's Unicode form must not change; text is compared precomposed.
private func fingerprint(_ p: LorvexCaptureParse) -> String {
  [
    p.title.precomposedStringWithCanonicalMapping,
    String(describing: p.plannedDayOffset), String(describing: p.dueDayOffset),
    String(describing: p.estimatedMinutes), String(describing: p.startMinutes),
    String(describing: p.recurrence), String(describing: p.recurrenceStartOffset),
    String(describing: p.listID), String(describing: p.priority),
    p.tags.map { $0.precomposedStringWithCanonicalMapping }.joined(separator: ","),
    p.phrases.map { "\($0.kind)" }.joined(separator: ","),
  ].joined(separator: " | ")
}

// MARK: Probe

@Suite("Capture parser fuzz probe", .serialized)
struct ZZCaptureParserFuzzProbe {
  private func environmentInt(_ name: String, _ fallback: Int) -> Int {
    ProcessInfo.processInfo.environment[name].flatMap { Int($0) } ?? fallback
  }

  @Test(
    "mutated lines from the parser suites never trap and keep their invariants",
    .enabled(if: ProcessInfo.processInfo.environment["FUZZ_RUN"] != nil),
    .timeLimit(.minutes(60)))
  func mutatedLines() throws {
    var rng = SplitMix64(state: UInt64(environmentInt("FUZZ_SEED", 1)))
    let perLanguage = environmentInt("FUZZ_PER_LANG", 80)
    let seeds = loadSeeds()
    #expect(seeds.count > 500, "corpus size \(seeds.count)")
    let byLanguage = Dictionary(grouping: seeds, by: { $0.languages.joined(separator: ",") })
    var findings = Findings()
    let clock = ContinuousClock()

    func run(_ input: String, languages: [String]) {
      try? input.write(toFile: lastInputPath, atomically: false, encoding: .utf8)
      let start = clock.now
      let parsed = LorvexCaptureParser.parse(
        input, lists: lists, todayWeekday: 5, today: "2026-10-08", languages: languages)
      let elapsed = start.duration(to: clock.now)
      let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
      findings.parses += 1
      findings.noteTime(seconds, input)
      if seconds > 1 { findings.add("slow-parse >1s", input) }
      check(input, parsed, findings: &findings)
    }

    for (key, group) in byLanguage.sorted(by: { $0.key < $1.key }) {
      let languages = key.split(separator: ",").map(String.init)
      for seed in group.shuffled(using: &rng).prefix(perLanguage) {
        run(seed.text, languages: languages)
        for (_, mutated) in mutations(of: seed.text, rng: &rng) { run(mutated, languages: languages) }
      }
    }
    // Canonical equivalence: a line typed decomposed reads as the same line typed precomposed. Only
    // under FUZZ_NFD: the parser reads detail words typed with a separate combining accent as
    // unread (each language suite pins it), so the check reports those until that changes.
    var nfdChecked = 0
    var nfdDiffByLanguage: [String: Int] = [:]
    for (key, group) in byLanguage.sorted(by: { $0.key < $1.key })
    where ProcessInfo.processInfo.environment["FUZZ_NFD"] != nil {
      let languages = key.split(separator: ",").map(String.init)
      for seed in group.shuffled(using: &rng).prefix(perLanguage * 3) {
        let decomposed = seed.text.decomposedStringWithCanonicalMapping
        guard Array(decomposed.unicodeScalars) != Array(seed.text.unicodeScalars) else { continue }
        nfdChecked += 1
        func parse(_ text: String) -> LorvexCaptureParse {
          LorvexCaptureParser.parse(
            text, lists: lists, todayWeekday: 5, today: "2026-10-08", languages: languages)
        }
        if fingerprint(parse(seed.text)) != fingerprint(parse(decomposed)) {
          findings.add("nfd-differs \(key)", "\(seed.text) || \(decomposed.unicodeScalars.map { String($0.value, radix: 16) }.joined(separator: " "))")
          nfdDiffByLanguage[key, default: 0] += 1
        }
      }
    }
    print("NFD checked=\(nfdChecked) differing=\(nfdDiffByLanguage)")
    // Every language's vocabulary at once, over a sample of the whole corpus.
    for seed in seeds.shuffled(using: &rng).prefix(perLanguage * 4) {
      for (_, mutated) in mutations(of: seed.text, rng: &rng).prefix(6) { run(mutated, languages: allLanguages) }
    }

    var report = ["parses=\(findings.parses) seeds=\(seeds.count) maxOffset=\(findings.maxOffset) (\(findings.maxOffsetInput))"]
    for (kind, count) in findings.counts.sorted(by: { $0.key < $1.key }) {
      report.append("FINDING \(kind): \(count)")
      for example in findings.examples[kind] ?? [] { report.append("    \(example.debugDescription)") }
    }
    report.append("slowest:")
    for (seconds, input) in findings.slowest.prefix(8) {
      report.append("    \(String(format: "%.3f", seconds)) s  \(input.debugDescription.prefix(120))")
    }
    try report.joined(separator: "\n").write(toFile: findingsPath, atomically: true, encoding: .utf8)
    print("FUZZSUMMARY\n" + report.joined(separator: "\n"))
    #expect(findings.counts.isEmpty, "findings: \(findings.counts)")
  }
}

/// Prints, per language, corpus lines whose length phrase spells hours and minutes with digits, so a
/// regression test can swap huge numbers into known-good lines. Run with FUZZ_SAMPLES=1.
@Suite("Capture parser length samples", .serialized)
struct ZZCaptureParserLengthSamples {
  @Test(
    "print length samples",
    .enabled(if: ProcessInfo.processInfo.environment["FUZZ_SAMPLES"] != nil))
  func samples() throws {
    let seeds = loadSeeds()
    var lines: [String] = []
    var perKey: [String: Int] = [:]
    for seed in seeds {
      let language = seed.languages.joined(separator: ",")
      guard seed.text.utf8.allSatisfy({ $0 < 128 }) == false || seed.text.contains(where: \.isNumber) else { continue }
      let parsed = LorvexCaptureParser.parse(
        seed.text, lists: lists, todayWeekday: 5, today: "2026-10-08", languages: seed.languages)
      guard let length = parsed.phrases.first(where: { $0.kind == .length }), parsed.estimatedMinutes != nil
      else { continue }
      var runs = 0
      var inRun = false
      for s in length.text.unicodeScalars {
        let isDigit = s.properties.numericType == .decimal
        if isDigit, !inRun { runs += 1 }
        inRun = isDigit
      }
      guard runs >= 1 else { continue }
      let kind = "\(language) runs=\(min(runs, 2))"
      if perKey[kind, default: 0] >= 2 { continue }
      perKey[kind, default: 0] += 1
      lines.append("SAMPLE\t\(kind)\t\(seed.text)\t\(length.text)\t\(parsed.estimatedMinutes ?? -1)")
    }
    try lines.joined(separator: "\n").write(
      toFile: scratch + "/length_samples.txt", atomically: true, encoding: .utf8)
    print("SAMPLES written: \(lines.count)")
  }
}

/// Prints the whole parse of FUZZ_INPUT (languages from FUZZ_LANG, comma separated; every language
/// when unset) as `SHOW` lines, and the scalars of each phrase. Run with FUZZ_SHOW=1.
@Suite("Capture parser show", .serialized)
struct ZZCaptureParserShow {
  @Test(
    "print one parse",
    .enabled(if: ProcessInfo.processInfo.environment["FUZZ_SHOW"] != nil))
  func show() {
    let env = ProcessInfo.processInfo.environment
    let input = env["FUZZ_INPUT"] ?? ""
    let languages = env["FUZZ_LANG"].map { $0.split(separator: ",").map(String.init) } ?? allLanguages
    let parsed = LorvexCaptureParser.parse(
      input, lists: lists, todayWeekday: 5, today: "2026-10-08", languages: languages)
    print("SHOW input=\(input.debugDescription)")
    print("SHOW title=\(parsed.title.debugDescription)")
    print("SHOW planned=\(String(describing: parsed.plannedDayOffset)) due=\(String(describing: parsed.dueDayOffset)) estimate=\(String(describing: parsed.estimatedMinutes)) start=\(String(describing: parsed.startMinutes))")
    for phrase in parsed.phrases {
      print("SHOW phrase \(phrase.kind) \(phrase.text.debugDescription)")
    }
  }
}
