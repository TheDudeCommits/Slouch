import GameKit
import SwiftUI
import UIKit

// MARK: - Observatory

struct ObservatoryView: View {
    @Environment(AppModel.self) private var appModel

    private var orderedModes: [GameMode] {
        [appModel.settings.preferredMode]
            + GameMode.allCases.filter { $0 != appModel.settings.preferredMode }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                CosmicBackdrop()

                ScrollView {
                    VStack(alignment: .leading, spacing: SlouchSpacing.lg) {
                        ObservatoryHeader(profile: appModel.profile)
                        QuietOrbitHero()

                        VStack(alignment: .leading, spacing: SlouchSpacing.md) {
                            SectionHeading(
                                eyebrow: "CHOOSE YOUR COURSE",
                                title: "How would you like to fly?"
                            )

                            ForEach(orderedModes) { mode in
                                NavigationLink(value: mode) {
                                    FlightModeCard(
                                        mode: mode,
                                        bestScore: appModel.bestScore(for: mode)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        DailySignalCard(profile: appModel.profile)
                    }
                    .padding(.horizontal, SlouchSpacing.md)
                    .padding(.top, SlouchSpacing.sm)
                    .padding(.bottom, 110)
                }
                .scrollIndicators(.hidden)
            }
            .navigationDestination(for: GameMode.self) { mode in
                PreflightView(mode: mode)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

private struct ObservatoryHeader: View {
    let profile: PlayerProfile

    var body: some View {
        HStack(alignment: .center, spacing: SlouchSpacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text("SLOUCH")
                    .font(.system(.headline, design: .rounded, weight: .medium))
                    .tracking(4)
                    .foregroundStyle(SlouchColor.moonstone)

                Text("THE OBSERVATORY")
                    .font(.caption2.weight(.semibold))
                    .tracking(1.6)
                    .foregroundStyle(SlouchColor.teal.opacity(0.9))
            }

            Spacer(minLength: SlouchSpacing.sm)

            HeaderStat(
                symbol: "flame.fill",
                value: "\(profile.currentStreak)",
                label: "day streak",
                tint: SlouchColor.solarGold
            )

            HeaderStat(
                symbol: "sparkle",
                value: profile.points.formatted(),
                label: "points",
                tint: SlouchColor.teal
            )
        }
        .accessibilityElement(children: .contain)
    }
}

private struct HeaderStat: View {
    let symbol: String
    let value: String
    let label: String
    let tint: Color

    var body: some View {
        HStack(spacing: SlouchSpacing.xs) {
            Image(systemName: symbol)
                .font(.caption.weight(.bold))
                .foregroundStyle(tint)

            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.white)
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.58))
            }
        }
        .padding(.horizontal, SlouchSpacing.sm)
        .frame(minHeight: 44)
        .background(.white.opacity(0.055), in: Capsule())
        .overlay { Capsule().stroke(.white.opacity(0.1), lineWidth: 1) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(value) \(label)")
    }
}

private struct QuietOrbitHero: View {
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            SlouchColor.lavender.opacity(0.32),
                            SlouchColor.deepNavy.opacity(0.66),
                            SlouchColor.teal.opacity(0.13)
                        ],
                        startPoint: .topTrailing,
                        endPoint: .bottomLeading
                    )
                )

            OrbitMark()
                .frame(width: 190, height: 190)
                .offset(x: 195, y: -45)
                .opacity(0.9)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: SlouchSpacing.sm) {
                Text("QUIET ORBIT · 07")
                    .font(.caption.weight(.semibold))
                    .tracking(1.8)
                    .foregroundStyle(SlouchColor.teal)

                Text("Breathe out.\nLengthen gently.\nTake the helm.")
                    .font(.system(.largeTitle, design: .rounded, weight: .light))
                    .foregroundStyle(SlouchColor.moonstone)
                    .fixedSize(horizontal: false, vertical: true)

                Label("A calm flight can be enough for today", systemImage: "moon.stars.fill")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.72))
            }
            .padding(SlouchSpacing.lg)
        }
        .frame(minHeight: 260)
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.22), SlouchColor.teal.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct OrbitMark: View {
    var body: some View {
        ZStack {
            Circle()
                .stroke(SlouchColor.lavender.opacity(0.44), lineWidth: 1)
                .scaleEffect(x: 1, y: 0.43)
                .rotationEffect(.degrees(-18))

            Circle()
                .stroke(SlouchColor.teal.opacity(0.33), lineWidth: 1)
                .scaleEffect(x: 0.46, y: 1)
                .rotationEffect(.degrees(34))

            Circle()
                .fill(
                    RadialGradient(
                        colors: [SlouchColor.moonstone, SlouchColor.lavender.opacity(0.7), .clear],
                        center: .center,
                        startRadius: 2,
                        endRadius: 45
                    )
                )
                .frame(width: 76, height: 76)

            Image(systemName: "paperplane.fill")
                .font(.title2)
                .foregroundStyle(.white)
                .rotationEffect(.degrees(42))
                .shadow(color: SlouchColor.teal, radius: 12)
        }
    }
}

private struct FlightModeCard: View {
    let mode: GameMode
    let bestScore: Int

    private var accent: Color {
        mode == .casual ? SlouchColor.teal : SlouchColor.lavender
    }

    private var symbol: String {
        mode == .casual ? "camera.viewfinder" : "figure.mind.and.body"
    }

    private var detail: String {
        mode == .casual
            ? "Turn and tilt naturally · 90-second flight"
            : "Guided cues · neutral holds · about 3 minutes"
    }

