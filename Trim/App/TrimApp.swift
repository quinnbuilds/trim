import SwiftUI

@main
struct TrimApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 880, height: 960)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
