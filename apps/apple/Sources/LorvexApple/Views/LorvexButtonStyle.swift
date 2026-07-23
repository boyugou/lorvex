import LorvexCore
import SwiftUI

/// The app's unified action-button look: a soft rounded capsule in one of three
/// emphasis tiers, with a gentle hover wash and press scale. Replaces the grab
/// bag of stock `.bordered` / `.borderedProminent` buttons so every action reads
/// as part of the same family (and matches `LorvexSegmentedControl` and the
/// capsule chips).
///
/// - `primary`: the main affirmative action — filled accent, white label.
/// - `secondary`: supporting actions — a soft accent-tinted capsule.
/// - `neutral`: low-emphasis / utility — a quiet quaternary capsule.
///
/// Deliberate exception: the Settings panes and the onboarding wizard keep the
/// stock `.bordered` / `.borderedProminent` styles. Those surfaces read as
/// system-standard configuration sheets, where the native button look is the
/// expected affordance — the capsule family is for the app's own workspaces.
struct LorvexButtonStyle: ButtonStyle {
  enum Tier { case primary, secondary, neutral }

  var tier: Tier = .secondary

  func makeBody(configuration: Configuration) -> some View {
    StyledLabel(tier: tier, configuration: configuration)
  }

  private struct StyledLabel: View {
    let tier: Tier
    let configuration: Configuration
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
      configuration.label
        .font(LorvexDesign.Typography.secondaryText.weight(.medium))
        .foregroundStyle(foreground)
        .padding(.horizontal, LorvexDesign.Spacing.m)
        .padding(.vertical, 6)
        .background(background, in: Capsule())
        .overlay {
          if tier == .neutral {
            Capsule().strokeBorder(.separator.opacity(0.5), lineWidth: 0.5)
          }
        }
        .contentShape(Capsule())
        .opacity(isEnabled ? 1 : 0.45)
        .scaleEffect(configuration.isPressed ? 0.97 : 1)
        .reduceMotionAnimation(.snappy(duration: 0.12), value: configuration.isPressed)
        .onHover { hovering = $0 }
    }

    private var foreground: AnyShapeStyle {
      switch tier {
      case .primary: AnyShapeStyle(.white)
      case .secondary: AnyShapeStyle(Color.accentColor)
      case .neutral: AnyShapeStyle(.secondary)
      }
    }

    private var background: AnyShapeStyle {
      switch tier {
      case .primary:
        AnyShapeStyle(Color.accentColor.opacity(hovering && isEnabled ? 0.85 : 1))
      case .secondary:
        AnyShapeStyle(Color.accentColor.opacity(hovering && isEnabled ? 0.22 : 0.13))
      case .neutral:
        AnyShapeStyle(Color.secondary.opacity(hovering && isEnabled ? 0.18 : 0.10))
      }
    }
  }
}

extension ButtonStyle where Self == LorvexButtonStyle {
  /// Main affirmative action — filled accent capsule.
  static var lorvexPrimary: LorvexButtonStyle { LorvexButtonStyle(tier: .primary) }
  /// Supporting action — soft accent-tinted capsule.
  static var lorvexSecondary: LorvexButtonStyle { LorvexButtonStyle(tier: .secondary) }
  /// Low-emphasis utility — quiet quaternary capsule.
  static var lorvexNeutral: LorvexButtonStyle { LorvexButtonStyle(tier: .neutral) }

  static func lorvex(_ tier: LorvexButtonStyle.Tier) -> LorvexButtonStyle {
    LorvexButtonStyle(tier: tier)
  }
}
