import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    private let store: PersistenceStore

    var profile: PlayerProfile {
        didSet { save() }
    }

    var settings: AppSettings {
        didSet { save() }
    }

    var hasCompletedOnboarding: Bool {
        didSet { save() }
    }

    init(store: PersistenceStore = .live, bypassOnboarding: Bool = false) {
        self.store = store
        profile = store.load(PlayerProfile.self, forKey: .profile) ?? .fresh
        settings = store.load(AppSettings.self, forKey: .settings) ?? .default
        hasCompletedOnboarding = bypassOnboarding
            || (store.load(Bool.self, forKey: .onboarding) ?? false)
        reconcileStreak()
    }

    var localLeaderboard: [RunRecord] {
        profile.runHistory
            .filter(\.completedCourse)
            .sorted { $0.score == $1.score ? $0.date > $1.date : $0.score > $1.score }
            .prefix(10)
            .map { $0 }
    }

    func bestScore(for mode: GameMode) -> Int {
        profile.runHistory
            .filter { $0.mode == mode && $0.completedCourse }
            .map(\.score)
            .max() ?? 0
    }

    @discardableResult
    func record(_ run: RunRecord, calendar: Calendar = .current) -> Int {
        profile.runHistory.append(run)
        profile.runHistory = trimmedRunHistory(profile.runHistory)

        let points = pointsEarned(for: run)
        profile.points += points
        profile.totalFlights += 1

        guard run.completedCourse else { return points }
        updateStreak(on: run.date, calendar: calendar)
        return points
    }

    /// Reconciles the displayed streak when the app returns after time away. A single
    /// missed day remains recoverable when a freeze is available; longer gaps expire.
    func reconcileStreak(asOf date: Date = .now, calendar: Calendar = .current) {
        guard profile.currentStreak > 0, let lastDate = profile.lastCompletedDay else { return }
        let gap = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: lastDate),
            to: calendar.startOfDay(for: date)
        ).day ?? 0
        if gap > 2 || (gap == 2 && profile.streakFreezes == 0) {
            profile.currentStreak = 0
        }
    }

    func purchase(_ item: StoreItem) -> PurchaseResult {
        guard !item.isComingSoon else { return .comingSoon }
        guard profile.points >= item.cost else { return .insufficientPoints }

        switch item.kind {
        case .streakFreeze:
            profile.points -= item.cost
            profile.streakFreezes += 1
        case .theme(let theme):
            guard !profile.unlockedThemes.contains(theme) else { return .alreadyOwned }
            profile.points -= item.cost
            profile.unlockedThemes.insert(theme)
        }
        return .purchased
    }

    func select(theme: GameTheme) {
        guard profile.unlockedThemes.contains(theme) else { return }
        profile.selectedTheme = theme
    }

    func completeOnboarding() {
        hasCompletedOnboarding = true
    }

    func resetAllProgress() {
        profile = .fresh
        settings = .default
        hasCompletedOnboarding = false
    }

    private func pointsEarned(for run: RunRecord) -> Int {
        guard run.completedCourse else { return 0 }
        let smoothnessBonus = Int((run.metrics.smoothness * 5).rounded())
        let streakBonus = min(profile.currentStreak, 7)
        return min(5 + run.score / 300 + smoothnessBonus + streakBonus, 35)
    }

    private func updateStreak(on date: Date, calendar: Calendar) {
        let today = calendar.startOfDay(for: date)
        guard let lastDate = profile.lastCompletedDay else {
            profile.currentStreak = 1
            profile.longestStreak = max(profile.longestStreak, 1)
            profile.lastCompletedDay = today
            return
        }

        let last = calendar.startOfDay(for: lastDate)
        guard today > last else { return }
        let gap = calendar.dateComponents([.day], from: last, to: today).day ?? 0

        if gap == 1 {
            profile.currentStreak += 1
        } else if gap == 2, profile.streakFreezes > 0 {
            profile.streakFreezes -= 1
            profile.currentStreak += 1
        } else {
            profile.currentStreak = 1
        }

        profile.longestStreak = max(profile.longestStreak, profile.currentStreak)
        profile.lastCompletedDay = today
    }

    /// Keeps recent history compact without ever discarding either mode's genuine
    /// local Top 10. Incomplete attempts stay in the recent log but cannot be a best.
    private func trimmedRunHistory(_ history: [RunRecord]) -> [RunRecord] {
        let recent = Array(history.sorted { $0.date > $1.date }.prefix(50))
        let best = GameMode.allCases.flatMap { mode in
            history
                .filter { $0.mode == mode && $0.completedCourse }
                .sorted { $0.score == $1.score ? $0.date > $1.date : $0.score > $1.score }
                .prefix(10)
        }

        var seen = Set<UUID>()
        return (recent + best).filter { seen.insert($0.id).inserted }
    }

    private func save() {
        store.save(profile, forKey: .profile)
        store.save(settings, forKey: .settings)
        store.save(hasCompletedOnboarding, forKey: .onboarding)
    }
}
