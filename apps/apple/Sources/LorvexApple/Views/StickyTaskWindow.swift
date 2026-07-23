import AppKit
import LorvexCore
import SwiftUI

/// Window value for a sticky task note. A distinct type (not bare
/// `LorvexTask.ID`) so the sticky `WindowGroup` is unambiguous alongside the
/// detached-task group, which keys on `LorvexTask.ID` directly.
struct StickyTaskRef: Hashable, Codable {
  let taskID: LorvexTask.ID
}

/// A small, always-on-top "sticky" window for a single task: keep it floating in
/// a corner while you work and jot notes or tick off sub-items, the way a
/// physical sticky note would. Runs its own per-window store
/// (loaded via ``AppStore/loadDetachedTaskWindow(taskID:)``) and renders a
/// compact chromeless card pinned above other apps, even their full-screen spaces.
struct StickyTaskWindow: View {
  let store: AppStore
  let ref: StickyTaskRef?

  var body: some View {
    Group {
      if let ref {
        StickyTaskWindowContent(store: store, taskID: ref.taskID)
      } else {
        DetachedWindowPlaceholder(
          systemImage: "note.text",
          title: String(
            localized: "sticky.placeholder.title", defaultValue: "No Task Pinned",
            table: "Localizable",
            bundle: LorvexL10n.bundle)
        )
      }
    }
    .frame(minWidth: 220, idealWidth: 280, maxWidth: 460, minHeight: 220, idealHeight: 340)
    .background(FloatingWindowConfigurator())
    .tint(.accentColor)
  }
}

private struct StickyTaskWindowContent: View {
  let store: AppStore
  let taskID: LorvexTask.ID

  @State private var windowStore: AppStore?
  @Environment(\.controlActiveState) private var controlActiveState

  var body: some View {
    Group {
      if let windowStore {
        StickyTaskView(store: windowStore, mainStore: store, taskID: taskID)
      } else {
        DetachedWindowLoadingView(
          systemImage: "note.text",
          title: String(localized: "sticky.loading", defaultValue: "Sticky", table: "Localizable", bundle: LorvexL10n.bundle))
      }
    }
    .navigationTitle(windowStore?.selectedTask?.title ?? String(
      localized: "sticky.window_title", defaultValue: "Sticky",
      table: "Localizable",
      bundle: LorvexL10n.bundle))
    .task(id: taskID) {
      let detachedStore = windowStore ?? store.makeDetachedWindowStore()
      windowStore = detachedStore
      // Converge on MCP-host / main-window writes without a second CloudKit
      // stack — the regain-key path below is only a backstop for signals missed
      // while unfocused. Registered before the load await so the observers are
      // always paired with the `.onDisappear` teardown even if the window closes
      // mid-load; a signal before the load merely no-ops (no entity selected yet).
      detachedStore.startDetachedWindowObserversIfNeeded()
      await detachedStore.loadDetachedTaskWindow(taskID: taskID)
    }
    .onDisappear {
      guard let windowStore else { return }
      windowStore.stopDetachedWindowObservers()
      guard let id = windowStore.selectedTaskID,
        windowStore.taskDetailDraftHasChanges(for: id)
      else { return }
      Task { await windowStore.saveTaskDetailDraft(id: id, preserveSelection: id) }
    }
    .onChange(of: windowStore?.selectedTaskHasUnsavedEditorState ?? false) { wasDirty, isDirty in
      guard wasDirty, !isDirty, let windowStore else { return }
      Task { await windowStore.resumeDeferredDetachedWindowReloadIfPossible() }
    }
    .onChange(of: controlActiveState) { _, newState in
      guard let windowStore else { return }
      if newState == .key {
        // Pull in edits made elsewhere, but never clobber an unsaved draft.
        if !windowStore.selectedTaskHasUnsavedEditorState {
          Task { await windowStore.loadDetachedTaskWindow(taskID: taskID) }
        }
      } else {
        // Persist notes/checklist edits when the sticky loses focus.
        Task { await windowStore.saveSelectedTaskDraftIfNeeded() }
      }
    }
    .focusedSceneValue(
      \.lorvexTaskCommandContext,
      windowStore.map {
        LorvexTaskCommandContext(store: $0, selectionSurface: nil)
      }
    )
  }
}

/// The immersive sticky body: a chromeless rounded card whose hero is a
/// free-form notes pad. The title sits quietly at the top; sub-items appear only
/// when they exist; and the window controls (close, open-in-app, add sub-item)
/// fade in on hover, like Apple Music's mini player. No standard title bar.
private struct StickyTaskView: View {
  @Bindable var store: AppStore
  /// The main-window store. "Open in Lorvex" must select the task there — the
  /// per-window `store` is detached and invisible to the main window.
  let mainStore: AppStore
  let taskID: LorvexTask.ID
  @Environment(\.openWindow) private var openWindow
  @Environment(\.dismissWindow) private var dismissWindow

  @State private var hovering = false
  @State private var addingSubitem = false
  @FocusState private var subitemFocused: Bool
  /// Keyboard focus reveals the chromeless window's controls so they are
  /// reachable without a pointer hover (the window hides its traffic lights).
  @FocusState private var controlsFocused: Bool

  private var checklistItems: [TaskChecklistItem] { store.selectedTask?.checklistItems ?? [] }

