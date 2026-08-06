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
        static let hapticFeedbackEnabled = "hapticFeedbackEnabled"
        static let keyClickSoundEnabled = "keyClickSoundEnabled"
        static let userDictionary = "userDictionary"
        static let aiDataSharingConsentEndpoint = "aiDataSharingConsentEndpoint"
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

    public func loadHapticFeedbackEnabled() -> Bool {
        guard defaults.object(forKey: Key.hapticFeedbackEnabled) != nil else {
            return true
        }
        return defaults.bool(forKey: Key.hapticFeedbackEnabled)
    }

    public func saveHapticFeedbackEnabled(_ isEnabled: Bool) {
        defaults.set(isEnabled, forKey: Key.hapticFeedbackEnabled)
    }

    public func loadKeyClickSoundEnabled() -> Bool {
        guard defaults.object(forKey: Key.keyClickSoundEnabled) != nil else {
            return true
        }
        return defaults.bool(forKey: Key.keyClickSoundEnabled)
    }

    public func saveKeyClickSoundEnabled(_ isEnabled: Bool) {
        defaults.set(isEnabled, forKey: Key.keyClickSoundEnabled)
    }

    public func loadUserDictionary() -> String {
        defaults.string(forKey: Key.userDictionary) ?? ""
    }

    public func saveUserDictionary(_ dictionary: String) {
        defaults.set(dictionary, forKey: Key.userDictionary)
    }

    public func hasAIDataSharingConsent(for endpoint: String) -> Bool {
        let normalizedEndpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedEndpoint.isEmpty else {
            return false
        }
        return defaults.string(forKey: Key.aiDataSharingConsentEndpoint) == normalizedEndpoint
    }

    public func saveAIDataSharingConsent(for endpoint: String) {
        let normalizedEndpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedEndpoint.isEmpty else {
            return
        }
        defaults.set(normalizedEndpoint, forKey: Key.aiDataSharingConsentEndpoint)
    }

    public func revokeAIDataSharingConsent() {
        defaults.removeObject(forKey: Key.aiDataSharingConsentEndpoint)
    }
}
