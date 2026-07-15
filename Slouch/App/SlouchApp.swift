import SwiftUI

@main
struct SlouchApp: App {
    @State private var appModel = AppModel(bypassOnboarding: DebugLaunch.bypassesOnboarding)
    @State private var gameCenter = GameCenterService()

    var body: some Scene {
        WindowGroup {
            Group {
                if let mode = DebugLaunch.directMode {
                    GameView(mode: mode)
                } else {
                    RootView()
                }
            }
                .environment(appModel)
                .environment(gameCenter)
                .preferredColorScheme(.dark)
                .task {
                    await gameCenter.authenticate()
                }
        }
    }
}

/// Deterministic Simulator entry points for visual QA. These arguments are compiled
/// only into Debug builds and never alter the release experience.
private enum DebugLaunch {
    static var directMode: GameMode? {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-qa-casual") { return .casual }
        if arguments.contains("-qa-tech-neck") { return .techNeck }
        #endif
        return nil
    }

    static var bypassesOnboarding: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-qa-home") || directMode != nil
        #else
        false
        #endif
    }
}