    var body: some View {
        HStack(spacing: SlouchSpacing.md) {
            ZStack {
                Circle()
                    .fill(accent.opacity(0.17))
                Circle()
                    .stroke(accent.opacity(0.32), lineWidth: 1)
                    .padding(5)
                Image(systemName: symbol)
                    .font(.title2.weight(.light))
                    .foregroundStyle(accent)
            }
            .frame(width: 64, height: 64)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: SlouchSpacing.xs) {
                HStack(alignment: .firstTextBaseline) {
                    Text(mode.title)
                        .font(.headline)
                        .foregroundStyle(.white)

                    Spacer(minLength: SlouchSpacing.xs)

                    Image(systemName: "arrow.up.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(accent)
                }

                Text(mode.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.72))

                Text(detail)
                    .font(.caption)
                    .foregroundStyle(accent.opacity(0.92))

                if bestScore > 0 {
                    Text("Personal best  \(bestScore.formatted())")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
        }
        .padding(SlouchSpacing.md)
        .frame(maxWidth: .infinity, minHeight: 124, alignment: .leading)
        .background(
            LinearGradient(
                colors: [accent.opacity(0.13), SlouchColor.glass],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(accent.opacity(0.24), lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the preflight setup")
    }
}

private struct DailySignalCard: View {
    let profile: PlayerProfile

    private var title: String {
        profile.currentStreak == 0 ? "Begin a gentle rhythm" : "Your rhythm is holding"
    }

    private var message: String {
        if profile.currentStreak == 0 {
            return "Complete one course when it feels comfortable to begin your daily streak."
        }
        return "You have completed a course for \(profile.currentStreak) day\(profile.currentStreak == 1 ? "" : "s") in a row."
    }

    var body: some View {
        HStack(alignment: .top, spacing: SlouchSpacing.md) {
            Image(systemName: profile.currentStreak == 0 ? "sun.horizon.fill" : "flame.fill")
                .font(.title2)
                .foregroundStyle(SlouchColor.solarGold)
                .frame(width: 44, height: 44)
                .background(SlouchColor.solarGold.opacity(0.12), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: SlouchSpacing.xs) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.68))

                if profile.streakFreezes > 0 {
                    Label(
                        "\(profile.streakFreezes) streak freeze\(profile.streakFreezes == 1 ? "" : "s") ready",
                        systemImage: "snowflake"
                    )
                    .font(.caption)
                    .foregroundStyle(SlouchColor.teal)
                }
            }
        }
        .padding(SlouchSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Preflight

struct PreflightView: View {
    let mode: GameMode

    @Environment(AppModel.self) private var appModel
    @State private var isReady = false
    @State private var isPresentingGame = false

    private var accent: Color {
        mode == .casual ? SlouchColor.teal : SlouchColor.lavender
    }

    private var setupItems: [PreflightItem] {
        var items = [
            PreflightItem(symbol: "iphone.gen3", title: "Keep the phone still", detail: "Place it upright on a stable surface at a comfortable viewing distance."),
            PreflightItem(symbol: "person.crop.rectangle", title: "Frame yourself", detail: "Keep your face and upper shoulders visible in soft, even light."),
            PreflightItem(symbol: "eye", title: "Find neutral", detail: "Sit or stand tall, let your shoulders soften, and keep your eyes level.")
        ]

        if mode == .techNeck {
            items.append(
                PreflightItem(symbol: "metronome", title: "Move slowly", detail: "Use a small, comfortable range. Smooth control matters more than distance.")
            )
        }
        return items
    }

    var body: some View {
        ZStack {
            CosmicBackdrop()

            ScrollView {
                VStack(alignment: .leading, spacing: SlouchSpacing.lg) {
                    PreflightHero(mode: mode, accent: accent)

                    VStack(alignment: .leading, spacing: SlouchSpacing.sm) {
                        SectionHeading(eyebrow: "SETUP", title: "A steady launch begins here")

                        ForEach(setupItems) { item in
                            PreflightRow(item: item, tint: accent)
                        }
                    }

                    PrivacyPromiseCard()
                    SafetyCard()

                    Toggle(isOn: $isReady) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("I’m stationary and comfortable")
                                .font(.headline)
                                .foregroundStyle(.white)
                            Text("I can stop at any time.")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.62))
                        }
                    }
                    .tint(accent)
                    .padding(SlouchSpacing.md)
                    .glassCard(tint: accent.opacity(0.09))
                    .accessibilityHint("Required before starting the flight")
                }
                .padding(.horizontal, SlouchSpacing.md)
                .padding(.top, SlouchSpacing.sm)
                .padding(.bottom, 130)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Preflight")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: SlouchSpacing.xs) {
                Button {
                    isPresentingGame = true
                } label: {
                    Label("Calibrate & launch", systemImage: "viewfinder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(GlowButtonStyle(tint: accent))
                .disabled(!isReady)

                Text(isReady ? "Camera access may be requested next." : "Confirm the setup above to continue.")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.58))
            }
            .padding(.horizontal, SlouchSpacing.md)
            .padding(.top, SlouchSpacing.sm)
            .padding(.bottom, SlouchSpacing.xs)
            .background(.ultraThinMaterial)
        }
        .fullScreenCover(isPresented: $isPresentingGame) {
            GameView(mode: mode)
        }
    }
}

private struct PreflightHero: View {
    let mode: GameMode
    let accent: Color

    var body: some View {
        HStack(alignment: .center, spacing: SlouchSpacing.md) {
            ZStack {
                Circle().fill(accent.opacity(0.16))
                Circle().stroke(accent.opacity(0.35), lineWidth: 1).padding(6)
                Image(systemName: mode == .casual ? "camera.viewfinder" : "figure.mind.and.body")
                    .font(.title.weight(.light))
                    .foregroundStyle(accent)
            }
            .frame(width: 76, height: 76)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: SlouchSpacing.xs) {
                Text(mode.shortTitle.uppercased())
                    .font(.caption.weight(.bold))
                    .tracking(1.5)
                    .foregroundStyle(accent)
                Text(mode.title)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                Text(mode == .casual ? "Calm 90-second flight" : "Guided three-minute course")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.65))
            }
        }
        .padding(SlouchSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [accent.opacity(0.18), SlouchColor.glass],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(accent.opacity(0.28), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct PreflightItem: Identifiable {
    let id = UUID()
    let symbol: String
    let title: String
    let detail: String
}

private struct PreflightRow: View {
    let item: PreflightItem
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: SlouchSpacing.md) {
            Image(systemName: item.symbol)
                .font(.body.weight(.medium))
                .foregroundStyle(tint)
                .frame(width: 42, height: 42)
                .background(tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(item.detail)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.66))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(SlouchSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 20)
        .accessibilityElement(children: .combine)
    }
}

