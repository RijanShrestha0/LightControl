import AppIntents

struct CheckLightConnectionIntent: AppIntent {
    static let title: LocalizedStringResource = "Check Light Connection"
    static let description = IntentDescription("Reports whether the selected Bluetooth device is connected.")
    static let openAppWhenRun = false

    static var parameterSummary: some ParameterSummary {
        Summary("Check the light connection")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let response = await AppServices.shared.lightController.connectionStatusResponse()
        return .result(dialog: "\(response)")
    }
}

struct ConnectToLightIntent: AppIntent {
    static let title: LocalizedStringResource = "Connect to Light"
    static let description = IntentDescription("Connects to the Bluetooth device selected in iLink Controller.")
    static let openAppWhenRun = true

    static var parameterSummary: some ParameterSummary {
        Summary("Connect to the selected light")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let response = await AppServices.shared.lightController.connectToSelectedLight()
        return .result(dialog: "\(response)")
    }
}