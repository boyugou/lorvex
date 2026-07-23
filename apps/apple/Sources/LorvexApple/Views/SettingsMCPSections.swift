import AppKit
import LorvexCore
import SwiftUI
import TipKit

extension SettingsView {
  private var mcpAssistantTip: MCPAssistantTip { MCPAssistantTip() }

  var mcpSection: some View {
    Group {
      mcpConnectSection
      mcpDiagnosticsSection
    }
  }

  /// The actionable part: how to point an external AI client at this app's MCP
  /// host. The fastest path is the setup prompt the assistant applies to its own
  /// config; the JSON snippet and raw command path cover manual and other clients.
  private var mcpConnectSection: some View {
    Section(String(
      localized: "settings.mcp.connect_section", defaultValue: "Connect an Assistant",
      table: "Localizable",
      bundle: LorvexL10n.bundle)) {
      SettingsMCPConnectionPanel(setup: MCPClientSetup.current())
    }
  }

  private var mcpDiagnosticsSection: some View {
    Section(String(localized: "settings.mcp.section", defaultValue: "Connection Status", table: "Localizable", bundle: LorvexL10n.bundle)) {
      SettingsMCPDiagnosticsPanel(setup: MCPClientSetup.current())
        .popoverTip(mcpAssistantTip)
    }
  }
}

private struct SettingsMCPConnectionPanel: View {
  let setup: MCPClientSetup
  @State private var advancedExpanded = false
  @State private var copiedKind: String?

  var body: some View {
    Group {
      Text(LocalizedStringResource(
        "settings.mcp.connect_blurb",
        defaultValue:
          "Your AI client launches Lorvex's built-in helper to read and update Lorvex data, including tasks, lists, habits, memory, reviews, and calendar entries. Copy the setup prompt below only into assistants you trust.",
        table: "Localizable",
        bundle: LorvexL10n.bundle
      ))
      .font(LorvexDesign.Typography.tertiaryText)
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)

      Button {
        copy(setup.setupPrompt)
      } label: {
        Label(
          copiedKind == "prompt"
            ? String(localized: "common.copied", defaultValue: "Copied", table: "Localizable", bundle: LorvexL10n.bundle)
            : String(localized: "settings.mcp.copy_prompt", defaultValue: "Copy Setup Prompt", table: "Localizable", bundle: LorvexL10n.bundle),
          systemImage: copiedKind == "prompt" ? "checkmark" : "sparkles"
        )
      }
      .buttonStyle(.borderedProminent)
      .accessibilityIdentifier("settings.mcp.copyPrompt")

      // The raw JSON config and command path are manual-setup details most
      // users never need — keep them available but collapsed.
      SettingsAdvancedDisclosureButton(
        isExpanded: $advancedExpanded,
        accessibilityIdentifier: "settings.mcp.advancedToggle")

      if advancedExpanded {
        Text(LocalizedStringResource("settings.mcp.manual_label", defaultValue: "Manual MCP client config:", table: "Localizable", bundle: LorvexL10n.bundle))
          .font(LorvexDesign.Typography.tertiaryText)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)

        Text(setup.jsonSnippet)
          .font(LorvexDesign.Typography.tertiaryText.monospaced())
          .textSelection(.enabled)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, LorvexDesign.Spacing.s)
          .padding(.vertical, LorvexDesign.Spacing.xs)
          .background(.quaternary.opacity(0.18), in: RoundedRectangle(cornerRadius: LorvexDesign.Radius.s))
          .accessibilityIdentifier("settings.mcp.configSnippet")

        Button {
          copy(setup.jsonSnippet, kind: "config")
        } label: {
          Label(
            copiedKind == "config"
              ? String(localized: "common.copied", defaultValue: "Copied", table: "Localizable", bundle: LorvexL10n.bundle)
              : String(localized: "settings.mcp.copy_config", defaultValue: "Copy Config", table: "Localizable", bundle: LorvexL10n.bundle),
            systemImage: copiedKind == "config" ? "checkmark" : "curlybraces"
          )
        }
        .accessibilityIdentifier("settings.mcp.copyConfig")