private struct PrivacyPromiseCard: View {
    var body: some View {
        HStack(alignment: .top, spacing: SlouchSpacing.md) {
            Image(systemName: "lock.shield.fill")
                .font(.title2)
                .foregroundStyle(SlouchColor.teal)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: SlouchSpacing.xs) {
                Text("Private by design")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("Camera frames are analyzed on this iPhone for movement controls. Slouch does not record or upload images of your face.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .padding(SlouchSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(tint: SlouchColor.teal.opacity(0.08))
        .accessibilityElement(children: .combine)
    }
}

private struct SafetyCard: View {
    var body: some View {
        HStack(alignment: .top, spacing: SlouchSpacing.md) {
            Image(systemName: "heart.text.square.fill")
                .font(.title2)
                .foregroundStyle(SlouchColor.solarGold)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: SlouchSpacing.xs) {
                Text("Comfort is the boundary")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("Use only gentle, pain-free movement. Stop immediately for dizziness, worsening pain, tingling, numbness, or weakness. Never play while walking or driving.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.72))
            }
        }
        .padding(SlouchSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(tint: SlouchColor.solarGold.opacity(0.075))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Flight log and leaderboards

struct LeaderboardView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(GameCenterService.self) private var gameCenter

    @State private var selectedMode: GameMode = .techNeck
    @State private var isShowingGameCenter = false

    private var records: [RunRecord] {
        Array(
            appModel.profile.runHistory
                .filter { $0.mode == selectedMode && $0.completedCourse }
                .sorted { $0.score == $1.score ? $0.date > $1.date : $0.score > $1.score }
                .prefix(10)
        )
    }

    private var authenticationPresentation: Binding<Bool> {
        Binding(
            get: { gameCenter.pendingAuthenticationController != nil },
            set: { isPresented in
                if !isPresented {
                    gameCenter.pendingAuthenticationController = nil
                }
            }
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                CosmicBackdrop()

                ScrollView {
                    VStack(alignment: .leading, spacing: SlouchSpacing.lg) {
                        ScreenTitle(
                            eyebrow: "FLIGHT LOG",
                            title: "Your quiet victories",
                            subtitle: "Personal bests stay on this device. Eligible scores can also reach Game Center."
                        )

                        ScoreSummaryCard(
                            bestScore: appModel.bestScore(for: selectedMode),
                            totalFlights: appModel.profile.runHistory.filter { $0.mode == selectedMode }.count,
                            mode: selectedMode
                        )

                        Picker("Flight mode", selection: $selectedMode) {
                            ForEach(GameMode.allCases) { mode in
                                Text(mode.shortTitle).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityHint("Filters scores by flight mode")

                        GameCenterStatusCard(
                            state: gameCenter.authenticationState,
                            openLeaderboard: { isShowingGameCenter = true },
                            retry: {
                                Task { await gameCenter.authenticate() }
                            }
                        )

                        VStack(alignment: .leading, spacing: SlouchSpacing.sm) {
                            SectionHeading(eyebrow: "LOCAL TOP 10", title: selectedMode.title)

                            if records.isEmpty {
                                EmptyFlightLog(mode: selectedMode)
                            } else {
                                ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
                                    ScoreRow(rank: index + 1, record: record)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, SlouchSpacing.md)
                    .padding(.top, SlouchSpacing.sm)
                    .padding(.bottom, 110)
                }
                .scrollIndicators(.hidden)
            }
            .toolbar(.hidden, for: .navigationBar)
            .task {
                if case .idle = gameCenter.authenticationState {
                    await gameCenter.authenticate()
                }
            }
            .sheet(isPresented: $isShowingGameCenter) {
                GameCenterDashboard(mode: selectedMode)
                    .ignoresSafeArea()
            }
            .sheet(isPresented: authenticationPresentation) {
                AuthenticationControllerHost(controller: gameCenter.pendingAuthenticationController)
                    .ignoresSafeArea()
            }
        }
    }
}

private struct ScoreSummaryCard: View {
    let bestScore: Int
    let totalFlights: Int
    let mode: GameMode

    private var tint: Color {
        mode == .casual ? SlouchColor.teal : SlouchColor.lavender
    }

    var body: some View {
        HStack(spacing: SlouchSpacing.md) {
            VStack(alignment: .leading, spacing: SlouchSpacing.xs) {
                Text("PERSONAL BEST")
                    .font(.caption.weight(.semibold))
                    .tracking(1.4)
                    .foregroundStyle(tint)
                Text(bestScore.formatted())
                    .font(.system(.largeTitle, design: .rounded, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)
                Text(mode.shortTitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.55))
            }

            Spacer()

            VStack(spacing: 2) {
                Image(systemName: "paperplane.fill")
                    .font(.title2)
                    .foregroundStyle(tint)
                Text(totalFlights.formatted())
                    .font(.title3.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.white)
                Text("flights")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.56))
            }
            .frame(minWidth: 82, minHeight: 86)
            .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .padding(SlouchSpacing.lg)
        .background(
            LinearGradient(
                colors: [tint.opacity(0.2), SlouchColor.glass],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(tint.opacity(0.25), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct GameCenterStatusCard: View {
    let state: GameCenterService.AuthenticationState
    let openLeaderboard: () -> Void
    let retry: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: SlouchSpacing.md) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .background(tint.opacity(0.11), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Game Center")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(2)
            }

            Spacer(minLength: SlouchSpacing.xs)

            action
        }
        .padding(SlouchSpacing.md)
        .glassCard(cornerRadius: 20)
    }

    @ViewBuilder
    private var action: some View {
        switch state {
        case .idle, .unavailable:
            Button("Connect", action: retry)
                .buttonStyle(.bordered)
                .tint(SlouchColor.teal)
        case .authenticating:
            ProgressView()
                .tint(SlouchColor.teal)
                .frame(width: 44, height: 44)
                .accessibilityLabel("Connecting to Game Center")
        case .authenticated:
            Button("Open", action: openLeaderboard)
                .buttonStyle(.bordered)
                .tint(SlouchColor.teal)
        }
    }

    private var symbol: String {
        switch state {
        case .authenticated: "checkmark.circle.fill"
        case .unavailable: "exclamationmark.circle"
        default: "gamecontroller.fill"
        }
    }

    private var tint: Color {
        if case .unavailable = state { return SlouchColor.solarGold }
        return SlouchColor.teal
    }

    private var statusText: String {
        switch state {
        case .idle: "Connect to share eligible high scores."
        case .authenticating: "Connecting…"
        case .authenticated(let playerName): "Signed in as \(playerName)"
        case .unavailable(let message): message
        }
    }
}

private struct ScoreRow: View {
    let rank: Int
    let record: RunRecord

    private var rankTint: Color {
        switch rank {
        case 1: SlouchColor.solarGold
        case 2: SlouchColor.moonstone
        case 3: Color(red: 0.78, green: 0.53, blue: 0.38)
        default: SlouchColor.teal.opacity(0.72)
        }
    }

    var body: some View {
        HStack(spacing: SlouchSpacing.md) {
            Text(rank.formatted())
                .font(.headline.monospacedDigit())
                .foregroundStyle(rankTint)
                .frame(width: 32, height: 32)
                .background(rankTint.opacity(0.1), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(record.score.formatted())
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.white)
                Text(record.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.52))
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(record.metrics.smoothness, format: .percent.precision(.fractionLength(0)))
                    .font(.subheadline.monospacedDigit().weight(.medium))
                    .foregroundStyle(SlouchColor.teal)
                Text("smooth")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(.horizontal, SlouchSpacing.md)
        .frame(minHeight: 72)
        .glassCard(cornerRadius: 18)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Rank \(rank), score \(record.score), \(record.metrics.smoothness.formatted(.percent.precision(.fractionLength(0)))) smoothness")
    }
}

private struct EmptyFlightLog: View {
    let mode: GameMode

    var body: some View {
        VStack(spacing: SlouchSpacing.sm) {
            Image(systemName: "sparkles")
                .font(.largeTitle)
                .foregroundStyle(SlouchColor.lavender)
                .accessibilityHidden(true)
            Text("The sky is open")
                .font(.headline)
                .foregroundStyle(.white)
            Text("Your first completed \(mode.shortTitle.lowercased()) flight will appear here.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.62))
                .multilineTextAlignment(.center)
        }
        .padding(SlouchSpacing.lg)
        .frame(maxWidth: .infinity, minHeight: 170)
        .glassCard()
        .accessibilityElement(children: .combine)
    }
}

private struct GameCenterDashboard: UIViewControllerRepresentable {
    let mode: GameMode
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(onDismiss: { dismiss() })
    }

    func makeUIViewController(context: Context) -> GKGameCenterViewController {
        let identifier = mode == .casual
            ? GameCenterService.casualLeaderboardID
            : GameCenterService.techNeckLeaderboardID
        let controller = GKGameCenterViewController(
            leaderboardID: identifier,
            playerScope: .global,
            timeScope: .allTime
        )
        controller.gameCenterDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: GKGameCenterViewController, context: Context) {}

    final class Coordinator: NSObject, GKGameCenterControllerDelegate {
        let onDismiss: () -> Void

        init(onDismiss: @escaping () -> Void) {
            self.onDismiss = onDismiss
        }

        func gameCenterViewControllerDidFinish(_ gameCenterViewController: GKGameCenterViewController) {
            onDismiss()
        }
    }
}

private struct AuthenticationControllerHost: UIViewControllerRepresentable {
    let controller: UIViewController?

    func makeUIViewController(context: Context) -> UIViewController {
        controller ?? UIViewController()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}

// MARK: - Store

struct StoreView: View {
    @Environment(AppModel.self) private var appModel
    @State private var feedback: StoreFeedback?

    var body: some View {
        NavigationStack {
            ZStack {
                CosmicBackdrop()

                ScrollView {
                    VStack(alignment: .leading, spacing: SlouchSpacing.lg) {
                        StoreHeader(
                            points: appModel.profile.points,
                            freezes: appModel.profile.streakFreezes
                        )

                        VStack(alignment: .leading, spacing: SlouchSpacing.sm) {
                            SectionHeading(eyebrow: "SUPPLIES", title: "Keep your rhythm")

                            ForEach(StoreItem.catalog.filter { item in
                                if case .streakFreeze = item.kind { return true }
                                return false
                            }) { item in
                                StoreItemCard(
                                    item: item,
                                    profile: appModel.profile,
                                    action: { performAction(for: item) }
                                )
                            }
                        }

                        VStack(alignment: .leading, spacing: SlouchSpacing.sm) {
                            SectionHeading(
                                eyebrow: "FLIGHT THEMES",
                                title: "A new atmosphere, the same gentle course"
                            )

                            ForEach(StoreItem.catalog.filter { item in
                                if case .theme = item.kind { return true }
                                return false
                            }) { item in
                                StoreItemCard(
                                    item: item,
                                    profile: appModel.profile,
                                    action: { performAction(for: item) }
                                )
                            }
                        }

                        Text("Points are earned through completed flights. No real-money purchases are used in this version.")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.48))
                            .frame(maxWidth: .infinity, alignment: .center)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, SlouchSpacing.lg)
                    }
                    .padding(.horizontal, SlouchSpacing.md)
                    .padding(.top, SlouchSpacing.sm)
                    .padding(.bottom, 110)
                }
                .scrollIndicators(.hidden)
            }
            .toolbar(.hidden, for: .navigationBar)
            .overlay(alignment: .top) {
                if let feedback {
                    StoreToast(feedback: feedback)
                        .padding(.horizontal, SlouchSpacing.md)
                        .padding(.top, SlouchSpacing.sm)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .task(id: feedback.id) {
                            try? await Task.sleep(for: .seconds(2.2))
                            guard self.feedback?.id == feedback.id else { return }
                            withAnimation(.easeOut(duration: 0.25)) {
                                self.feedback = nil
                            }
                        }
                }
            }
        }
    }

    @MainActor
    private func performAction(for item: StoreItem) {
        if case .theme(let theme) = item.kind,
           appModel.profile.unlockedThemes.contains(theme) {
            appModel.select(theme: theme)
            showFeedback(
                message: "\(theme.title) is now active.",
                symbol: "checkmark.circle.fill",
                tint: SlouchColor.teal
            )
            return
        }

        switch appModel.purchase(item) {
        case .purchased:
            let message: String
            if case .streakFreeze = item.kind {
                message = "One streak freeze is ready."
            } else {
                message = "\(item.title) has been unlocked."
            }
            showFeedback(message: message, symbol: "sparkles", tint: SlouchColor.teal)
        case .insufficientPoints:
            showFeedback(
                message: "You need \(max(0, item.cost - appModel.profile.points).formatted()) more points.",
                symbol: "sparkle",
                tint: SlouchColor.solarGold
            )
        case .alreadyOwned:
            showFeedback(message: "Already in your collection.", symbol: "checkmark", tint: SlouchColor.teal)
        case .comingSoon:
            showFeedback(message: "This journey is still being charted.", symbol: "clock", tint: SlouchColor.lavender)
        }
    }

    private func showFeedback(message: String, symbol: String, tint: Color) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            feedback = StoreFeedback(message: message, symbol: symbol, tint: tint)
        }
    }
}

private struct StoreHeader: View {
    let points: Int
    let freezes: Int

    var body: some View {
        VStack(alignment: .leading, spacing: SlouchSpacing.md) {
            ScreenTitle(
                eyebrow: "SUPPLY DOCK",
                title: "Carry a little light",
                subtitle: "Use flight points for atmosphere and a little breathing room."
            )

            HStack(spacing: SlouchSpacing.sm) {
                StoreBalance(
                    symbol: "sparkle",
                    value: points.formatted(),
                    label: "available points",
                    tint: SlouchColor.teal
                )
                StoreBalance(
                    symbol: "snowflake",
                    value: freezes.formatted(),
                    label: "streak freezes",
                    tint: SlouchColor.lavender
                )
            }
        }
    }
}

private struct StoreBalance: View {
    let symbol: String
    let value: String
    let label: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: SlouchSpacing.xs) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(value)
                .font(.title3.monospacedDigit().weight(.semibold))
                .foregroundStyle(.white)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.56))
        }
        .padding(SlouchSpacing.md)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
        .glassCard(cornerRadius: 20, tint: tint.opacity(0.07))
        .accessibilityElement(children: .combine)
    }
}

