import Foundation
import LorvexCore

extension AppStore {
  func loadRuntimeDiagnostics() async {
    await perform {
      runtimeDiagnostics = try await core.loadRuntimeDiagnostics()
    }
  }
}
