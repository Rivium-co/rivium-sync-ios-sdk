import SwiftUI
import RiviumSync

@main
struct RiviumSyncExampleApp: App {
    init() {
        let config = RiviumSyncConfig(
            apiKey: AppConfig.apiKey,
            debugMode: true,
            offlineEnabled: true
        )
        RiviumSync.initialize(config: config)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
