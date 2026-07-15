import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case observatory
    case flightLog
    case store
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .observatory: "Fly"
        case .flightLog: "Scores"
        case .store: "Store"
        case .settings: "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .observatory: "sparkles"
        case .flightLog: "chart.line.uptrend.xyaxis"
        case .store: "shippingbox"
        case .settings: "slider.horizontal.3"
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab: AppTab = .observatory

    var body: some View {
        ZStack {
            SpaceGradientBackground()

            TabView(selection: $selectedTab) {
                ObservatoryView()
                    .tag(AppTab.observatory)
                    .tabItem { Label(AppTab.observatory.title, systemImage: AppTab.observatory.symbol) }

                LeaderboardView()
                    .tag(AppTab.flightLog)
                    .tabItem { Label(AppTab.flightLog.title, systemImage: AppTab.flightLog.symbol) }

                StoreView()
                    .tag(AppTab.store)
                    .tabItem { Label(AppTab.store.title, systemImage: AppTab.store.symbol) }

                SettingsView()
                    .tag(AppTab.settings)
                    .tabItem { Label(AppTab.settings.title, systemImage: AppTab.settings.symbol) }
            }
            .tint(SlouchColor.teal)
        }
        .fullScreenCover(isPresented: Binding(
            get: { !appModel.hasCompletedOnboarding },
            set: { if !$0 { appModel.completeOnboarding() } }
        )) {
            OnboardingView()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                appModel.reconcileStreak()
            }
        }
    }
}

#Preview {
    RootView()
        .environment(AppModel(store: PersistenceStore(defaults: UserDefaults(suiteName: "Slouch.RootPreview")!)))
        .environment(GameCenterService())
}