private struct StoreItemCard: View {
    let item: StoreItem
    let profile: PlayerProfile
    let action: () -> Void

    private var isSelected: Bool {
        guard case .theme(let theme) = item.kind else { return false }
        return profile.selectedTheme == theme
    }

    private var isOwned: Bool {
        guard case .theme(let theme) = item.kind else { return false }
        return profile.unlockedThemes.contains(theme)
    }

    private var buttonTitle: String {
        if item.isComingSoon { return "Coming soon" }
        if isSelected { return "Selected" }
        if isOwned { return "Use theme" }
        return "\(item.cost.formatted()) points"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SlouchSpacing.md) {
            StoreArtwork(item: item, selected: isSelected)

            HStack(alignment: .top, spacing: SlouchSpacing.sm) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(item.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.62))
                }

                Spacer(minLength: SlouchSpacing.sm)

                if isOwned && !isSelected {
                    Text("OWNED")
                        .font(.caption2.weight(.bold))
                        .tracking(1)
                        .foregroundStyle(SlouchColor.teal)
                }
            }

            Button(action: action) {
                HStack {
                    Text(buttonTitle)
                    if !item.isComingSoon && !isSelected && !isOwned {
                        Image(systemName: "sparkle")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(StoreActionButtonStyle(isSelected: isSelected))
            .disabled(item.isComingSoon || isSelected)
        }
        .padding(SlouchSpacing.md)
        .glassCard()
        .accessibilityElement(children: .contain)
    }
}

