// ABOUTME: One-test placeholder so the fiti-integration target builds.
// ABOUTME: Real AppKit-bound tests land in later tasks.

import Testing

@Suite("AppKit smoke")
struct AppKitSmokeTests {
    @Test("integration target compiles")
    func compiles() {
        #expect(Bool(true))
    }
}
