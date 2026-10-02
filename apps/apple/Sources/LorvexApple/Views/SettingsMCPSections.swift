import AppKit
import LorvexCore
import SwiftUI

extension SettingsView {
  /// Connecting an assistant, the assistants that have used Lorvex here, and,
  /// last, the manual setup most people never need.
  var mcpSection: some View {
    Group {
      SettingsAssistantConnectSection()
      SettingsAssistantSessionsSection(core: store.core)
      SettingsMCPConnectionPanel(setup: MCPClientSetup.current())
    }
  }
}

/// How to point an external AI client at this app's MCP host: the setup prompt
/// the assistant applies to its own config, copied from the row's trailing
/// button, with what the helper does and whom to trust as the footer under it.
/// The JSON snippet and raw command path for manual setup are a group of their
/// own at the end of the pane (``SettingsMCPConnectionPanel``).
///
/// The group leads with the bundled helper's problem when its self-check finds
/// one, and says nothing about a working helper: the assistants listed below
/// it, with when each last used Lorvex, show that a connection works end to
/// end. The self-check hangs off the section, which always draws its controls,
/// so it runs even while no problem shows.
private struct SettingsAssistantConnectSection: View {
  @State private var helperStatus: MCPHelperProbeStatus = .ready
  @State private var copied = false

  var body: some View {
    Section {
      if let problem = SettingsMCPHelperProblemRow(status: helperStatus) {
        problem
      }
      LabeledContent {
        Button {
          copy(MCPClientSetup.current().setupPrompt)
        } label: {
          SettingsCopyButtonTitle(copied: copied)
        }
        .buttonStyle(.borderedProminent)
        .accessibilityLabel(String(localized: "settings.mcp.copy_prompt", defaultValue: "Copy Setup Prompt", table: "Localizable", bundle: LorvexL10n.bundle))
        .accessibilityIdentifier("settings.mcp.copyPrompt")
      } label: {
        Label(
          String(localized: "settings.mcp.setup_prompt", defaultValue: "Setup Prompt", table: "Localizable", bundle: LorvexL10n.bundle),
          systemImage: "sparkles")
      }
    } header: {
      Text(String(
        localized: "settings.mcp.connect_section", defaultValue: "Connect an Assistant",
        table: "Localizable",
        bundle: LorvexL10n.bundle))
    } footer: {
      Text(LocalizedStringResource(
        "settings.mcp.connect_blurb",
        defaultValue:
          "Lorvex is built for an assistant to do most of the work: your AI client launches Lorvex’s built-in helper to read and update tasks, lists, habits, memory, reviews, and calendar entries. Copy the setup prompt only into assistants you trust.",
        table: "Localizable",
        bundle: LorvexL10n.bundle
      ))
    }
    .task {
      let status = await Self.currentStatus()
      lorvexAnimated(.snappy(duration: 0.18)) { helperStatus = status }
    }
  }

  /// The bundled helper's status. A DEBUG `--ui-preview` run is a bare binary
  /// with no app bundle to probe, so it shows an installed app's ready state.
  private static func currentStatus() async -> MCPHelperProbeStatus {
    #if DEBUG
      if LorvexUIPreview.isActive { return .ready }
    #endif
    return await MCPHelperProbe.probe()
  }

  private func copy(_ value: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(value, forType: .string)
    copied = true
    Task { @MainActor in
      try? await Task.sleep(for: .seconds(1.4))
      copied = false
    }
  }
}

/// Which assistants have actually used Lorvex here, so the user can confirm a
/// connection works end to end rather than only that the helper can run. One
/// row per MCP client, most recently active first, with when it last used
/// Lorvex. The helper records a client when it connects and again while it
/// keeps calling tools; the list is device-local and never synced. The tooltip
/// carries the raw client name and version for troubleshooting.
private struct SettingsAssistantSessionsSection: View {
  let core: any LorvexCoreServicing
  @State private var sessions: [AssistantSessionRecord]?

  var body: some View {
    // The load hangs off the section, which always draws its header: rows only
    // exist once the load has finished.
    Section(String(
      localized: "settings.mcp.sessions_section", defaultValue: "Assistants on This Mac",
      table: "Localizable", bundle: LorvexL10n.bundle)) {
      if let sessions, sessions.isEmpty {
        Text(LocalizedStringResource(
          "settings.mcp.sessions_empty",
          defaultValue: "No assistant has used Lorvex on this Mac yet.",
          table: "Localizable", bundle: LorvexL10n.bundle))
          .font(LorvexDesign.Typography.tertiaryText)
          .foregroundStyle(.secondary)
          .accessibilityIdentifier("settings.mcp.sessionsEmpty")
      } else if let sessions {
        ForEach(sessions) { session in
          LabeledContent(session.displayName) {
            Text(lastUsed(session))
              .foregroundStyle(.secondary)
          }
          .help(Text(verbatim: [session.clientName, session.clientVersion].compactMap { $0 }
            .joined(separator: " ")))
          .accessibilityIdentifier("settings.mcp.session")
        }
      }
    }
    .task { sessions = (try? await core.loadAssistantSessions()) ?? [] }
  }

