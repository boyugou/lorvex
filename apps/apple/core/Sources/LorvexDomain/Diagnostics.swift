import Foundation

/// Diagnostic-text redaction shared across the MCP host and platform surfaces.
///
/// Error messages, stack traces, and HTTP response fragments that land in
/// `error_logs` or `ai_changelog` summaries can incidentally contain access
/// tokens, bearer authorization headers, `sk_…`/`AKIA…`-style API keys, and
/// JSON-serialized password / token fields. These live alongside genuinely
/// diagnostic content (file paths, task ids, HTTP status codes) and need to
/// survive persistence long enough to show up in Settings → Diagnostics —
/// but must not ship out of the machine in a copy-to-clipboard bug report.
public enum Diagnostics {
  /// Redact bearer tokens, API-key-prefixed strings, `key=value` /
  /// `"key":"value"` secret patterns, emails, and home directory path
  /// fragments in a free-form diagnostic string. Whitespace-token level;
  /// safe to apply to any user-facing string; preserves enough structure
  /// to remain useful for triage.
  public static func redactDiagnosticText(_ value: String) -> String {
    let kvKeys = ["password", "passwd", "secret", "token", "api_key", "api-key"]

    var out = ""
    out.reserveCapacity(value.count)
    var skipNextBearerValue = false
    var skipNextKvValue = false
    var first = true

    func pushSep() {
      if first { first = false } else { out.append(" ") }
    }

    for token in value.split(whereSeparator: { $0.isWhitespace }).map(String.init) {
      if skipNextBearerValue {
        skipNextBearerValue = false
        continue
      }
      if skipNextKvValue {
        skipNextKvValue = false
        continue
      }
      let lower = token.lowercased()
      if lower == "bearer" {
        pushSep()
        out.append("Bearer [REDACTED]")
        skipNextBearerValue = true
        continue
      }
      if lower.hasPrefix("bearer:") || lower.hasPrefix("bearer=") {
        pushSep()
        out.append("Bearer [REDACTED]")
        continue
      }
      if lower.hasPrefix("authorization:bearer") || lower.hasPrefix("authorization=bearer") {
        pushSep()
        out.append("Authorization: Bearer [REDACTED]")
        if lower == "authorization:bearer" || lower == "authorization=bearer" {
          skipNextBearerValue = true
        }
        continue
      }
      // Colon-delimited secret kv: `token:value` (attached) or `token: value`
      // (space-delimited, secret in the following whitespace token). The
      // `key=value` and `"key":"value"` forms are handled by the byte-level scan
      // below.
      if let colonKey = kvKeys.first(where: { lower.hasPrefix($0 + ":") }) {
        pushSep()
        out.append("\(colonKey): [REDACTED]")
        if lower.count == colonKey.count + 1 {
          skipNextKvValue = true
        }
        continue
      }
      if hasSecretTokenPrefix(token) {
        pushSep()
        out.append("[REDACTED_TOKEN]")
        continue
      }
      if tokenIsJWTLike(token) {
        pushSep()
        out.append("[REDACTED_TOKEN]")
        continue
      }
      if let redacted = redactHttpUrl(token) {
        pushSep()
        out.append(redacted)
        continue
      }
      var maskedKvSecret = false
      let lowerBytes = Array(lower.utf8)
      let tokenBytes = Array(token.utf8)
      for key in kvKeys {
        let keyBytes = Array(key.utf8)
        var start = 0
        while let rel = findSubsequence(in: lowerBytes, key: keyBytes, from: start) {
          let pos = rel
          let after = pos + keyBytes.count
          // `key=` form
          if after < lowerBytes.count, lowerBytes[after] == UInt8(ascii: "=") {
            // prefix = portion of token before the first '='
            let prefix = String(decoding: tokenBytes.prefix { $0 != UInt8(ascii: "=") }, as: UTF8.self)
            pushSep()
            out.append(prefix.isEmpty ? "secret" : prefix)
            out.append("=[REDACTED]")
            maskedKvSecret = true
            break
          }
          // `"key":` form
          if pos > 0,
            lowerBytes[pos - 1] == UInt8(ascii: "\""),
            after + 1 < lowerBytes.count,
            lowerBytes[after] == UInt8(ascii: "\""),
            lowerBytes[after + 1] == UInt8(ascii: ":")
          {
            pushSep()
            out.append("[REDACTED_JSON_SECRET]")
            maskedKvSecret = true
            break
          }
          start = pos + keyBytes.count
        }
        if maskedKvSecret { break }
      }
      if maskedKvSecret { continue }
      if tokenIsEmailLike(token) {
        pushSep()
        out.append("[REDACTED_EMAIL]")
        continue
      }
      if let redacted = redactHomePath(token) {
        pushSep()
        out.append(redacted)
        continue
      }
      pushSep()
      out.append(token)
    }
    return out
  }

  /// Distinctive prefixes of vendor API keys / tokens that must never persist in
  /// a diagnostic string: Stripe (`sk_`/`rk_`/`pk_`), OpenAI + Anthropic (`sk-…`,
  /// including `sk-ant-…`), GitHub (`ghp_`, `github_pat_`), AWS (`AKIA`), Google
  /// (`AIza`), and Slack (`xoxb-`/`xoxp-`).
  static func hasSecretTokenPrefix(_ token: String) -> Bool {
    let prefixes = [
      "sk_", "rk_", "pk_",
      "sk-",
      "ghp_", "github_pat_",
      "AKIA",
      "AIza",
      "xoxb-", "xoxp-",
    ]
    return prefixes.contains(where: token.hasPrefix)
  }

