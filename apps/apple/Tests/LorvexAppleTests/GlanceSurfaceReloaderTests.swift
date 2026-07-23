import LorvexWidgetKitSupport
import Testing

@Test
func glanceSurfaceReloaderInvalidatesWidgetsAndControlInOrder() {
  let calls = LockedBox<[String]>([])
  let reloader = GlanceSurfaceReloader(
    reloadWidgetTimelines: { calls.mutate { $0.append("widgets") } },
    reloadFocusControl: { calls.mutate { $0.append("control") } })

  reloader.reloadAll()

  #expect(calls.value == ["widgets", "control"])
}
