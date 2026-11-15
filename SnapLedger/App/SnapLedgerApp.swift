import SwiftUI

@main struct SnapLedgerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        #if os(macOS)
        .defaultSize(width: 1080, height: 1080)
        .windowResizability(.contentMinSize)
        #endif
    }
}
