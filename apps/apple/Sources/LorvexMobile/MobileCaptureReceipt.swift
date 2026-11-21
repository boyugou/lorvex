import LorvexCore
import SwiftUI

/// A snapshot of exactly the tasks returned by a committed single or batch capture.
public struct MobileCaptureReceipt: Hashable, Identifiable, Sendable {
  struct Entry: Hashable, Identifiable, Sendable {
    let id: LorvexTask.ID
    let title: String
    let listName: String?
  }

  public let id: LorvexTask.ID
  let entries: [Entry]
  let destinations: [String]

  init?(tasks: [LorvexTask], lists: [LorvexList]) {
    guard let first = tasks.first else { return nil }
    id = first.id
    let names = Dictionary(lists.map { ($0.id, $0.displayName) }, uniquingKeysWith: { a, _ in a })
    var seen: Set<LorvexList.ID> = []
    var destinations: [String] = []
    entries = tasks.map { task in
      let listID = task.listID ?? LorvexListNaming.inboxID
      let name = names[listID] ?? (listID == LorvexListNaming.inboxID ? LorvexListNaming.localizedInboxName : nil)
      if seen.insert(listID).inserted, let name { destinations.append(name) }
      return Entry(id: task.id, title: task.title, listName: name)
    }
    self.destinations = destinations
  }

  static var savedTasks: String {
    String(localized: "capture.receipt.tasks", defaultValue: "Saved tasks", table: "Localizable", bundle: MobileL10n.bundle)
  }

  static var open: String {
    String(localized: "capture.receipt.open", defaultValue: "Open", table: "Localizable", bundle: MobileL10n.bundle)
  }

  var title: String {
    if entries.count == 1 { return entries[0].title }
    return "\(Self.savedTasks) (\(entries.count.formatted()))"
  }

  var detail: String? {
    guard !destinations.isEmpty else { return nil }
    if destinations.count > 2 {
      return "\(MobileDestination.lists.title) (\(destinations.count.formatted()))"
    }
    let names = destinations.formatted(.list(type: .and))
    return String(localized: "capture.receipt.saved_to", defaultValue: "Saved to \(names)", table: "Localizable", bundle: MobileL10n.bundle)
  }
}

struct MobileCapturedTasksView: View {
  let receipt: MobileCaptureReceipt
  let open: (LorvexTask.ID) -> Void

  var body: some View {
    List(receipt.entries) { entry in
      Button { open(entry.id) } label: {
        HStack(spacing: LorvexDesign.Spacing.m) {
          VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xs) {
            Text(userContent: entry.title)
              .font(LorvexDesign.Typography.primaryText)
            if let name = entry.listName {
              Label { Text(userContent: name) } icon: { Image(systemName: "list.bullet") }
                .font(LorvexDesign.Typography.secondaryText)
                .foregroundStyle(.secondary)
            }
          }
          Spacer()
          Image(systemName: "chevron.forward")
            .font(LorvexDesign.Typography.secondaryText)
            .foregroundStyle(.tertiary)
            .accessibilityHidden(true)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
    }
    .navigationTitle(MobileCaptureReceipt.savedTasks)
    .accessibilityIdentifier("capture.receipt.tasks")
  }
}