private struct StoreArtwork: View {
    let item: StoreItem
    let selected: Bool

    private var colors: [Color] {
        switch item.kind {
        case .streakFreeze:
            [SlouchColor.teal.opacity(0.42), SlouchColor.deepNavy]
        case .theme(.luminousFrontier):
            [SlouchColor.lavender.opacity(0.55), SlouchColor.deepNavy]
        case .theme(.auroraDrift):
            [SlouchColor.teal.opacity(0.58), Color.blue.opacity(0.26)]
        case .theme(.solarEmber):
            [SlouchColor.solarGold.opacity(0.62), Color.red.opacity(0.18)]
        case .theme(.jungleRun):
            [Color.green.opacity(0.48), SlouchColor.deepNavy]
        }
    }

    private var symbol: String {
        switch item.kind {
        case .streakFreeze: "snowflake"
        case .theme(.jungleRun): "hare.fill"
        default: "paperplane.fill"
        }
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))

            Circle()
                .stroke(.white.opacity(0.16), lineWidth: 1)
                .frame(width: 126, height: 52)
                .rotationEffect(.degrees(-12))

            Image(systemName: symbol)
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(.white.opacity(item.isComingSoon ? 0.48 : 0.9))
                .shadow(color: colors[0], radius: 16)
                .rotationEffect(.degrees(symbol == "paperplane.fill" ? 42 : 0))

            if selected {
                Label("ACTIVE", systemImage: "checkmark.circle.fill")
                    .font(.caption2.weight(.bold))
                    .tracking(1)
                    .foregroundStyle(.white)
                    .padding(.horizontal, SlouchSpacing.sm)
                    .padding(.vertical, SlouchSpacing.xs)
                    .background(.black.opacity(0.32), in: Capsule())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(SlouchSpacing.sm)
            }
        }
        .frame(height: 126)
        .accessibilityHidden(true)
    }
}

private struct StoreFeedback: Identifiable {
    let id = UUID()
    let message: String
    let symbol: String
    let tint: Color
}

private struct StoreToast: View {
    let feedback: StoreFeedback

    var body: some View {
        HStack(spacing: SlouchSpacing.sm) {
            Image(systemName: feedback.symbol)
                .foregroundStyle(feedback.tint)
            Text(feedback.message)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, SlouchSpacing.md)
        .frame(minHeight: 54)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay { Capsule().stroke(feedback.tint.opacity(0.28), lineWidth: 1) }
        .shadow(color: .black.opacity(0.28), radius: 18, y: 8)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
    }
}

// MARK: - Settings

struct SettingsView: View {
    @Environment(AppModel.self) private var appModel
    @State private var isConfirmingReset = false

    var body: some View {
        @Bindable var model = appModel

        NavigationStack {
            Form {
                Section {
                    SettingsIdentityCard(profile: appModel.profile)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                Section("Sound & feel") {
                    Toggle(isOn: $model.settings.musicEnabled) {
                        SettingsLabel(symbol: "music.note", title: "Music", tint: SlouchColor.lavender)
                    }
                    Toggle(isOn: $model.settings.soundEffectsEnabled) {
                        SettingsLabel(symbol: "speaker.wave.2.fill", title: "Sound effects", tint: SlouchColor.teal)
                    }
                    Toggle(isOn: $model.settings.hapticsEnabled) {
                        SettingsLabel(symbol: "waveform", title: "Haptics", tint: SlouchColor.solarGold)
                    }
                }

                Section("Camera controls") {
                    Picker(selection: $model.settings.preferredMode) {
                        ForEach(GameMode.allCases) { mode in
                            Text(mode.shortTitle).tag(mode)
                        }
                    } label: {
                        SettingsLabel(symbol: "paperplane.fill", title: "Preferred mode", tint: SlouchColor.teal)
                    }

                    VStack(alignment: .leading, spacing: SlouchSpacing.sm) {
                        HStack {
                            SettingsLabel(symbol: "dial.medium", title: "Sensitivity", tint: SlouchColor.lavender)
                            Spacer()
                            Text(model.settings.sensitivity.formatted(.number.precision(.fractionLength(1))) + "×")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $model.settings.sensitivity, in: 0.6...1.4, step: 0.1)
                            .tint(SlouchColor.teal)
                            .accessibilityLabel("Control sensitivity")
                            .accessibilityValue(model.settings.sensitivity.formatted(.number.precision(.fractionLength(1))) + " times")
                    }

                    NavigationLink {
                        RecalibrationView()
                    } label: {
                        SettingsLabel(symbol: "viewfinder", title: "Camera & recalibration", tint: SlouchColor.teal)
                    }
                }

                Section("Comfort") {
                    Toggle(isOn: $model.settings.reduceMotion) {
                        SettingsLabel(symbol: "circle.lefthalf.filled", title: "Reduce motion", tint: SlouchColor.lavender)
                    }

                    NavigationLink {
                        WellnessInfoView()
                    } label: {
                        SettingsLabel(symbol: "heart.text.square", title: "Wellness & safety", tint: SlouchColor.solarGold)
                    }
                }

                Section("The voyage") {
                    NavigationLink {
                        LoreView()
                    } label: {
                        SettingsLabel(symbol: "book.closed.fill", title: "Lore", tint: SlouchColor.lavender)
                    }

                    NavigationLink {
                        PrivacyView()
                    } label: {
                        SettingsLabel(symbol: "lock.shield.fill", title: "Privacy", tint: SlouchColor.teal)
                    }

                    NavigationLink {
                        AboutView()
                    } label: {
                        SettingsLabel(symbol: "info.circle.fill", title: "About Slouch", tint: SlouchColor.moonstone)
                    }
                }

                Section {
                    Button(role: .destructive) {
                        isConfirmingReset = true
                    } label: {
                        Label("Reset all progress", systemImage: "arrow.counterclockwise")
                    }
                } footer: {
                    Text("This clears local scores, points, themes, streaks, and preferences.")
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(CosmicBackdrop())
            .tint(SlouchColor.teal)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.hidden, for: .navigationBar)
            .confirmationDialog(
                "Reset every local record?",
                isPresented: $isConfirmingReset,
                titleVisibility: .visible
            ) {
                Button("Reset all progress", role: .destructive) {
                    appModel.resetAllProgress()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This cannot be undone. Game Center data is managed separately by Apple.")
            }
        }
    }
}

private struct SettingsIdentityCard: View {
    let profile: PlayerProfile

    var body: some View {
        HStack(spacing: SlouchSpacing.md) {
            ZStack {
                Circle().fill(SlouchColor.lavender.opacity(0.16))
                Image(systemName: "paperplane.fill")
                    .font(.title2)
                    .foregroundStyle(SlouchColor.moonstone)
                    .rotationEffect(.degrees(42))
            }
            .frame(width: 58, height: 58)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Luminous pilot")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("\(profile.totalFlights) flights · longest streak \(profile.longestStreak)")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.58))
            }

            Spacer()

            Text(profile.points.formatted())
                .font(.headline.monospacedDigit())
                .foregroundStyle(SlouchColor.teal)
                .accessibilityLabel("\(profile.points) points")
        }
        .padding(SlouchSpacing.md)
        .glassCard()
        .accessibilityElement(children: .contain)
    }
}

private struct SettingsLabel: View {
    let symbol: String
    let title: String
    let tint: Color

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(tint)
        }
    }
}

