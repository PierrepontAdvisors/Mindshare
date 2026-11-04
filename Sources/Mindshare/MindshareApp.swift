import SwiftUI

@main
struct MindshareApp: App {
    @StateObject private var monitor = Monitor()

    var body: some Scene {
        MenuBarExtra {
            DashboardView(monitor: monitor)
        } label: {
            Image(nsImage: monitor.menuBarIcon)
                .renderingMode(.original)
                .accessibilityLabel(monitor.menuBarLabel)
        }
        .menuBarExtraStyle(.window)
    }
}
