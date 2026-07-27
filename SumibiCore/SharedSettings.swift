import Foundation

public struct ProviderConfiguration: Codable, Equatable, Sendable {
    public static let defaultModel = "gpt-5.6-terra"

    public var endpoint: String
    public var model: String

    public init(endpoint: String = "", model: String = Self.defaultModel) {
        self.endpoint = endpoint
        self.model = model
    }
}

public struct SharedSettingsStore {
    public static let appGroupIdentifier = "group.org.sumibi.Sumibi-iOS"

    private enum Key {
        static let providerConfiguration = "providerConfiguration"
    }

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init?() {
        guard let defaults = UserDefaults(suiteName: Self.appGroupIdentifier) else {
            return nil
        }
        self.defaults = defaults
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public func loadProviderConfiguration() -> ProviderConfiguration {
        guard
            let data = defaults.data(forKey: Key.providerConfiguration),
            let configuration = try? decoder.decode(ProviderConfiguration.self, from: data)
        else {
            return ProviderConfiguration()
        }
        if configuration.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return ProviderConfiguration(
                endpoint: configuration.endpoint,
                model: ProviderConfiguration.defaultModel
            )
        }
        return configuration
    }

    public func saveProviderConfiguration(_ configuration: ProviderConfiguration) throws {
        let data = try encoder.encode(configuration)
        defaults.set(data, forKey: Key.providerConfiguration)
    }

    public func resetProviderConfiguration() {
        defaults.removeObject(forKey: Key.providerConfiguration)
    }
}
