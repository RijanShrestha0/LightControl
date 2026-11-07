import SwiftUI

@main
struct iLinkControllerApp: App {
    @StateObject private var services = AppServices.shared

    var body: some Scene {
        WindowGroup {
            ContentView(
                bluetooth: services.bluetoothManager,
                lightController: services.lightController
            )
                .frame(minWidth: 680, minHeight: 480)
        }
        .windowResizability(.contentSize)
    }
}