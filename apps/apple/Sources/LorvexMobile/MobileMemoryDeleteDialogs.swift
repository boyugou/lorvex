import LorvexCore
import SwiftUI

extension View {
  func mobileMemoryDeleteDialogs(
    entryPendingDeletion: Binding<MemoryEntry?>,
    isConfirmingBatchDelete: Binding<Bool>,
    deleteEntry: @escaping (MemoryEntry) -> Void,
    deleteBatch: @escaping () -> Void
  ) -> some View {
    self
      .confirmationDialog(
        entryPendingDeletion.wrappedValue.map(mobileMemoryDeleteDialogTitle) ?? "",
        isPresented: Binding(
          get: { entryPendingDeletion.wrappedValue != nil },
          set: { if !$0 { entryPendingDeletion.wrappedValue = nil } }
        ),
        titleVisibility: .visible,
        presenting: entryPendingDeletion.wrappedValue
      ) { entry in
        Button(
          String(
            localized: "common.delete", defaultValue: "Delete", table: "Localizable",
            bundle: MobileL10n.bundle), role: .destructive
        ) {
          deleteEntry(entry)
        }
        Button(
          String(
            localized: "common.cancel", defaultValue: "Cancel", table: "Localizable",
            bundle: MobileL10n.bundle), role: .cancel
        ) {}
      } message: { _ in
        mobileMemoryDeleteMessage
      }
      .confirmationDialog(
        String(
          localized: "memory.batch.delete_confirm.title", defaultValue: "Delete selected memory?",
          table: "Localizable", bundle: MobileL10n.bundle),
        isPresented: isConfirmingBatchDelete,
        titleVisibility: .visible
      ) {
        Button(
          String(
            localized: "common.delete", defaultValue: "Delete", table: "Localizable",
            bundle: MobileL10n.bundle), role: .destructive
        ) {
          deleteBatch()
        }
        Button(
          String(
            localized: "common.cancel", defaultValue: "Cancel", table: "Localizable",
            bundle: MobileL10n.bundle), role: .cancel
        ) {}
      } message: {
        mobileMemoryDeleteMessage
      }
  }
}

private var mobileMemoryDeleteMessage: Text {
  Text(
    String(
      localized: "memory.delete.confirm.message",
      defaultValue: "The memory entry is removed. This can't be undone.", table: "Localizable",
      bundle: MobileL10n.bundle))
}

private func mobileMemoryDeleteDialogTitle(_ entry: MemoryEntry) -> String {
  String(
    format: String(
      localized: "memory.delete.confirm.title", defaultValue: "Delete memory “%@”?",
      table: "Localizable", bundle: MobileL10n.bundle),
    entry.key
  )
}
