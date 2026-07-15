import Foundation

struct PersistenceStore {
    enum Key: String {
        case profile = "slouch.profile.v1"
        case settings = "slouch.settings.v1"
        case onboarding = "slouch.onboarding.v1"
    }

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    static let live = PersistenceStore(defaults: .standard)

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    func load<Value: Decodable>(_ type: Value.Type, forKey key: Key) -> Value? {
        guard let data = defaults.data(forKey: key.rawValue) else { return nil }
        return try? decoder.decode(Value.self, from: data)
    }

    func save<Value: Encodable>(_ value: Value, forKey key: Key) {
        guard let data = try? encoder.encode(value) else { return }
        defaults.set(data, forKey: key.rawValue)
    }
}