private struct RecalibrationView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        ZStack {
            CosmicBackdrop()

            ScrollView {
                VStack(alignment: .leading, spacing: SlouchSpacing.lg) {
                    ArticleHero(
                        symbol: "viewfinder",
                        eyebrow: "CAMERA CONTROL",
                        title: "A fresh neutral point",
                        subtitle: "Slouch calibrates at the beginning of every flight.",
                        tint: SlouchColor.teal
                    )

                    ArticleSectionView(
                        title: "For a clear calibration",
                        paragraphs: [
                            "Keep the phone upright and stationary. Your face and upper shoulders should remain visible.",
                            "Settle into a comfortable, natural position with eyes level. Calibration is a control baseline, not a posture score."
                        ]
                    )

                    NavigationLink {
                        PreflightView(mode: appModel.settings.preferredMode)
                    } label: {
                        Label("Open preflight setup", systemImage: "arrow.up.right")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(GlowButtonStyle(tint: SlouchColor.teal))
                }
                .padding(SlouchSpacing.md)
                .padding(.bottom, SlouchSpacing.xl)
            }
        }
        .navigationTitle("Recalibration")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }
}

private struct LoreView: View {
    var body: some View {
        ArticleView(
            navigationTitle: "Lore",
            hero: ArticleHeroContent(
                symbol: "sparkles",
                eyebrow: "THE LUMINOUS FRONTIER",
                title: "The stars remember how to breathe",
                subtitle: "A quiet signal is waiting beyond the Meridian.",
                tint: SlouchColor.lavender
            ),
            sections: [
                ArticleSectionContent(
                    title: "The long drift",
                    paragraphs: [
                        "For generations, the city-ships of the Meridian crossed the dark without looking up. Their pilots forgot the old alignments, and the routes between worlds began to dim.",
                        "Then a moonstone craft received a patient pulse from the frontier: not a distress call, but an invitation to move with the current instead of fighting it."
                    ]
                ),
                ArticleSectionContent(
                    title: "Your course",
                    paragraphs: [
                        "You are the craft’s newest navigator. Each asteroid field is an echo of a lost constellation. Each smooth turn brings its light back into view.",
                        "There is no war to win here. The frontier opens for pilots who can return to center, choose a line, and let the ship carry them home."
                    ]
                )
            ]
        )
    }
}

private struct PrivacyView: View {
    var body: some View {
        ArticleView(
            navigationTitle: "Privacy",
            hero: ArticleHeroContent(
                symbol: "lock.shield.fill",
                eyebrow: "PRIVATE BY DESIGN",
                title: "Your face stays out of the flight log",
                subtitle: "Movement becomes control data on this iPhone.",
                tint: SlouchColor.teal
            ),
            sections: [
                ArticleSectionContent(
                    title: "Camera",
                    paragraphs: [
                        "Camera frames are processed transiently on your device to estimate movement. Slouch does not record, save, or upload images of your face.",
                        "Camera permission can be changed at any time in iOS Settings. A touch-control demo remains available without camera access."
                    ]
                ),
                ArticleSectionContent(
                    title: "Flight data",
                    paragraphs: [
                        "Points, streaks, preferences, and local run records are stored on this device. Reset all progress from Settings whenever you wish.",
                        "If you sign in to Game Center, eligible high scores are submitted to Apple under your Game Center identity. This version does not operate a Slouch account server."
                    ]
                )
            ]
        )
    }
}

private struct WellnessInfoView: View {
    var body: some View {
        ArticleView(
            navigationTitle: "Wellness & Safety",
            hero: ArticleHeroContent(
                symbol: "heart.text.square.fill",
                eyebrow: "COMFORT FIRST",
                title: "A game, not medical treatment",
                subtitle: "The goal is gentle awareness and controlled movement—not diagnosis or correction.",
                tint: SlouchColor.solarGold
            ),
            sections: [
                ArticleSectionContent(
                    title: "Move within comfort",
                    paragraphs: [
                        "Keep movements small, slow, and pain-free. Never force range, whip your head, perform neck circles, or continue through discomfort.",
                        "Stop immediately if you notice dizziness, worsening pain, tingling, numbness, weakness, a severe headache, or any other concerning symptom."
                    ]
                ),
                ArticleSectionContent(
                    title: "When to ask a professional",
                    paragraphs: [
                        "If you have recent neck trauma, neurological symptoms, significant dizziness, or a condition that affects balance or movement, seek advice from a qualified healthcare professional before using Tech Neck mode.",
                        "Do not play while walking, driving, or anywhere you cannot keep the phone stationary and your body supported."
                    ]
                )
            ]
        )
    }
}

private struct AboutView: View {
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    var body: some View {
        ArticleView(
            navigationTitle: "About",
            hero: ArticleHeroContent(
                symbol: "moon.stars.fill",
                eyebrow: "SLOUCH · VERSION \(version)",
                title: "A calmer arcade voyage",
                subtitle: "Built for short flights, smooth choices, and a gentler relationship with the screen.",
                tint: SlouchColor.lavender
            ),
            sections: [
                ArticleSectionContent(
                    title: "Why Slouch exists",
                    paragraphs: [
                        "Slouch turns small head and neck movements into a cinematic on-rails space flight. Casual mode keeps the controls intuitive; Tech Neck mode introduces guided neutral holds, turns, nods, side bends, and gentle retractions.",
                        "Slouch is a wellness game. It does not diagnose, prevent, treat, or cure any medical condition, and it is not a replacement for professional care."
                    ]
                ),
                ArticleSectionContent(
                    title: "The signal",
                    paragraphs: [
                        "Designed as a quiet counterpoint to frantic screen time: obstacles arrive early, control rewards smoothness, and returning to center should feel powerful."
                    ]
                )
            ]
        )
    }
}

private struct ArticleHeroContent {
    let symbol: String
    let eyebrow: String
    let title: String
    let subtitle: String
    let tint: Color
}

private struct ArticleSectionContent: Identifiable {
    let id = UUID()
    let title: String
    let paragraphs: [String]
}

private struct ArticleView: View {
    let navigationTitle: String
    let hero: ArticleHeroContent
    let sections: [ArticleSectionContent]