  var body: some View {
    ZStack(alignment: .topTrailing) {
      card
      // Always in the view/accessibility tree (just faded out) so VoiceOver and
      // keyboard focus can reach Close / Open even without a pointer hover.
      hoverControls
        .padding(LorvexDesign.Spacing.s)
        .opacity(hovering || controlsFocused ? 1 : 0)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    // Fill the whole window, including the (hidden) titlebar strip, so the card
    // reaches the top edge with no transparent gap above it.
    .ignoresSafeArea()
    .onHover { hovering in
      lorvexAnimated(.easeInOut(duration: 0.14)) { self.hovering = hovering }
    }
  }

  private var card: some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.s) {
      Text(store.selectedTask?.title ?? "")
        .font(LorvexDesign.Typography.primaryEmphasis)
        .lineLimit(2)
        .padding(.trailing, 44)  // leave room for the hover controls

      notes

      if !checklistItems.isEmpty {
        checklist
      }

      if hovering || addingSubitem {
        addSubitemRow
      }
    }
    .padding(LorvexDesign.Spacing.m)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .fill(Color(nsColor: .textBackgroundColor))
    )
    .overlay(
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .strokeBorder(.separator.opacity(0.5), lineWidth: 0.5)
    )
    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
  }

  private var notes: some View {
    LorvexPlainTextEditor(
      text: $store.taskDetailNotes,
      placeholder: String(localized: "sticky.notes_placeholder", defaultValue: "Jot a note…", table: "Localizable", bundle: LorvexL10n.bundle),
      minHeight: 60,
      fontSize: 12
    )
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .accessibilityIdentifier("sticky.notes")
  }

  private var checklist: some View {
    VStack(alignment: .leading, spacing: 2) {
      ForEach(checklistItems) { item in
        Button {
          Task { await store.toggleChecklistItem(item) }
        } label: {
          HStack(spacing: LorvexDesign.Spacing.s) {
            Image(systemName: item.completedAt != nil ? "checkmark.circle.fill" : "circle")
              .foregroundStyle(item.completedAt != nil ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            Text(item.text)
              .font(LorvexDesign.Typography.secondaryText)
              .strikethrough(item.completedAt != nil)
              .foregroundStyle(item.completedAt != nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
              .frame(maxWidth: .infinity, alignment: .leading)
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
      }
    }
  }

  private var addSubitemRow: some View {
    HStack(spacing: LorvexDesign.Spacing.s) {
      Image(systemName: "plus.circle")
        .foregroundStyle(.secondary)
      TextField(
        String(localized: "sticky.add_subitem", defaultValue: "Add sub-item", table: "Localizable", bundle: LorvexL10n.bundle),
        text: $store.taskDetailNewChecklistText
      )
      .textFieldStyle(.plain)
      .font(LorvexDesign.Typography.secondaryText)
      .focused($subitemFocused)
      .onSubmit {
        Task { await store.addChecklistItemToSelectedTask() }
      }
    }
    .transition(.opacity)
  }

  private var hoverControls: some View {
    HStack(spacing: LorvexDesign.Spacing.xs) {
      stickyControl("xmark", help: String(
        localized: "sticky.close", defaultValue: "Close sticky",
        table: "Localizable",
        bundle: LorvexL10n.bundle), id: "sticky.close") {
        dismissWindow(id: LorvexWindowID.stickyTaskGroupID, value: StickyTaskRef(taskID: taskID))
      }
      stickyControl("arrow.up.forward.app", help: String(
        localized: "sticky.open_in_app", defaultValue: "Open in Lorvex",
        table: "Localizable",
        bundle: LorvexL10n.bundle), id: "sticky.openInApp") {
        mainStore.selectedTaskID = taskID
        openWindow(.main)
        NSApp.activate()
      }
    }
  }

  private func stickyControl(
    _ systemImage: String, help: String, id: String, action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Image(systemName: systemImage)
        .font(.system(size: 10, weight: .bold))
        .foregroundStyle(.secondary)
        .frame(width: 18, height: 18)
        .background(.quaternary.opacity(0.6), in: Circle())
        .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .focused($controlsFocused)
    .help(help)
    .accessibilityLabel(help)
    .accessibilityIdentifier(id)
  }
}

/// Turns the hosting window into a chromeless, always-on-top sticky: no title
/// bar or traffic lights, transparent background so the rounded card shows
/// through, draggable by its body, visible across Spaces and while Lorvex is in
/// the background.
private struct FloatingWindowConfigurator: NSViewRepresentable {
  func makeNSView(context: Context) -> NSView {
    let view = NSView()
    DispatchQueue.main.async { [weak view] in Self.configure(view?.window) }
    return view
  }

  func updateNSView(_ nsView: NSView, context: Context) {
    DispatchQueue.main.async { [weak nsView] in Self.configure(nsView?.window) }
  }

  private static func configure(_ window: NSWindow?) {
    guard let window else { return }
    // Sit above normal windows AND join every Space, including other apps'
    // full-screen spaces, so the sticky stays visible no matter what else is
    // focused. `.canJoinAllSpaces` is what carries it onto a foreign full-screen space;
    // `.floating` keeps it above that space's content.
    window.level = .floating
    window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    window.hidesOnDeactivate = false
    window.isMovableByWindowBackground = true
    // `.hiddenTitleBar` window style removes the bar; also hide the traffic
    // lights so the card is fully chromeless, and clear the background so the
    // rounded card (not a square window) is what shows.
    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = true
    window.standardWindowButton(.closeButton)?.isHidden = true
    window.standardWindowButton(.miniaturizeButton)?.isHidden = true
    window.standardWindowButton(.zoomButton)?.isHidden = true
    window.isOpaque = false
    window.backgroundColor = .clear
    window.hasShadow = true
  }
}
