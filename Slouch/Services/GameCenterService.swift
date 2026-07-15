import GameKit
import Observation
import UIKit

@MainActor
@Observable
final class GameCenterService: NSObject {
    enum AuthenticationState: Equatable {
        case idle
        case authenticating
        case authenticated(playerName: String)
        case unavailable(message: String)
    }

    var authenticationState: AuthenticationState = .idle
    var pendingAuthenticationController: UIViewController?

    static let casualLeaderboardID = "slouch.casual.highscore"
    static let techNeckLeaderboardID = "slouch.techneck.highscore"

    func authenticate() async {
        guard !GKLocalPlayer.local.isAuthenticated else {
            authenticationState = .authenticated(playerName: GKLocalPlayer.local.displayName)
            return
        }

        authenticationState = .authenticating
        GKLocalPlayer.local.authenticateHandler = { [weak self] controller, error in
            Task { @MainActor in
                guard let self else { return }
                if let controller {
                    self.pendingAuthenticationController = controller
                } else if GKLocalPlayer.local.isAuthenticated {
                    self.pendingAuthenticationController = nil
                    self.authenticationState = .authenticated(playerName: GKLocalPlayer.local.displayName)
                } else {
                    self.pendingAuthenticationController = nil
                    self.authenticationState = .unavailable(message: error?.localizedDescription ?? "Game Center is not signed in.")
                }
            }
        }
    }

    func submit(score: Int, mode: GameMode) async {
        guard GKLocalPlayer.local.isAuthenticated else { return }
        let identifier = mode == .casual ? Self.casualLeaderboardID : Self.techNeckLeaderboardID
        do {
            try await GKLeaderboard.submitScore(
                score,
                context: 0,
                player: GKLocalPlayer.local,
                leaderboardIDs: [identifier]
            )
        } catch {
            // Local scores remain authoritative when Game Center is unavailable or unconfigured.
        }
    }
}
