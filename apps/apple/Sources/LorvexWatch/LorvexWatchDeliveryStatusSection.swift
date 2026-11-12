import LorvexCore
import SwiftUI

struct LorvexWatchDeliveryStatusSection: View {
  @Bindable var store: LorvexWatchStore

  var body: some View {
    if shouldShow {
      Section(String(
        localized: "watch.delivery.section", defaultValue: "Phone delivery",
        table: "Localizable", bundle: WatchL10n.bundle)
      ) {
        if store.deliveryStatus.pendingCount > 0 {
          Label(
            String(
              localized: "watch.delivery.pending",
              defaultValue: "\(store.deliveryStatus.pendingCount) pending",
              table: "Localizable", bundle: WatchL10n.bundle),
            systemImage: "clock.arrow.circlepath"
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        }

        ForEach(store.deliveryStatus.rejectedCommands) { command in
          VStack(alignment: .leading, spacing: 5) {
            Label(
              LorvexWatchCalmCopy.notApplied(command.mutation),
              systemImage: "exclamationmark.circle"
            )
            .font(.caption.weight(.medium))
            .foregroundStyle(LorvexDesign.Palette.warning)

            if let subject = store.subject(of: command) {
              Text(userContent: subject)
                .font(.caption)
                .lineLimit(2)
            }

            Text(command.reason)
              .font(.caption2)
              .foregroundStyle(.secondary)
              .lineLimit(3)

            Button(role: .destructive) {
              Task { await store.dismissRejectedCommand(id: command.id) }
            } label: {
              Text(String(
                localized: "watch.delivery.dismiss", defaultValue: "Dismiss",
                table: "Localizable", bundle: WatchL10n.bundle))
            }
            .controlSize(.small)
          }
        }

        if store.deliveryStatus.journalUnavailable {
          Label(
            String(
              localized: "watch.delivery.journal_failure",
              defaultValue: "Saved actions unavailable",
              table: "Localizable", bundle: WatchL10n.bundle),
            systemImage: "externaldrive.badge.exclamationmark"
          )
          .font(.caption)
          .foregroundStyle(LorvexDesign.Palette.warning)
          .accessibilityHint(String(
            localized: "watch.delivery.journal_failure.hint",
            defaultValue: "Open Lorvex on iPhone, then reopen the watch app",
            table: "Localizable", bundle: WatchL10n.bundle))
        }
      }
    }
  }

  private var shouldShow: Bool {
    store.deliveryStatus.pendingCount > 0
      || !store.deliveryStatus.rejectedCommands.isEmpty
      || store.deliveryStatus.journalUnavailable
  }
}
