import XCTest
@testable import Slouch

@MainActor
final class AppModelTests: XCTestCase {
    func testFirstCompletedRunStartsStreakAndAwardsPoints() {
        let suite = "SlouchTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let model = AppModel(store: PersistenceStore(defaults: defaults))
        let startingPoints = model.profile.points
        let run = RunRecord(
            mode: .techNeck,
            score: 1_800,
            duration: 180,
            hazardsCleared: 12,
            pickups: 5,
            completedCourse: true,
            usedCameraControls: true,
            leaderboardEligible: true,
            metrics: .preview
        )

        let earned = model.record(run)

        XCTAssertEqual(model.profile.currentStreak, 1)
        XCTAssertEqual(model.profile.points, startingPoints + earned)
        XCTAssertGreaterThan(earned, 0)
        XCTAssertEqual(model.bestScore(for: .techNeck), 1_800)
    }

    func testFreezeProtectsOneMissedDay() {
        let suite = "SlouchTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(store: PersistenceStore(defaults: defaults))
        model.profile.currentStreak = 4
        model.profile.streakFreezes = 1

        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.startOfDay(for: .now)
        model.profile.lastCompletedDay = calendar.date(byAdding: .day, value: -2, to: today)

        let run = RunRecord(
            date: today,
            mode: .casual,
            score: 900,
            duration: 90,
            hazardsCleared: 6,
            pickups: 2,
            completedCourse: true,
            usedCameraControls: true,
            leaderboardEligible: true,
            metrics: .preview
        )
        model.record(run, calendar: calendar)

        XCTAssertEqual(model.profile.currentStreak, 5)
        XCTAssertEqual(model.profile.streakFreezes, 0)
    }

    func testIncompleteAttemptCannotReplaceCompletedBest() {
        let suite = "SlouchTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(store: PersistenceStore(defaults: defaults))

        model.record(makeRun(score: 1_000, completed: true))
        model.record(makeRun(score: 9_999, completed: false))

        XCTAssertEqual(model.bestScore(for: .techNeck), 1_000)
        XCTAssertEqual(model.localLeaderboard.map(\.score), [1_000])
    }

    func testHistoryTrimPreservesTrueHighScore() {
        let suite = "SlouchTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(store: PersistenceStore(defaults: defaults))

        let oldBestDate = Date(timeIntervalSinceNow: -10_000)
        model.record(makeRun(score: 8_000, completed: true, date: oldBestDate))
        for index in 0..<65 {
            model.record(makeRun(score: index, completed: false, date: oldBestDate.addingTimeInterval(Double(index + 1))))
        }

        XCTAssertEqual(model.bestScore(for: .techNeck), 8_000)
        XCTAssertTrue(model.profile.runHistory.contains { $0.score == 8_000 && $0.completedCourse })
    }

    func testExpiredStreakReconcilesOnReturn() {
        let suite = "SlouchTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(store: PersistenceStore(defaults: defaults))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let today = calendar.startOfDay(for: .now)
        model.profile.currentStreak = 7
        model.profile.longestStreak = 7
        model.profile.lastCompletedDay = calendar.date(byAdding: .day, value: -3, to: today)

        model.reconcileStreak(asOf: today, calendar: calendar)

        XCTAssertEqual(model.profile.currentStreak, 0)
        XCTAssertEqual(model.profile.longestStreak, 7)
    }

    private func makeRun(
        score: Int,
        completed: Bool,
        date: Date = .now
    ) -> RunRecord {
        RunRecord(
            date: date,
            mode: .techNeck,
            score: score,
            duration: completed ? 180 : 30,
            hazardsCleared: 0,
            pickups: 0,
            completedCourse: completed,
            usedCameraControls: true,
            leaderboardEligible: completed,
            metrics: .preview
        )
    }
}
