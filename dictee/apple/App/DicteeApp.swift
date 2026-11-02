import SwiftUI

@main
struct DicteeApp: App {
    @StateObject private var engine = DictationEngine.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(engine)
                .onOpenURL { url in
                    engine.handle(url: url)
                }
        }
    }
}
