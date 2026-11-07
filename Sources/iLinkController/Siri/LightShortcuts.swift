import AppIntents

struct LightShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CheckLightConnectionIntent(),
            phrases: [
                "Check my light connection in \(.applicationName)",
                "Is my iLink light connected in \(.applicationName)"
            ],
            shortTitle: "Light Connection",
            systemImageName: "antenna.radiowaves.left.and.right"
        )

        AppShortcut(
            intent: ConnectToLightIntent(),
            phrases: [
                "Connect to my iLink light in \(.applicationName)"
            ],
            shortTitle: "Connect Light",
            systemImageName: "link"
        )
    }
}