import SwiftUI
import AppKit

@main
struct KubeBarApp: App {
    @StateObject private var configStore = ConfigStore()

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra("KubeBar", systemImage: "terminal") {
            MenuBarContentView()
                .environmentObject(configStore)
        }
        .menuBarExtraStyle(.window)
    }
}
