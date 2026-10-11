import LorvexCore
import SwiftUI

/// The Lists screen's archived lists, under a header that folds them away
/// (folded by default, remembered across launches). The header counts the lists
/// only while it hides them. Each row restores its list with one tap; an empty
/// archived list can also be deleted from a swipe or the context menu, while one
/// that still holds tasks is restored first, since the core refuses to delete a
/// list that holds tasks. Draws nothing while no list is archived.
struct MobileListArchivedSection: View {
  let lists: [LorvexList]
  let isMutating: Bool
  let restore: (LorvexList) -> Void
  let delete: (LorvexList) -> Void
  @AppStorage("lists.archived.collapsed") private var isCollapsed = true

  var body: some View {
    if !lists.isEmpty {
      Section {
        if !isCollapsed {
          ForEach(lists) { list in
            row(list)
          }
        }
      } header: {
        Button {
          lorvexAnimated(.snappy(duration: 0.2)) { isCollapsed.toggle() }
        } label: {
          HStack(spacing: LorvexDesign.Spacing.s) {
            Text(MobileListArchiveCopy.sectionTitle)
            if isCollapsed {
              Text("\(lists.count)")
                .monospacedDigit()
            }
            Spacer(minLength: 0)
            MobileFoldChevron(isExpanded: !isCollapsed)
          }
          .textCase(nil)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isHeader)
        .lorvexFoldState(isExpanded: !isCollapsed)
        .accessibilityIdentifier("mobileTasks.archived.toggle")
      }
    }
  }

  private func row(_ list: LorvexList) -> some View {
    HStack(spacing: LorvexDesign.Spacing.m) {
      MobileIconTile(
        icon: list.icon, fallback: "tray.fill", tint: LorvexDesign.Palette.neutral, size: 30)
      Text(userContent: list.displayName)
        .foregroundStyle(.secondary)
        .lineLimit(2)
        .frame(maxWidth: .infinity, alignment: .leading)
      Button(MobileListArchiveCopy.restore) { restore(list) }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(isMutating)
        .accessibilityIdentifier("mobileTasks.archived.restore.\(list.id)")
    }
    .padding(.vertical, LorvexDesign.Spacing.xxs)
    .accessibilityElement(children: .contain)
    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
      if list.totalCount == 0 {
        deleteButton(list)
          .mobileDestructiveSwipeStyle()
      }
    }
    .contextMenu {
      Button {
        restore(list)
      } label: {
        Label(MobileListArchiveCopy.restore, systemImage: "arrow.uturn.backward")
      }
      .disabled(isMutating)
      if list.totalCount == 0 {
        deleteButton(list, role: .destructive)
      }
    }
    .accessibilityIdentifier("mobileTasks.archived.row.\(list.id)")
  }

  private func deleteButton(_ list: LorvexList, role: ButtonRole? = nil) -> some View {
    Button(role: role) {
      delete(list)
    } label: {
      Label(
        String(localized: "common.delete", defaultValue: "Delete", table: "Localizable", bundle: MobileL10n.bundle),
        systemImage: "trash")
    }
    .disabled(isMutating)
  }
}
