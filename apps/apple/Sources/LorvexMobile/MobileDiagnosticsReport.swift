import Foundation
import LorvexCore

/// The diagnostics feed as plain text for a bug report: one header line
/// naming the app build, the system and the device model, then every entry
/// newest first with its full detail.
///
/// The text is English and unlocalized, like the entries themselves: it is
/// read by whoever investigates the report. It holds what the feed shows and
/// nothing else, so the detail lines are the sanitized ones.
enum MobileDiagnosticsReport {
  static func text(
    entries: [RecentLogEntry], appVersion: String, build: String, system: String, model: String
  ) -> String {
    var lines = ["Lorvex \(appVersion) (\(build)) · \(system) · \(model)"]
    lines.append(entries.count == 1 ? "1 entry" : "\(entries.count) entries, newest first")
    for entry in entries {
      lines.append("")
      let heading = [entry.timestamp, entry.level.rawValue, entry.origin ?? entry.source]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
      lines.append(heading.joined(separator: "  "))
      lines.append(entry.summary)
      if let details = entry.details, !details.isEmpty {
        lines.append(details)
      }
    }
    return lines.joined(separator: "\n")
  }

  /// The report for this process: the running app's version and build, the
  /// system's own version string, and the hardware model identifier.
  static func text(entries: [RecentLogEntry]) -> String {
    let info = Bundle.main
    return text(
      entries: entries,
      appVersion: info.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?",
      build: info.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?",
      system: ProcessInfo.processInfo.operatingSystemVersionString,
      model: hardwareModel)
  }

  private static var hardwareModel: String {
    var system = utsname()
    uname(&system)
    return withUnsafeBytes(of: &system.machine) { bytes in
      String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
    }
  }
}
