import AppKit
import LorvexCore
import SwiftUI

extension SettingsView {
  var appearanceSection: some View {
    Section(String(localized: "settings.section.appearance", defaultValue: "Appearance", table: "Localizable", bundle: LorvexL10n.bundle)) {
      AppearanceThumbnailPicker(selection: $settings.appearance)
      Text(LocalizedStringResource(
        "settings.appearance.footer",
        defaultValue: "System follows your macOS Light/Dark setting; Light and Dark force that appearance everywhere in Lorvex.",
        table: "Localizable",
        bundle: LorvexL10n.bundle
      ))
        .font(LorvexDesign.Typography.tertiaryText)
        .foregroundStyle(.secondary)
    }
  }

  var languageSection: some View {
    Section(String(localized: "settings.section.language", defaultValue: "Language", table: "Localizable", bundle: LorvexL10n.bundle)) {
      Picker(
        String(localized: "settings.language", defaultValue: "Language", table: "Localizable", bundle: LorvexL10n.bundle),
        selection: $selectedLanguage
      ) {
        Text(String(
          localized: "settings.language.system", defaultValue: "System Default",
          table: "Localizable",
          bundle: LorvexL10n.bundle))
          .tag(AppLanguage.system)
        Divider()
        ForEach(AppLanguage.selectable) { language in
          Text(language.endonym).tag(language)
        }
      }
      .onChange(of: selectedLanguage) { _, newValue in
        newValue.apply()
        languageNeedsRelaunch = newValue != launchLanguage
      }

      if languageNeedsRelaunch {
        HStack {
          Text(LocalizedStringResource(
            "settings.language.relaunch_note",
            defaultValue: "Restart Lorvex to apply the new language.",
            table: "Localizable",
            bundle: LorvexL10n.bundle
          ))
            .font(LorvexDesign.Typography.tertiaryText)
            .foregroundStyle(.secondary)
          Spacer()
          Button(String(
            localized: "settings.language.relaunch", defaultValue: "Quit & Reopen",
            table: "Localizable",
            bundle: LorvexL10n.bundle
          )) {
            relaunchForLanguageChange()
          }
        }
      }
    }
  }

  /// Relaunch the app so the new `AppleLanguages` override is read at launch:
  /// spawn a fresh instance, then terminate the current one.
  private func relaunchForLanguageChange() {
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.createsNewApplicationInstance = true
    NSWorkspace.shared.openApplication(
      at: Bundle.main.bundleURL, configuration: configuration
    ) { _, _ in
      Task { @MainActor in NSApp.terminate(nil) }
    }
  }
}

private extension AppAppearance {
  var localizedSettingsLabel: String {
    switch self {
    case .system: String(localized: "settings.appearance.system", defaultValue: "System", table: "Localizable", bundle: LorvexL10n.bundle)
    case .light: String(localized: "settings.appearance.light", defaultValue: "Light", table: "Localizable", bundle: LorvexL10n.bundle)
    case .dark: String(localized: "settings.appearance.dark", defaultValue: "Dark", table: "Localizable", bundle: LorvexL10n.bundle)
    }
  }
}

/// A visual appearance picker: three tappable window-preview swatches (Light /
/// Dark / System) with a selection ring and label, so the choice reads by
/// preview rather than by word. Each swatch renders a fixed light or dark
/// mini-window regardless of the app's current scheme (System shows a diagonal
/// split of both). Keyboard- and VoiceOver-accessible; selection animates.
struct AppearanceThumbnailPicker: View {
  @Binding var selection: AppAppearance

