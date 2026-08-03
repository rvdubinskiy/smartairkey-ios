import SwiftUI

@main
struct SmartAirKeyApp: App {

    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    // Uses the live backend + preset SAS token when provided via the scheme's
    // environment variables (see AppConfig.resolved); otherwise demo mode.
    @StateObject private var environment = AppEnvironment(config: .resolved)

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(environment)
                .environmentObject(environment.session)
        }
    }
}