    var body: some View {
        ZStack {
            CosmicBackdrop()

            ScrollView {
                VStack(alignment: .leading, spacing: SlouchSpacing.lg) {
                    ArticleHero(
                        symbol: hero.symbol,
                        eyebrow: hero.eyebrow,
                        title: hero.title,
                        subtitle: hero.subtitle,
                        tint: hero.tint
                    )

                    ForEach(sections) { section in
                        ArticleSectionView(title: section.title, paragraphs: section.paragraphs)
                    }
                }
                .padding(SlouchSpacing.md)
                .padding(.bottom, SlouchSpacing.xl)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }
}

private struct ArticleHero: View {
    let symbol: String
    let eyebrow: String
    let title: String
    let subtitle: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: SlouchSpacing.md) {
            Image(systemName: symbol)
                .font(.title)
                .foregroundStyle(tint)
                .frame(width: 58, height: 58)
                .background(tint.opacity(0.12), in: Circle())
                .accessibilityHidden(true)

            Text(eyebrow)
                .font(.caption.weight(.bold))
                .tracking(1.6)
                .foregroundStyle(tint)

            Text(title)
                .font(.system(.largeTitle, design: .rounded, weight: .light))
                .foregroundStyle(SlouchColor.moonstone)

            Text(subtitle)
                .font(.body)
                .foregroundStyle(.white.opacity(0.68))
        }
        .padding(SlouchSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [tint.opacity(0.17), SlouchColor.glass],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(tint.opacity(0.24), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct ArticleSectionView: View {
    let title: String
    let paragraphs: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: SlouchSpacing.md) {
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)

            ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                Text(paragraph)
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(SlouchSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Onboarding

struct OnboardingView: View {
    @Environment(AppModel.self) private var appModel
    @State private var page = 0

    private let pages = OnboardingPage.pages

    var body: some View {
        ZStack {
            CosmicBackdrop()

            TabView(selection: $page) {
                ForEach(Array(pages.enumerated()), id: \.element.id) { index, onboardingPage in
                    OnboardingPageView(page: onboardingPage)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .safeAreaInset(edge: .top) {
            HStack {
                Text("SLOUCH")
                    .font(.system(.headline, design: .rounded, weight: .medium))
                    .tracking(4)
                    .foregroundStyle(SlouchColor.moonstone)
                Spacer()
                Text("\(page + 1) / \(pages.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.52))
                    .accessibilityLabel("Page \(page + 1) of \(pages.count)")
            }
            .padding(.horizontal, SlouchSpacing.lg)
            .padding(.top, SlouchSpacing.sm)
        }
        .safeAreaInset(edge: .bottom) {
            OnboardingControls(
                page: page,
                pageCount: pages.count,
                tint: pages[page].tint,
                goBack: {
                    withAnimation(.easeInOut) { page = max(0, page - 1) }
                },
                goForward: {
                    if page == pages.count - 1 {
                        appModel.completeOnboarding()
                    } else {
                        withAnimation(.easeInOut) { page += 1 }
                    }
                }
            )
        }
        .interactiveDismissDisabled()
    }
}

private struct OnboardingPage: Identifiable {
    struct Point: Identifiable {
        let id = UUID()
        let symbol: String
        let title: String
        let detail: String
    }

    let id = UUID()
    let symbol: String
    let eyebrow: String
    let title: String
    let body: String
    let tint: Color
    let points: [Point]

    static let pages: [OnboardingPage] = [
        OnboardingPage(
            symbol: "moon.stars.fill",
            eyebrow: "WELCOME, PILOT",
            title: "Find your quiet orbit",
            body: "Slouch is a third-person space dodger controlled by gentle head and neck movements.",
            tint: SlouchColor.lavender,
            points: [
                Point(symbol: "sparkles", title: "Calm, cinematic flights", detail: "See hazards early and choose a smooth line."),
                Point(symbol: "timer", title: "Short by design", detail: "A guided Tech Neck course takes about three minutes.")
            ]
        ),
        OnboardingPage(
            symbol: "camera.viewfinder",
            eyebrow: "YOUR MOVEMENT · YOUR HELM",
            title: "Keep the phone still. Let yourself move.",
            body: "The front camera reads movement locally and turns it into flight control.",
            tint: SlouchColor.teal,
            points: [
                Point(symbol: "iphone.gen3", title: "Station the iPhone", detail: "Set it upright at a comfortable viewing distance."),
                Point(symbol: "person.crop.rectangle", title: "Stay in frame", detail: "Keep your face and upper shoulders visible."),
                Point(symbol: "lock.shield.fill", title: "Processed on device", detail: "Face images are not recorded or uploaded by Slouch.")
            ]
        ),
        OnboardingPage(
            symbol: "arrow.triangle.branch",
            eyebrow: "TWO WAYS TO FLY",
            title: "Follow your instinct—or a guided course",
            body: "Choose the kind of movement that fits this moment.",
            tint: SlouchColor.lavender,
            points: [
                Point(symbol: "camera.viewfinder", title: "Casual", detail: "The ship gently follows your head for a 90-second flight."),
                Point(symbol: "figure.mind.and.body", title: "Tech Neck", detail: "Neutral holds, turns, nods, side bends, and gentle retractions guide a short course."),
                Point(symbol: "metronome", title: "Smooth over fast", detail: "Small controlled movement earns more than a sudden jerk.")
            ]
        ),
        OnboardingPage(
            symbol: "heart.text.square.fill",
            eyebrow: "COMFORT FIRST",
            title: "This is wellness play—not treatment",
            body: "Slouch does not diagnose, prevent, treat, or cure tech neck or any medical condition.",
            tint: SlouchColor.solarGold,
            points: [
                Point(symbol: "hand.raised.fill", title: "Stay pain-free", detail: "Use a small, gentle range. Never force or whip your neck."),
                Point(symbol: "exclamationmark.triangle.fill", title: "Stop for red flags", detail: "Stop immediately for dizziness, worsening pain, tingling, numbness, weakness, or other concerning symptoms."),
                Point(symbol: "cross.case.fill", title: "Get advice when needed", detail: "Recent neck trauma, neurological symptoms, or significant dizziness deserve professional medical guidance first."),
                Point(symbol: "car.fill", title: "Play somewhere safe", detail: "Never play while walking or driving.")
            ]
        ),
        OnboardingPage(
            symbol: "paperplane.fill",
            eyebrow: "THE FRONTIER IS OPEN",
            title: "Return to center. Choose your line.",
            body: "Every flight begins with a fresh calibration. You can pause or leave whenever you need.",
            tint: SlouchColor.teal,
            points: [
                Point(symbol: "flame.fill", title: "Build a gentle rhythm", detail: "Complete a course to grow a daily streak."),
                Point(symbol: "sparkle", title: "Earn points", detail: "Unlock new space atmospheres and streak freezes."),
                Point(symbol: "slider.horizontal.3", title: "Make it yours", detail: "Tune sensitivity, sound, haptics, and motion in Settings.")
            ]
        )
    ]
}

private struct OnboardingPageView: View {
    let page: OnboardingPage

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SlouchSpacing.lg) {
                OnboardingIllustration(symbol: page.symbol, tint: page.tint)
                    .frame(maxWidth: .infinity)
                    .padding(.top, SlouchSpacing.lg)

                VStack(alignment: .leading, spacing: SlouchSpacing.sm) {
                    Text(page.eyebrow)
                        .font(.caption.weight(.bold))
                        .tracking(1.8)
                        .foregroundStyle(page.tint)

                    Text(page.title)
                        .font(.system(.largeTitle, design: .rounded, weight: .light))
                        .foregroundStyle(SlouchColor.moonstone)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(page.body)
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: SlouchSpacing.sm) {
                    ForEach(page.points) { point in
                        OnboardingPointRow(point: point, tint: page.tint)
                    }
                }
            }
            .padding(.horizontal, SlouchSpacing.lg)
            .padding(.bottom, SlouchSpacing.lg)
        }
        .scrollIndicators(.hidden)
    }
}

private struct OnboardingIllustration: View {
    let symbol: String
    let tint: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.2), lineWidth: 1)
                .frame(width: 214, height: 92)
                .rotationEffect(.degrees(-14))

            Circle()
                .stroke(.white.opacity(0.09), lineWidth: 1)
                .frame(width: 118, height: 190)
                .rotationEffect(.degrees(28))

            Circle()
                .fill(
                    RadialGradient(
                        colors: [tint.opacity(0.42), tint.opacity(0.08), .clear],
                        center: .center,
                        startRadius: 4,
                        endRadius: 72
                    )
                )
                .frame(width: 150, height: 150)

            Image(systemName: symbol)
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.white)
                .rotationEffect(.degrees(symbol == "paperplane.fill" ? 42 : 0))
                .shadow(color: tint, radius: 18)
        }
        .frame(height: 190)
        .accessibilityHidden(true)
    }
}

private struct OnboardingPointRow: View {
    let point: OnboardingPage.Point
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: SlouchSpacing.md) {
            Image(systemName: point.symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 40, height: 40)
                .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(point.title)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(point.detail)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(SlouchSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 19)
        .accessibilityElement(children: .combine)
    }
}

