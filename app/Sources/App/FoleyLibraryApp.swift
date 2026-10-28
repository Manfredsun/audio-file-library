import SwiftUI

@main
struct FoleyLibraryApp: App {
    @StateObject private var preferences = AppPreferences()
    @StateObject private var environment = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(environment)
                .environmentObject(preferences)
                .onAppear { preferences.applyAppearance() }
                .frame(minWidth: 1000, minHeight: 600)
        }
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
        Settings {
            AppSettingsView().environmentObject(preferences)
        }
    }
}