  var body: some View {
    HStack(alignment: .top, spacing: LorvexDesign.Spacing.m) {
      ForEach(AppAppearance.allCases) { appearance in
        AppearanceSwatch(appearance: appearance, isSelected: selection == appearance) {
          lorvexAnimated(.snappy(duration: 0.18)) { selection = appearance }
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.vertical, LorvexDesign.Spacing.xs)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("settings.appearance.picker")
  }
}

private struct AppearanceSwatch: View {
  let appearance: AppAppearance
  let isSelected: Bool
  let onSelect: () -> Void
  @State private var hovering = false

  var body: some View {
    Button(action: onSelect) {
      VStack(spacing: LorvexDesign.Spacing.xs) {
        preview
          .frame(width: 76, height: 52)
          .clipShape(RoundedRectangle(cornerRadius: LorvexDesign.Radius.s, style: .continuous))
          .overlay {
            RoundedRectangle(cornerRadius: LorvexDesign.Radius.s, style: .continuous)
              .strokeBorder(
                isSelected
                  ? AnyShapeStyle(LorvexDesign.Palette.accent)
                  : AnyShapeStyle(.separator.opacity(hovering ? 0.9 : 0.5)),
                lineWidth: isSelected ? 2 : 0.5)
          }
          .overlay(alignment: .bottomTrailing) {
            if isSelected {
              Image(systemName: "checkmark.circle.fill")
                .font(LorvexDesign.Typography.secondaryText)
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, LorvexDesign.Palette.accent)
                .padding(3)
                .transition(.scale.combined(with: .opacity))
            }
          }
          .scaleEffect(hovering && !isSelected ? 1.03 : 1)

        Label(appearance.localizedSettingsLabel, systemImage: appearance.symbolName)
          .labelStyle(.titleAndIcon)
          .font(LorvexDesign.Typography.tertiaryText.weight(isSelected ? .semibold : .regular))
          .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover { inside in lorvexAnimated(.easeOut(duration: 0.14)) { hovering = inside } }
    .accessibilityIdentifier("settings.appearance.swatch.\(appearance.rawValue)")
    .accessibilityLabel(appearance.localizedSettingsLabel)
    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
  }

  @ViewBuilder
  private var preview: some View {
    switch appearance {
    case .light: AppearancePreviewCanvas(isDark: false)
    case .dark: AppearancePreviewCanvas(isDark: true)
    case .system: AppearanceSystemPreviewCanvas()
    }
  }
}

/// A miniature window used inside an appearance swatch: a title bar with three
/// traffic-light dots over a few content lines. Colors are hardcoded per scheme
/// (not the semantic palette) so the swatch always previews *that* scheme,
/// independent of the app's current appearance.
private struct AppearancePreviewCanvas: View {
  let isDark: Bool

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 3) {
        Circle().fill(Color.red.opacity(0.85)).frame(width: 5, height: 5)
        Circle().fill(Color.yellow.opacity(0.85)).frame(width: 5, height: 5)
        Circle().fill(Color.green.opacity(0.85)).frame(width: 5, height: 5)
        Spacer(minLength: 0)
      }
      .padding(.horizontal, 6)
      .frame(height: 14)
      .background(barColor)

      VStack(alignment: .leading, spacing: 4) {
        Capsule().fill(lineColor).frame(width: 34, height: 4)
        Capsule().fill(lineColor.opacity(0.6)).frame(width: 48, height: 4)
        Capsule().fill(lineColor.opacity(0.6)).frame(width: 40, height: 4)
      }
      .padding(6)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    .background(canvasColor)
  }

  private var canvasColor: Color {
    isDark ? Color(red: 0.11, green: 0.11, blue: 0.12) : Color(red: 0.97, green: 0.97, blue: 0.98)
  }

  private var barColor: Color {
    isDark ? Color.white.opacity(0.14) : Color.black.opacity(0.06)
  }

  private var lineColor: Color {
    isDark ? Color.white.opacity(0.22) : Color.black.opacity(0.16)
  }
}

/// The System swatch: a light canvas with the dark canvas masked to the
/// top-right triangle, plus a hairline diagonal seam — the platform-standard
/// "follows the system" split preview.
private struct AppearanceSystemPreviewCanvas: View {
  var body: some View {
    ZStack {
      AppearancePreviewCanvas(isDark: false)
      AppearancePreviewCanvas(isDark: true)
        .mask {
          GeometryReader { geo in
            Path { path in
              path.move(to: CGPoint(x: geo.size.width, y: 0))
              path.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height))
              path.addLine(to: CGPoint(x: 0, y: 0))
              path.closeSubpath()
            }
          }
        }
      GeometryReader { geo in
        Path { path in
          path.move(to: CGPoint(x: 0, y: 0))
          path.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height))
        }
        .stroke(Color.white.opacity(0.35), lineWidth: 0.5)
      }
    }
  }
}

