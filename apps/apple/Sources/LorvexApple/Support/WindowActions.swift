import SwiftUI

extension OpenWindowAction {
  func callAsFunction(_ windowID: LorvexWindowID) {
    callAsFunction(id: windowID.rawValue)
  }
}

extension DismissWindowAction {
  func callAsFunction(_ windowID: LorvexWindowID) {
    callAsFunction(id: windowID.rawValue)
  }
}
