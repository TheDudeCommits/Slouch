import Foundation

enum GameMode: String, Codable, CaseIterable, Identifiable, Hashable {
    case casual
    case techNeck

    var id: String { rawValue }

    var title: String {
        switch self {
        case .casual: "Casual Flight"
        case .techNeck: "Tech Neck Journey"
        }
    }

    var shortTitle: String {
        switch self {
        case .casual: "Casual"
        case .techNeck: "Tech Neck"
        }
    }

    var subtitle: String {
        switch self {
        case .casual: "The ship gently follows your head."
        case .techNeck: "A guided three-minute movement voyage."
        }
    }
}

enum GameTheme: String, Codable, CaseIterable, Identifiable, Hashable {
    case luminousFrontier
    case auroraDrift
    case solarEmber
    case jungleRun

    var id: String { rawValue }

    var title: String {
        switch self {
        case .luminousFrontier: "Luminous Frontier"
        case .auroraDrift: "Aurora Drift"
        case .solarEmber: "Solar Ember"
        case .jungleRun: "Jungle Run"
        }
    }

    var subtitle: String {
        switch self {
        case .luminousFrontier: "Moonstone ship · violet frontier"
        case .auroraDrift: "Teal ion wake · frozen minerals"
        case .solarEmber: "Gold seams · warm stellar ruins"
        case .jungleRun: "A rabbit's forest journey"
        }
    }

    var isComingSoon: Bool { self == .jungleRun }
}

enum MovementCue: String, Codable, CaseIterable, Hashable {
    case neutral
    case steerLeft
    case steerRight
    case nod
    case retract
    case bendLeft
    case bendRight
    case shoulderSet

    var prompt: String {
        switch self {
        case .neutral: "Lengthen gently"
        case .steerLeft: "Glide left"
        case .steerRight: "Glide right"
        case .nod: "Small chin nod"
        case .retract: "Draw back softly"
        case .bendLeft: "Float left"
        case .bendRight: "Float right"
        case .shoulderSet: "Shoulders soft and back"
        }
    }
}

struct RunMetrics: Codable, Hashable {
    var neutralAccuracy: Double
    var smoothness: Double
    var leftRightBalance: Double
    var controlledMovements: Int
    var trackingQuality: Double

    static let preview = RunMetrics(
        neutralAccuracy: 0.93,
        smoothness: 0.87,
        leftRightBalance: 0.98,
        controlledMovements: 14,
        trackingQuality: 0.99
    )
}

struct RunRecord: Codable, Identifiable, Hashable {
    var id: UUID
    var date: Date
    var mode: GameMode
    var score: Int
    var duration: TimeInterval
    var hazardsCleared: Int
    var pickups: Int
    var completedCourse: Bool
    var usedCameraControls: Bool
    var leaderboardEligible: Bool
    var metrics: RunMetrics

    init(
        id: UUID = UUID(),
        date: Date = .now,
        mode: GameMode,
        score: Int,
        duration: TimeInterval,
        hazardsCleared: Int,
        pickups: Int,
        completedCourse: Bool,
        usedCameraControls: Bool,
        leaderboardEligible: Bool,
        metrics: RunMetrics
    ) {
        self.id = id
        self.date = date
        self.mode = mode
        self.score = score
        self.duration = duration
        self.hazardsCleared = hazardsCleared
        self.pickups = pickups
        self.completedCourse = completedCourse
        self.usedCameraControls = usedCameraControls
        self.leaderboardEligible = leaderboardEligible
        self.metrics = metrics
    }
}

struct AppSettings: Codable, Hashable {
    var musicEnabled: Bool
    var soundEffectsEnabled: Bool
    var hapticsEnabled: Bool
    var sensitivity: Double
    var reduceMotion: Bool
    var preferredMode: GameMode

    static let `default` = AppSettings(
        musicEnabled: true,
        soundEffectsEnabled: true,
        hapticsEnabled: true,
        sensitivity: 1,
        reduceMotion: false,
        preferredMode: .techNeck
    )
}

struct PlayerProfile: Codable, Hashable {
    var points: Int
    var currentStreak: Int
    var longestStreak: Int
    var streakFreezes: Int
    var lastCompletedDay: Date?
    var totalFlights: Int
    var unlockedThemes: Set<GameTheme>
    var selectedTheme: GameTheme
    var runHistory: [RunRecord]

    static let fresh = PlayerProfile(
        points: 300,
        currentStreak: 0,
        longestStreak: 0,
        streakFreezes: 0,
        lastCompletedDay: nil,
        totalFlights: 0,
        unlockedThemes: [.luminousFrontier],
        selectedTheme: .luminousFrontier,
        runHistory: []
    )
}

struct StoreItem: Identifiable, Hashable {
    enum Kind: Hashable {
        case streakFreeze
        case theme(GameTheme)
    }

    let id: String
    let title: String
    let subtitle: String
    let cost: Int
    let kind: Kind
    let isComingSoon: Bool

    static let catalog: [StoreItem] = [
        StoreItem(id: "freeze", title: "Streak Freeze", subtitle: "Protect one missed day", cost: 250, kind: .streakFreeze, isComingSoon: false),
        StoreItem(id: "aurora", title: "Aurora Drift", subtitle: "A cool luminous space route", cost: 900, kind: .theme(.auroraDrift), isComingSoon: false),
        StoreItem(id: "ember", title: "Solar Ember", subtitle: "A warm cinematic space route", cost: 1_400, kind: .theme(.solarEmber), isComingSoon: false),
        StoreItem(id: "jungle", title: "Jungle Run", subtitle: "Rabbit journey · future theme", cost: 0, kind: .theme(.jungleRun), isComingSoon: true)
    ]
}

enum PurchaseResult: Equatable {
    case purchased
    case insufficientPoints
    case alreadyOwned
    case comingSoon
}
