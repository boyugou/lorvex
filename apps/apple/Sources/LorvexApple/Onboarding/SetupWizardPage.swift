import LorvexCore
import SwiftUI

/// The frame every first-run page shares, so nothing the eye follows moves
/// when the page turns: a tinted icon badge and a title anchored at one
/// height under the step dots, with the page's subtitle under them when it
/// has one; the page's own content next (feature rows, or the permission
/// rows); and the page's buttons anchored at the bottom of the sheet.
struct SetupWizardPage<Content: View, Actions: View>: View {
  let systemImage: String
  let iconTint: Color
  let title: LocalizedStringResource
  let subtitle: LocalizedStringResource?
  let content: Content
  let actions: Actions

  init(
    systemImage: String,
    iconTint: Color = .accentColor,
    title: LocalizedStringResource,
    subtitle: LocalizedStringResource? = nil,
    @ViewBuilder content: () -> Content,
    @ViewBuilder actions: () -> Actions
  ) {
    self.systemImage = systemImage
    self.iconTint = iconTint
    self.title = title
    self.subtitle = subtitle
    self.content = content()
    self.actions = actions()
  }

  var body: some View {
    VStack(spacing: 0) {
      badge
      Text(title)
        .font(LorvexDesign.Typography.screenTitle)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.top, LorvexDesign.Spacing.l)
      if let subtitle {
        Text(subtitle)
          .font(LorvexDesign.Typography.secondaryText)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: 380)
          .padding(.top, LorvexDesign.Spacing.s)
      }
      content
        .padding(.top, LorvexDesign.Spacing.l)
      Spacer(minLength: LorvexDesign.Spacing.m)
      HStack(spacing: LorvexDesign.Spacing.s) { actions }
        .controlSize(.large)
    }
    .padding(.horizontal, 40)
    .padding(.vertical, LorvexDesign.Spacing.xl)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var badge: some View {
    Image(systemName: systemImage)
      .resizable()
      .scaledToFit()
      .fontWeight(.semibold)
      .foregroundStyle(iconTint)
      .frame(width: 28, height: 28)
      .frame(width: 60, height: 60)
      .background(
        iconTint.opacity(0.12),
        in: RoundedRectangle(cornerRadius: LorvexDesign.Radius.card, style: .continuous)
      )
      .accessibilityHidden(true)
  }
}

/// The points a first-run page makes, one ``SetupWizardFeatureRow`` each,
/// in a left-aligned column narrower than the sheet and centered in it, so
/// every line stays short enough to read at a glance.
struct SetupWizardFeatureList<Rows: View>: View {
  let rows: Rows

  init(@ViewBuilder rows: () -> Rows) {
    self.rows = rows()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.l) { rows }
      .frame(maxWidth: 400, alignment: .leading)
  }
}

/// One point a first-run page makes: a tinted symbol beside a short title
/// and a line that explains it, read by VoiceOver as one element.
struct SetupWizardFeatureRow: View {
  let systemImage: String
  let title: LocalizedStringResource
  let detail: LocalizedStringResource

  var body: some View {
    HStack(spacing: LorvexDesign.Spacing.m) {
      Image(systemName: systemImage)
        .font(LorvexDesign.Typography.screenTitle)
        .foregroundStyle(.tint)
        .frame(width: 32)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xxs) {
        Text(title)
          .font(LorvexDesign.Typography.primaryEmphasis)
        Text(detail)
          .font(LorvexDesign.Typography.secondaryText)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .accessibilityElement(children: .combine)
  }
}

/// A page's main action: the prominent button, which Return also presses.
struct SetupWizardPrimaryButton: View {
  let title: String
  let action: () -> Void

  init(_ title: String, action: @escaping () -> Void) {
    self.title = title
    self.action = action
  }

  var body: some View {
    Button(title, action: action)
      .buttonStyle(.borderedProminent)
      .keyboardShortcut(.defaultAction)
  }
}
