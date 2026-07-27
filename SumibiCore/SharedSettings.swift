import Foundation

public struct ProviderConfiguration: Codable, Equatable, Sendable {
    public static let defaultEndpoint = "https://api.openai.com"
    public static let defaultModel = "gpt-5.6-terra"

    public var endpoint: String
    public var model: String

    public init(
        endpoint: String = Self.defaultEndpoint,
        model: String = Self.defaultModel
    ) {
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
        let endpoint = configuration.endpoint
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let model = configuration.model
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return ProviderConfiguration(
            endpoint: endpoint.isEmpty
                ? ProviderConfiguration.defaultEndpoint
                : configuration.endpoint,
            model: model.isEmpty
                ? ProviderConfiguration.defaultModel
                : configuration.model
        )
    }

    public func saveProviderConfiguration(_ configuration: ProviderConfiguration) throws {
        let data = try encoder.encode(configuration)
        defaults.set(data, forKey: Key.providerConfiguration)
    }

    public func resetProviderConfiguration() {
        defaults.removeObject(forKey: Key.providerConfiguration)
    }
}