private struct OnboardingControls: View {
    let page: Int
    let pageCount: Int
    let tint: Color
    let goBack: () -> Void
    let goForward: () -> Void

    var body: some View {
        VStack(spacing: SlouchSpacing.md) {
            HStack(spacing: 8) {
                ForEach(0..<pageCount, id: \.self) { index in
                    Capsule()
                        .fill(index == page ? tint : .white.opacity(0.18))
                        .frame(width: index == page ? 24 : 7, height: 7)
                }
            }
            .accessibilityHidden(true)

            HStack(spacing: SlouchSpacing.sm) {
                if page > 0 {
                    Button("Back", action: goBack)
                        .buttonStyle(SecondaryButtonStyle())
                }

                Button(action: goForward) {
                    HStack {
                        Text(page == pageCount - 1 ? "Enter the observatory" : "Continue")
                        Image(systemName: page == pageCount - 1 ? "sparkles" : "arrow.right")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(GlowButtonStyle(tint: tint))
            }
        }
        .padding(.horizontal, SlouchSpacing.lg)
        .padding(.top, SlouchSpacing.sm)
        .background(.ultraThinMaterial)
    }
}

// MARK: - Shared presentation

private struct CosmicBackdrop: View {
    var body: some View {
        ZStack {
            SpaceGradientBackground()
            StarField()
        }
        .ignoresSafeArea()
    }
}

private struct StarField: View {
    private let stars: [(CGFloat, CGFloat, CGFloat, Double)] = [
        (0.07, 0.11, 2.0, 0.62), (0.22, 0.06, 1.2, 0.44), (0.41, 0.15, 1.4, 0.38),
        (0.77, 0.08, 1.8, 0.5), (0.92, 0.18, 1.1, 0.4), (0.14, 0.28, 1.3, 0.5),
        (0.33, 0.35, 2.1, 0.38), (0.62, 0.29, 1.2, 0.48), (0.86, 0.39, 1.8, 0.42),
        (0.05, 0.51, 1.1, 0.35), (0.27, 0.58, 1.7, 0.45), (0.55, 0.48, 1.2, 0.38),
        (0.73, 0.61, 2.0, 0.36), (0.95, 0.55, 1.3, 0.48), (0.11, 0.72, 1.9, 0.36),
        (0.38, 0.78, 1.1, 0.4), (0.66, 0.71, 1.5, 0.43), (0.88, 0.83, 1.1, 0.34),
        (0.19, 0.91, 1.2, 0.48), (0.49, 0.88, 1.8, 0.34), (0.79, 0.95, 1.4, 0.42)
    ]

    var body: some View {
        GeometryReader { proxy in
            ForEach(Array(stars.enumerated()), id: \.offset) { _, star in
                Circle()
                    .fill(.white.opacity(star.3))
                    .frame(width: star.2, height: star.2)
                    .position(x: proxy.size.width * star.0, y: proxy.size.height * star.1)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct ScreenTitle: View {
    let eyebrow: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: SlouchSpacing.xs) {
            Text(eyebrow)
                .font(.caption.weight(.bold))
                .tracking(1.8)
                .foregroundStyle(SlouchColor.teal)
            Text(title)
                .font(.system(.largeTitle, design: .rounded, weight: .light))
                .foregroundStyle(SlouchColor.moonstone)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.62))
        }
        .accessibilityElement(children: .combine)
    }
}

private struct SectionHeading: View {
    let eyebrow: String
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(eyebrow)
                .font(.caption2.weight(.bold))
                .tracking(1.5)
                .foregroundStyle(SlouchColor.teal.opacity(0.88))
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct GlowButtonStyle: ButtonStyle {
    let tint: Color
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(SlouchColor.void)
            .padding(.horizontal, SlouchSpacing.md)
            .frame(minHeight: 54)
            .background(
                LinearGradient(
                    colors: [tint, tint.opacity(0.76)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .shadow(color: tint.opacity(isEnabled ? 0.26 : 0), radius: 14, y: 7)
            .opacity(isEnabled ? (configuration.isPressed ? 0.78 : 1) : 0.38)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

private struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white.opacity(0.82))
            .padding(.horizontal, SlouchSpacing.lg)
            .frame(minHeight: 54)
            .background(.white.opacity(configuration.isPressed ? 0.13 : 0.07), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(.white.opacity(0.13), lineWidth: 1)
            }
    }
}

private struct StoreActionButtonStyle: ButtonStyle {
    let isSelected: Bool
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(isSelected ? SlouchColor.teal : .white)
            .padding(.horizontal, SlouchSpacing.md)
            .frame(minHeight: 46)
            .background(
                isSelected ? SlouchColor.teal.opacity(0.09) : .white.opacity(configuration.isPressed ? 0.14 : 0.08),
                in: RoundedRectangle(cornerRadius: 15, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(isSelected ? SlouchColor.teal.opacity(0.3) : .white.opacity(0.12), lineWidth: 1)
            }
            .opacity(isEnabled || isSelected ? 1 : 0.46)
    }
}
