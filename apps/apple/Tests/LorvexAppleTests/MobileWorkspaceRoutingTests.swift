import Foundation
import LorvexCore
import Testing

@testable import LorvexMobile

/// Secondary workspaces (Memory, Settings) push a typed `.workspace` route onto
/// the hosting tab's stack.
@MainActor
@Test
func mobileStorePushesSecondaryWorkspacesOntoHostTabs() async throws {
  let store = MobileStore(core: try await makeSeededInMemoryCore(), todayString: { "2026-05-23" })

  store.openWorkspaceDestination(.memory)
  #expect(store.selectedTab == .tasks)
  #expect(store.tasksRoutePath == [.workspace(.memory)])

  store.openWorkspaceDestination(.settings)
  #expect(store.selectedTab == .today)
  #expect(store.routePath == [.workspace(.settings)])
  #expect(store.tasksRoutePath == [.workspace(.memory)])
}

@MainActor
@Test
func mobileStoreMemoryDeepLinkOpensTheWorkspaceNotJustTheTasksHome() async throws {
  let store = MobileStore(core: try await makeSeededInMemoryCore(), todayString: { "2026-05-23" })

  store.applyRouteNavigation(.destination(.memory))
  #expect(store.selectedTab == .tasks)
  #expect(store.tasksRoutePath == [.workspace(.memory)])

  store.applyRouteNavigation(.destination(.lists))
  #expect(store.selectedTab == .tasks)
  #expect(store.tasksRoutePath.isEmpty)
}
