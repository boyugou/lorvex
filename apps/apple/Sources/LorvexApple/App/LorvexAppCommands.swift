import AppKit
import LorvexCore
import SwiftUI

struct LorvexAppCommands: Commands {
  @Environment(\.openWindow) private var openWindow
  @FocusedValue(\.lorvexTaskCommandContext) private var taskCommandContext

  let store: AppStore

  var body: some Commands {
    // Custom About panel populated from AppMetadata, replacing the bare default.
    CommandGroup(replacing: .appInfo) {
      Button(
        String(
          format: String(
            localized:
              "app.commands.about",
              defaultValue: "About %@",
              table: "Localizable",
              bundle: LorvexL10n.bundle
            ),
          AppMetadata.appDisplayName
        )
      ) {
        NSApplication.shared.orderFrontStandardAboutPanel(options: [
          .applicationName: AppMetadata.appDisplayName,
          .applicationVersion: AppMetadata.displayVersion,
          .init(rawValue: "Copyright"): "Apache-2.0 licensed.",
        ])
      }
    }

    // A real Help menu — no email; Help routes to the lorvex.app website and
    // support pages.
    CommandGroup(replacing: .help) {
      if let websiteURL {
        Link(
          String(
            format: String(
              localized:
                "app.commands.website",
                defaultValue: "%@ Website",
                table: "Localizable",
                bundle: LorvexL10n.bundle
              ),
            AppMetadata.appDisplayName
          ),
          destination: websiteURL
        )
      }
      if let supportURL {
        Link(
          String(
            format: String(
              localized:
                "app.commands.support",
                defaultValue: "%@ Support",
                table: "Localizable",
                bundle: LorvexL10n.bundle
              ),
            AppMetadata.appDisplayName
          ),
          destination: supportURL
        )
      }
    }

    // The standard File-menu "Export" area: save the calendar timeline window
    // as an `.ics` file. macOS otherwise had no entry point for the built
    // `exportCalendarICS` action (iOS, MCP, and the App Intent do).
    CommandGroup(after: .importExport) {
      Button(String(
        localized: "calendar.export_ics.action", defaultValue: "Export Calendar…",
        table: "Localizable",
        bundle: LorvexL10n.bundle)) {
        Task { await store.exportCalendarICSToFile() }
      }
    }

    // Give the sidebar the standard macOS toggle affordances — a View-menu item
    // and ⌃⌘S — instead of only the bare toolbar button.
    CommandGroup(replacing: .sidebar) {
      SidebarVisibilityCommandButton()
    }

    CommandGroup(after: .newItem) {
      Button(AppCommand.newTask.title) {
        // Surface the main window so the focused inline quick-add is visible if
        // ⌘N was pressed while a detached workspace window held focus.
        openWindow(.main)
        AppCommand.newTask.perform(in: store)
      }
      .keyboardShortcut(AppCommand.newTask.keyboardShortcut)

      Button(String(localized: "app.commands.command_palette", defaultValue: "Command Palette", table: "Localizable", bundle: LorvexL10n.bundle)) {
        store.showCommandPalette.toggle()
        // Only surface the main window when opening the palette; toggling it off
        // must not yank focus back from whatever window the user is in.
        if store.showCommandPalette {
          openWindow(.main)
        }
      }
      .keyboardShortcut("k", modifiers: [.command])

    }

    CommandMenu(AppCommandMenu.workspace.title) {
      ForEach(LorvexWindowID.workspaceWindows, id: \.self) { windowID in
        workspaceWindowButton(windowID)
      }
    }

    CommandMenu(AppCommandMenu.navigate.title) {
      ForEach(SidebarSelection.mainNavigationItems) { selection in
        navigationButton(selection)
      }
    }

    CommandMenu(AppCommandMenu.task.title) {
      Button(AppCommand.refresh.title) {
        AppCommand.refresh.perform(in: store)
      }
      .keyboardShortcut(AppCommand.refresh.keyboardShortcut)

      Divider()

      ForEach(TaskCommand.allCases, id: \.self) { command in
        taskCommandButton(command)
      }
    }
  }

  private var websiteURL: URL? {
    URL(string: LorvexWebLinks.websiteURL)
  }

  private var supportURL: URL? {
    URL(string: LorvexWebLinks.supportURL)
  }

  private func openMainWorkspace(_ selection: SidebarSelection) {
    store.navigateToWorkspace(selection)
    openWindow(.main)
  }

  @ViewBuilder
  private func navigationButton(_ selection: SidebarSelection) -> some View {
    let button = Button(String(localized: selection.macOSLocalizedTitle)) {
      openMainWorkspace(selection)
    }

    if let shortcut = selection.navigationShortcut {
      button.keyboardShortcut(shortcut, modifiers: [.command])
    } else {
      button
    }
  }

  @ViewBuilder
  private func workspaceWindowButton(_ windowID: LorvexWindowID) -> some View {
    let button = Button(windowID.windowMenuTitle) {
      openWindow(windowID)
    }

    if let shortcut = windowID.keyboardShortcut {
      button.keyboardShortcut(shortcut, modifiers: [.command, .shift])
    } else {
      button
    }
  }

  private func taskCommandButton(_ command: TaskCommand) -> some View {
    Button(command.title(isFocused: taskCommandContext?.singleTaskIsFocused ?? false)) {
      guard let taskCommandContext else { return }
      command.perform(in: taskCommandContext) { taskID in
        openTaskDetail(taskID)
      }
    }
    .keyboardShortcut(command.keyboardShortcut)
    .disabled(!command.isEnabled(in: taskCommandContext))
  }

  private func openTaskDetail(_ taskID: LorvexTask.ID) {
    store.selectedTaskID = taskID
    openWindow(.taskDetail)
    Task { await store.loadSelectedTaskDetail() }
  }
}
