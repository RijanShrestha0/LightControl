import SwiftUI

@main
struct iLinkControllerApp: App {
    @StateObject private var services = AppServices.shared

    var body: some Scene {
        WindowGroup {
            ContentView(
                bluetooth: services.bluetoothManager,
                lightController: services.lightController,
                glowAssistant: services.glowAssistantManager
            )
                .frame(minWidth: 720, minHeight: 560)
        }
        .windowResizability(.contentSize)
    }
}