  private func lastUsed(_ session: AssistantSessionRecord) -> String {
    // A preview run pins its clock, so the seeded sessions read the same in
    // every capture.
    let now = LorvexPreviewClock.now(in: Calendar.current)
    let relative = LorvexDateFormatters.relative(session.lastActiveAt, to: now)
    return String(
      format: String(
        localized: "settings.mcp.session_last_used", defaultValue: "Last used %@",
        table: "Localizable", bundle: LorvexL10n.bundle),
      relative)
  }
}

/// Manual setup for clients that take a JSON config or a command path, folded
/// behind "Advanced" in a group at the end of the Assistant pane: the snippet,
/// selectable, with its two copy buttons at the trailing edge of the line
/// above it.
private struct SettingsMCPConnectionPanel: View {
  let setup: MCPClientSetup
  @State private var advancedExpanded = false
  @State private var copiedKind: String?

  var body: some View {
    Section {
      SettingsAdvancedDisclosureButton(
        isExpanded: $advancedExpanded,
        accessibilityIdentifier: "settings.mcp.advancedToggle")

      if advancedExpanded {
        LabeledContent {
          HStack(spacing: LorvexDesign.Spacing.s) {
            Button {
              copy(setup.commandPath, kind: "command")
            } label: {
              SettingsCopyButtonTitle(
                title: String(localized: "settings.mcp.copy_command", defaultValue: "Copy Command Path", table: "Localizable", bundle: LorvexL10n.bundle),
                copied: copiedKind == "command")
            }
            .accessibilityIdentifier("settings.mcp.copyCommand")

            Button {
              copy(setup.jsonSnippet, kind: "config")
            } label: {
              SettingsCopyButtonTitle(
                title: String(localized: "settings.mcp.copy_config", defaultValue: "Copy Config", table: "Localizable", bundle: LorvexL10n.bundle),
                copied: copiedKind == "config")
            }
            .accessibilityIdentifier("settings.mcp.copyConfig")
          }
        } label: {
          Text(LocalizedStringResource("settings.mcp.manual_label", defaultValue: "Manual Setup", table: "Localizable", bundle: LorvexL10n.bundle))
        }

        Text(setup.jsonSnippet)
          .font(LorvexDesign.Typography.tertiaryText.monospaced())
          .textSelection(.enabled)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, LorvexDesign.Spacing.s)
          .padding(.vertical, LorvexDesign.Spacing.xs)
          .background(LorvexDesign.Palette.insetFill, in: RoundedRectangle(cornerRadius: LorvexDesign.Radius.s))
          .accessibilityIdentifier("settings.mcp.configSnippet")
      }
    }
  }

  private func copy(_ value: String, kind: String) {
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

/// What is wrong with the bundled MCP helper and how to recover, in a warning
/// row. It exists only for a failed self-check: `init(status:)` returns nil for
/// a ready helper, since a working connection needs no row of its own.
private struct SettingsMCPHelperProblemRow: View {
  let title: LocalizedStringResource
  let detail: LocalizedStringResource

  init?(status: MCPHelperProbeStatus) {
    switch status {
    case .ready:
      return nil
    case .helperMissing:
      title = LocalizedStringResource("settings.mcp.helper_missing_title", defaultValue: "Assistant helper missing", table: "Localizable", bundle: LorvexL10n.bundle)
      detail = LocalizedStringResource(
        "settings.mcp.helper_missing_detail",
        defaultValue:
          "Lorvex can’t find its built-in MCP helper. Reinstall Lorvex from the original download to restore it.",
        table: "Localizable",
        bundle: LorvexL10n.bundle
      )
    case .helperNotExecutable:
      title = LocalizedStringResource("settings.mcp.helper_blocked_title", defaultValue: "Assistant helper can’t run", table: "Localizable", bundle: LorvexL10n.bundle)
      detail = LocalizedStringResource(
        "settings.mcp.helper_blocked_detail",
        defaultValue:
          "Lorvex’s built-in MCP helper isn’t executable. Reinstall Lorvex from the original download, or remove it from quarantine, to restore the connection.",
        table: "Localizable",
        bundle: LorvexL10n.bundle
      )
    case .runtimeFailed:
      title = LocalizedStringResource("settings.mcp.helper_runtime_failed_title", defaultValue: "Assistant helper self-check failed", table: "Localizable", bundle: LorvexL10n.bundle)
      detail = LocalizedStringResource(
        "settings.mcp.helper_runtime_failed_detail",
        defaultValue:
          "Lorvex found the helper, but it could not start with the current storage settings. Reconnect Lorvex in Settings > Assistant or reinstall the app.",
        table: "Localizable",
        bundle: LorvexL10n.bundle
      )
    }
  }

  // The warning color marks the icon only, so the title reads as a statement
  // rather than as a link.
  var body: some View {
    Label {
      VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xxs) {
        Text(title)
          .font(LorvexDesign.Typography.primaryEmphasis)
        Text(detail)
          .font(LorvexDesign.Typography.tertiaryText)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    } icon: {
      Image(systemName: "exclamationmark.triangle.fill")
        .symbolRenderingMode(.hierarchical)
        .foregroundStyle(LorvexDesign.Palette.warning)
    }
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("settings.mcp.helperProblem")
  }
}