        Button {
          copy(setup.commandPath, kind: "command")
        } label: {
          Label(
            copiedKind == "command"
              ? String(localized: "common.copied", defaultValue: "Copied", table: "Localizable", bundle: LorvexL10n.bundle)
              : String(localized: "settings.mcp.copy_command", defaultValue: "Copy Command Path", table: "Localizable", bundle: LorvexL10n.bundle),
            systemImage: copiedKind == "command" ? "checkmark" : "terminal"
          )
        }
        .accessibilityIdentifier("settings.mcp.copyCommand")
      }
    }
  }

  private func copy(_ value: String, kind: String = "prompt") {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(value, forType: .string)
    copiedKind = kind
    Task { @MainActor in
      try? await Task.sleep(for: .seconds(1.4))
      if copiedKind == kind {
        copiedKind = nil
      }
    }
  }
}

private struct SettingsMCPDiagnosticsPanel: View {
  let setup: MCPClientSetup
  @State private var status: MCPHelperProbeStatus = .ready

  var body: some View {
    Label {
      VStack(alignment: .leading, spacing: 3) {
        Text(title)
          .font(LorvexDesign.Typography.primaryEmphasis)
          .foregroundStyle(tint)
        Text(detail)
          .font(LorvexDesign.Typography.tertiaryText)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    } icon: {
      Image(systemName: iconName)
        .symbolRenderingMode(.hierarchical)
        .foregroundStyle(tint)
    }
    .task { status = await MCPHelperProbe.probe() }
  }

  private var tint: Color { status == .ready ? .green : .orange }

  private var iconName: String {
    status == .ready ? "checkmark.seal.fill" : "exclamationmark.triangle.fill"
  }

  private var title: LocalizedStringResource {
    switch status {
    case .ready:
      LocalizedStringResource("settings.mcp.ready_title", defaultValue: "Assistant connection ready", table: "Localizable", bundle: LorvexL10n.bundle)
    case .helperMissing:
      LocalizedStringResource("settings.mcp.helper_missing_title", defaultValue: "Assistant helper missing", table: "Localizable", bundle: LorvexL10n.bundle)
    case .helperNotExecutable:
      LocalizedStringResource("settings.mcp.helper_blocked_title", defaultValue: "Assistant helper can’t run", table: "Localizable", bundle: LorvexL10n.bundle)
    case .runtimeFailed:
      LocalizedStringResource("settings.mcp.helper_runtime_failed_title", defaultValue: "Assistant helper self-check failed", table: "Localizable", bundle: LorvexL10n.bundle)
    }
  }

  private var detail: LocalizedStringResource {
    switch status {
    case .ready:
      LocalizedStringResource(
        "settings.mcp.ready_blurb",
        defaultValue:
          "Lorvex includes a built-in helper so your assistant can read and update your tasks. Add it using the connection details above.",
        table: "Localizable",
        bundle: LorvexL10n.bundle
      )
    case .helperMissing:
      LocalizedStringResource(
        "settings.mcp.helper_missing_detail",
        defaultValue:
          "Lorvex can’t find its built-in MCP helper. Reinstall Lorvex from the original download to restore it.",
        table: "Localizable",
        bundle: LorvexL10n.bundle
      )
    case .helperNotExecutable:
      LocalizedStringResource(
        "settings.mcp.helper_blocked_detail",
        defaultValue:
          "Lorvex’s built-in MCP helper isn’t executable. Reinstall Lorvex from the original download, or remove it from quarantine, to restore the connection.",
        table: "Localizable",
        bundle: LorvexL10n.bundle
      )
    case .runtimeFailed:
      LocalizedStringResource(
        "settings.mcp.helper_runtime_failed_detail",
        defaultValue:
          "Lorvex found the helper, but it could not start with the current storage settings. Reconnect Lorvex in Settings > Assistant or reinstall the app.",
        table: "Localizable",
        bundle: LorvexL10n.bundle
      )
    }
  }
}
