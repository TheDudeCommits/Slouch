import Observation
import SwiftUI

enum AppRoute: Hashable {
    case preflight(GameMode)
    case lore
}
@MainActor
@Observable
final class AppRouter {
    var path: [AppRoute] = []

    func navigate(to route: AppRoute) {
        path.append(route)
    }

    func reset() {
        path.removeAll()
    }
}
