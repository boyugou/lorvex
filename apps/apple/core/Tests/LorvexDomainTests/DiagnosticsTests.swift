import XCTest

@testable import LorvexDomain

final class DiagnosticsTests: XCTestCase {
  func testRedactsWhitespaceSeparatedBearerToken() {
    let s = "GET /api failed: Authorization: Bearer eyJhbGciOi...xyz server=unreachable"
    let out = Diagnostics.redactDiagnosticText(s)
    XCTAssertFalse(out.contains("eyJhbGci"))
    XCTAssertTrue(out.contains("[REDACTED]"))
    XCTAssertTrue(out.contains("server=unreachable"))
  }

  func testRedactsInlineBearerColonValue() {
    let s = "header bearer:eyJhbGci.xyz more"
    let out = Diagnostics.redactDiagnosticText(s)
    XCTAssertFalse(out.contains("eyJhbGci"))
    XCTAssertTrue(out.contains("Bearer [REDACTED]"))
  }

  func testRedactsApiKeyPrefixes() {
    let out = Diagnostics.redactDiagnosticText("failed with sk_live_abcdef and AKIAEXAMPLE123")
    XCTAssertFalse(out.contains("sk_live_abcdef"))
    XCTAssertFalse(out.contains("AKIAEXAMPLE123"))
    XCTAssertEqual(
      out.components(separatedBy: "[REDACTED_TOKEN]").count - 1, 2)
  }

