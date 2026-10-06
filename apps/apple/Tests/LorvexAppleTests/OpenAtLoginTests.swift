import Observation
import Testing
import os

@testable import LorvexApple

/// A login item that records what the app asks of it and keeps the status the
/// system would report.
@MainActor
private final class FakeLoginItem: LoginItemControlling {
  var status: LoginItemStatus
  /// What a successful `register()` leaves behind.
  var statusAfterRegister: LoginItemStatus = .on
  var registerError: (any Error)?
  var unregisterError: (any Error)?
  private(set) var registerCalls = 0
  private(set) var unregisterCalls = 0
  private(set) var settingsOpened = 0

  init(status: LoginItemStatus = .off) {
    self.status = status
  }

  func register() throws {
    registerCalls += 1
    if let registerError { throw registerError }
    status = statusAfterRegister
  }

  func unregister() throws {
    unregisterCalls += 1
    if let unregisterError { throw unregisterError }
    status = .off
  }

  func openSystemSettings() {
    settingsOpened += 1
  }
}

private struct LoginItemFailure: Error {}

/// Settings' "Open at Login" switch.
@MainActor
struct OpenAtLoginTests {
  @Test func theSwitchShowsWhatTheSystemReports() {
    for status in [LoginItemStatus.off, .on, .needsApproval] {
      let model = OpenAtLoginModel(loginItem: FakeLoginItem(status: status))
      #expect(model.status == status)
      #expect(model.isOn == (status != .off))
      #expect(!model.lastChangeFailed)
    }
  }

  @Test func turningTheSwitchOnRegistersAndOffUnregisters() {
    let item = FakeLoginItem()
    let model = OpenAtLoginModel(loginItem: item)

    model.setOn(true)
    #expect(item.registerCalls == 1)
    #expect(model.isOn)
    #expect(model.status == .on)
    #expect(!model.lastChangeFailed)

    model.setOn(false)
    #expect(item.unregisterCalls == 1)
    #expect(!model.isOn)
    #expect(!model.lastChangeFailed)
  }

  @Test func anItemWaitingForApprovalStillCountsAsOn() {
    let item = FakeLoginItem()
    item.statusAfterRegister = .needsApproval
    let model = OpenAtLoginModel(loginItem: item)

    model.setOn(true)

    #expect(model.isOn)
    #expect(model.status == .needsApproval)
    #expect(!model.lastChangeFailed)
  }

  @Test func aRefusedRegistrationLeavesTheSwitchOffAndSaysSo() {
    let item = FakeLoginItem()
    item.registerError = LoginItemFailure()
    let model = OpenAtLoginModel(loginItem: item)

    model.setOn(true)

    #expect(!model.isOn)
    #expect(model.lastChangeFailed)

    model.refresh()
    #expect(!model.lastChangeFailed)
  }

  @Test func aRefusedUnregistrationLeavesTheSwitchOnAndSaysSo() {
    let item = FakeLoginItem(status: .on)
    item.unregisterError = LoginItemFailure()
    let model = OpenAtLoginModel(loginItem: item)

    model.setOn(false)

    #expect(model.isOn)
    #expect(model.lastChangeFailed)
  }

  @Test func anErrorThatLeavesTheItemWhereItWasAskedToBeIsNoFailure() {
    // Registering an item that is already on throws and changes nothing.
    let alreadyOn = FakeLoginItem(status: .on)
    alreadyOn.registerError = LoginItemFailure()
    let onModel = OpenAtLoginModel(loginItem: alreadyOn)
    onModel.setOn(true)
    #expect(onModel.isOn)
    #expect(!onModel.lastChangeFailed)

    // Unregistering an item that is already off does the same.
    let alreadyOff = FakeLoginItem(status: .off)
    alreadyOff.unregisterError = LoginItemFailure()
    let offModel = OpenAtLoginModel(loginItem: alreadyOff)
    offModel.setOn(false)
    #expect(!offModel.isOn)
    #expect(!offModel.lastChangeFailed)
  }

  @Test func aChangeMadeInSystemSettingsReachesViewsOnRefresh() {
    let item = FakeLoginItem()
    let model = OpenAtLoginModel(loginItem: item)
    let observed = OSAllocatedUnfairLock(initialState: false)
    withObservationTracking {
      _ = model.status
    } onChange: {
      observed.withLock { $0 = true }
    }

    item.status = .on
    #expect(!observed.withLock { $0 })
    model.refresh()

    #expect(observed.withLock { $0 })
    #expect(model.isOn)
  }

  @Test func theWayToSystemSettingsGoesToTheLoginItem() {
    let item = FakeLoginItem(status: .needsApproval)
    let model = OpenAtLoginModel(loginItem: item)

    model.openSystemSettings()

    #expect(item.settingsOpened == 1)
  }

  @Test func theCaptionsSayDifferentThings() {
    let captions = [
      SettingsOpenAtLoginFooter.caption,
      SettingsOpenAtLoginFooter.approvalCaption,
      SettingsOpenAtLoginFooter.failedCaption,
    ]
    #expect(Set(captions).count == captions.count)
    for caption in captions {
      #expect(!caption.isEmpty)
    }
  }
}