  /// A bare JSON Web Token: an `eyJ`-prefixed header plus two more
  /// `.`-separated base64url segments (`header.payload.signature`). Matched
  /// conservatively — exactly three non-empty base64url parts — so ordinary
  /// dotted identifiers are not redacted.
  static func tokenIsJWTLike(_ token: String) -> Bool {
    guard token.hasPrefix("eyJ") else { return false }
    let parts = token.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count == 3 else { return false }
    for part in parts {
      if part.isEmpty { return false }
      for c in part {
        let ok = c.isASCII && (c.isLetter || c.isNumber || c == "-" || c == "_" || c == "=")
        if !ok { return false }
      }
    }
    return true
  }

  /// Find `key` as a contiguous subsequence of `haystack` starting at or
  /// after index `from`. Byte-level (UTF-8) over ASCII KV keys.
  static func findSubsequence(in haystack: [UInt8], key: [UInt8], from: Int) -> Int? {
    guard !key.isEmpty, haystack.count >= key.count + from else {
      return key.isEmpty && from <= haystack.count ? from : nil
    }
    let limit = haystack.count - key.count
    var i = from
    while i <= limit {
      var j = 0
      while j < key.count && haystack[i + j] == key[j] {
        j += 1
      }
      if j == key.count { return i }
      i += 1
    }
    return nil
  }

  static func tokenIsEmailLike(_ token: String) -> Bool {
    guard let at = token.firstIndex(of: "@") else { return false }
    let local = token[..<at]
    let host = token[token.index(after: at)...]
    if local.isEmpty || host.isEmpty { return false }
    if host.contains("@") { return false }
    guard host.contains(".") else { return false }
    guard let lastChar = host.last, lastChar.isASCII,
      (lastChar.isLetter || lastChar.isNumber)
    else { return false }
    for c in local {
      let ok = c.isASCII && (c.isLetter || c.isNumber || c == "." || c == "_" || c == "+" || c == "-")
      if !ok { return false }
    }
    return true
  }

  static func redactHomePath(_ token: String) -> String? {
    // POSIX home prefixes
    for prefix in ["/Users/", "/home/"] {
      if let rest = stripPrefix(token, prefix) {
        return formatHomeRedaction(rest: rest, separators: ["/"])
      }
    }
    // Windows: forward or backslash separators after the prefix.
    for prefix in ["C:\\Users\\", "c:\\Users\\", "C:/Users/", "c:/Users/"] {
      if let rest = stripPrefix(token, prefix) {
        return formatHomeRedaction(rest: rest, separators: ["\\", "/"])
      }
    }
    return nil
  }

  static func stripPrefix(_ s: String, _ p: String) -> String? {
    if s.hasPrefix(p) {
      return String(s.dropFirst(p.count))
    }
    return nil
  }

  static func formatHomeRedaction(rest: String, separators: [Character]) -> String {
    // Find first occurrence of any separator; tail is everything after it.
    var splitIndex: String.Index? = nil
    for ch in rest.indices {
      if separators.contains(rest[ch]) {
        splitIndex = ch
        break
      }
    }
    guard let split = splitIndex else {
      // No separator: rest is entirely the user component → just `[~]`.
      return "[~]"
    }
    let tail = String(rest[rest.index(after: split)...])
    return tail.isEmpty ? "[~]" : "[~]/\(tail)"
  }

  /// Mask the query string and userinfo of an http(s) URL while preserving
  /// scheme + host + path + any trailing punctuation.
  static func redactHttpUrl(_ token: String) -> String? {
    let scheme: String
    let restBody: String
    if let r = stripPrefix(token, "http://") {
      scheme = "http://"
      restBody = r
    } else if let r = stripPrefix(token, "https://") {
      scheme = "https://"
      restBody = r
    } else {
      return nil
    }
    // Separate trailing punctuation.
    let trailingPuncts: Set<Character> = [".", ",", ")", "]", ">", "\"", "'", ";"]
    var bodyChars = Array(restBody)
    var trailing = ""
    while let last = bodyChars.last, trailingPuncts.contains(last) {
      trailing = String(last) + trailing
      bodyChars.removeLast()
    }
    let body = String(bodyChars)
    if body.isEmpty { return nil }
    // Split off fragment first.
    let beforeFragment: String
    if let hash = body.firstIndex(of: "#") {
      beforeFragment = String(body[..<hash])
    } else {
      beforeFragment = body
    }
    let hadQuery = beforeFragment.contains("?")
    let beforeQuery: String
    if let q = beforeFragment.firstIndex(of: "?") {
      beforeQuery = String(beforeFragment[..<q])
    } else {
      beforeQuery = beforeFragment
    }
    // Userinfo: everything up to the first `@` BEFORE the first `/` counts.
    let pathStart = beforeQuery.firstIndex(of: "/") ?? beforeQuery.endIndex
    let authority = String(beforeQuery[..<pathStart])
    let path = String(beforeQuery[pathStart...])
    let maskedAuthority: String
    if let atIdx = authority.lastIndex(of: "@") {
      let host = authority[authority.index(after: atIdx)...]
      maskedAuthority = "[REDACTED_USERINFO]@\(host)"
    } else {
      maskedAuthority = authority
    }
    var out = scheme + maskedAuthority + path
    if hadQuery {
      out += "?[REDACTED_QUERY]"
    }
    out += trailing
    return out
  }
}