  func testRedactsJsonSecretFields() {
    let s = #"response: {"token":"abc","password":"pw","user":"alice"}"#
    let out = Diagnostics.redactDiagnosticText(s)
    XCTAssertFalse(out.contains("abc"))
    XCTAssertFalse(out.contains(#""password":"pw""#))
    XCTAssertTrue(out.contains("[REDACTED_JSON_SECRET]"))
  }

  func testRedactsKvPassword() {
    let out = Diagnostics.redactDiagnosticText("ssh password=hunter2 failed")
    XCTAssertFalse(out.contains("hunter2"))
    XCTAssertTrue(out.contains("password=[REDACTED]"))
  }

  func testPreservesSafeContent() {
    let out = Diagnostics.redactDiagnosticText("task id 018fef8c failed on line 42")
    XCTAssertEqual(out, "task id 018fef8c failed on line 42")
  }

  func testRedactsEmailAddresses() {
    let out = Diagnostics.redactDiagnosticText(
      "login failed for alice@example.com retrying with bob+tag@mail.example.co.uk")
    XCTAssertFalse(out.contains("alice@"))
    XCTAssertFalse(out.contains("bob+tag@"))
    XCTAssertEqual(out.components(separatedBy: "[REDACTED_EMAIL]").count - 1, 2)
  }

  func testDoesNotRedactAtMentionsOrKeysAsEmail() {
    let out = Diagnostics.redactDiagnosticText("ping @alice failed key@value=1 a@b missing")
    XCTAssertTrue(out.contains("@alice"))
    XCTAssertTrue(out.contains("key@value=1"))
    XCTAssertTrue(out.contains("a@b"))
    XCTAssertFalse(out.contains("[REDACTED_EMAIL]"))
  }

  func testRedactsMacosHomePath() {
    let out = Diagnostics.redactDiagnosticText(
      "failed at /Users/alex/Library/Application/db.sqlite reading line 42")
    XCTAssertFalse(out.contains("/Users/alex/"))
    XCTAssertTrue(out.contains("[~]/Library/Application/db.sqlite"))
  }

  func testRedactsLinuxHomePath() {
    let out = Diagnostics.redactDiagnosticText("at /home/alice/.local/share/file.db line 12")
    XCTAssertFalse(out.contains("/home/alice/"))
    XCTAssertTrue(out.contains("[~]/.local/share/file.db"))
  }

  func testRedactsWindowsHomePathBothSeparators() {
    let forward = Diagnostics.redactDiagnosticText(#"at C:/Users/Alex/AppData/log.txt line 1"#)
    XCTAssertFalse(forward.contains("Users/Alex"))
    XCTAssertTrue(forward.contains("[~]/AppData/log.txt"))
    let back = Diagnostics.redactDiagnosticText(#"at C:\Users\Alex\AppData\log.txt line 1"#)
    XCTAssertFalse(back.contains("Users\\Alex"))
    XCTAssertTrue(back.contains(#"[~]/AppData\log.txt"#))
  }

  func testPreservesNonHomeAbsolutePaths() {
    let out = Diagnostics.redactDiagnosticText("wrote /tmp/cache/file.blob to disk")
    XCTAssertEqual(out, "wrote /tmp/cache/file.blob to disk")
  }

  func testRedactsUrlQueryStringTokens() {
    let out = Diagnostics.redactDiagnosticText(
      "HTTP 401: https://p123-caldav.icloud.com/published/2/MTg4?token=ABCDEF fetch failed")
    XCTAssertFalse(out.contains("token=ABCDEF"))
    XCTAssertFalse(out.contains("?token"))
    XCTAssertTrue(out.contains("[REDACTED_QUERY]"))
    XCTAssertTrue(out.contains("p123-caldav.icloud.com"))
  }

  func testRedactsUrlUserinfo() {
    let out = Diagnostics.redactDiagnosticText(
      "connect failed https://alice:hunter2@calendar.example/ics")
    XCTAssertFalse(out.contains("alice:hunter2"))
    XCTAssertTrue(out.contains("[REDACTED_USERINFO]@calendar.example/ics"))
  }

  func testPreservesBareUrlWithoutQuery() {
    let out = Diagnostics.redactDiagnosticText("redirect to https://example.com/path/feed.ics now")
    XCTAssertTrue(out.contains("https://example.com/path/feed.ics"))
    XCTAssertFalse(out.contains("[REDACTED_QUERY]"))
  }

  func testPreservesTrailingPunctuationOnUrls() {
    let out = Diagnostics.redactDiagnosticText("saw https://example.com/a?token=xyz. retry please")
    XCTAssertTrue(out.contains("[REDACTED_QUERY]."))
    XCTAssertTrue(out.contains("retry please"))
  }

  func testRedactsHyphenatedOpenAIAnthropicKeys() {
    let out = Diagnostics.redactDiagnosticText(
      "openai sk-proj-ABC123 anthropic sk-ant-api03-XYZ failed")
    XCTAssertFalse(out.contains("sk-proj-ABC123"))
    XCTAssertFalse(out.contains("sk-ant-api03-XYZ"))
    XCTAssertEqual(out.components(separatedBy: "[REDACTED_TOKEN]").count - 1, 2)
  }

  func testRedactsGitHubTokens() {
    let out = Diagnostics.redactDiagnosticText(
      "push failed ghp_abcDEF123 and github_pat_11ABCXYZ ok")
    XCTAssertFalse(out.contains("ghp_abcDEF123"))
    XCTAssertFalse(out.contains("github_pat_11ABCXYZ"))
    XCTAssertEqual(out.components(separatedBy: "[REDACTED_TOKEN]").count - 1, 2)
  }

  func testRedactsGoogleAndSlackTokens() {
    let out = Diagnostics.redactDiagnosticText("google AIzaSyABCDEF slack xoxb-123-456-abc done")
    XCTAssertFalse(out.contains("AIzaSyABCDEF"))
    XCTAssertFalse(out.contains("xoxb-123-456-abc"))
    XCTAssertEqual(out.components(separatedBy: "[REDACTED_TOKEN]").count - 1, 2)
  }

  func testRedactsBareJWT() {
    let jwt = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0In0.SflKxwRJSMeKKF2QT4fwpMeJf36"
    let out = Diagnostics.redactDiagnosticText("auth token \(jwt) rejected")
    XCTAssertFalse(out.contains(jwt))
    XCTAssertTrue(out.contains("[REDACTED_TOKEN]"))
    XCTAssertTrue(out.contains("auth token"))
    XCTAssertTrue(out.contains("rejected"))
  }

  func testDoesNotRedactDottedNonJWTIdentifiers() {
    let out = Diagnostics.redactDiagnosticText("module.submodule.function threw at 12.34.56")
    XCTAssertEqual(out, "module.submodule.function threw at 12.34.56")
  }

  func testRedactsSpaceDelimitedTokenColonValue() {
    let out = Diagnostics.redactDiagnosticText("request failed token: abc123secret retry")
    XCTAssertFalse(out.contains("abc123secret"))
    XCTAssertTrue(out.contains("token: [REDACTED]"))
    XCTAssertTrue(out.contains("retry"))
  }

  func testRedactsAttachedSecretColonValue() {
    let out = Diagnostics.redactDiagnosticText("header secret:hunter2 sent")
    XCTAssertFalse(out.contains("hunter2"))
    XCTAssertTrue(out.contains("secret: [REDACTED]"))
    XCTAssertTrue(out.contains("sent"))
  }
}
