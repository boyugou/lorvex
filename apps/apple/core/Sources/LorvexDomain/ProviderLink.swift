/// Canonical validation for task-provider calendar link composite-key fields.
///
/// `provider_kind` / `provider_scope` / `provider_event_key` are a composite
/// SQL key shared by every provider-link writer (the MCP host, platform
/// surfaces, and sync apply). Human/agent-facing trust-boundary writers sanitize
/// through this module so provider-kind allowlists, empty-field policy, and
/// short-text caps do not drift per surface.
public struct ProviderLinkFields: Sendable, Equatable {
  public var providerKind: String
  public var providerScope: String
  public var providerEventKey: String

  public init(providerKind: String, providerScope: String, providerEventKey: String) {
    self.providerKind = providerKind
    self.providerScope = providerScope
    self.providerEventKey = providerEventKey
  }
}

public enum ProviderLink {
  /// Per-field cap is ``ValidationLimits/maxShortTextLength``.
  public static let maxFieldLength = ValidationLimits.maxShortTextLength

  /// Sanitize + trim, then enforce non-empty and the short-text scalar cap.
  public static func normalizeRequiredField(_ value: String, field: String)
    -> Result<String, ValidationError>
  {
    let normalized = UnicodeHygiene.sanitizeUserText(value)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    if normalized.isEmpty {
      return .failure(.empty(field))
    }
    let actual = normalized.unicodeScalars.count
    if actual > maxFieldLength {
      return .failure(.tooLong(field: field, max: maxFieldLength, actual: actual))
    }
    return .success(normalized)
  }

  /// Scope may be empty (single-scope providers like EventKit). Enforces only
  /// the short-text scalar cap.
  public static func normalizeScope(_ value: String) -> Result<String, ValidationError> {
    let normalized = UnicodeHygiene.sanitizeUserText(value)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let actual = normalized.unicodeScalars.count
    if actual > maxFieldLength {
      return .failure(.tooLong(field: "provider_scope", max: maxFieldLength, actual: actual))
    }
    return .success(normalized)
  }

  /// Normalize all three composite-key fields; enforces the provider-kind
  /// allowlist with the canonical error wording.
  public static func normalizeFields(
    providerKind: String, providerScope: String, providerEventKey: String
  ) -> Result<ProviderLinkFields, ValidationError> {
    let kindResult = normalizeRequiredField(providerKind, field: "provider_kind")
    let kind: String
    switch kindResult {
    case .failure(let e): return .failure(e)
    case .success(let v): kind = v
    }
    if !ProviderKind.isAllowedProviderKind(kind) {
      return .failure(
        .message(
          "provider_kind '\(kind)' is not in the allowlist; expected one of: "
            + ProviderKind.allowlistDisplay()))
    }
    let scopeResult = normalizeScope(providerScope)
    let scope: String
    switch scopeResult {
    case .failure(let e): return .failure(e)
    case .success(let v): scope = v
    }
    let keyResult = normalizeRequiredField(providerEventKey, field: "provider_event_key")
    let key: String
    switch keyResult {
    case .failure(let e): return .failure(e)
    case .success(let v): key = v
    }
    return .success(
      ProviderLinkFields(providerKind: kind, providerScope: scope, providerEventKey: key))
  }
}
