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
        static let conversionCompletionHapticEnabled = "conversionCompletionHapticEnabled"
        static let keyClickSoundEnabled = "keyClickSoundEnabled"
        static let userDictionary = "userDictionary"
        static let aiDataSharingConsentEndpoint = "aiDataSharingConsentEndpoint"
        static let usageStatistics = "usageStatistics"
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

    public func loadConversionCompletionHapticEnabled() -> Bool {
        guard defaults.object(forKey: Key.conversionCompletionHapticEnabled) != nil else {
            return true
        }
        return defaults.bool(forKey: Key.conversionCompletionHapticEnabled)
    }

    public func saveConversionCompletionHapticEnabled(_ isEnabled: Bool) {
        defaults.set(isEnabled, forKey: Key.conversionCompletionHapticEnabled)
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

    public func loadUsageStatistics() -> [ModelUsageStatistics] {
        guard
            let data = defaults.data(forKey: Key.usageStatistics),
            let statistics = try? decoder.decode([ModelUsageStatistics].self, from: data)
        else {
            return []
        }
        return statistics.sorted { $0.model.localizedStandardCompare($1.model) == .orderedAscending }
    }

    public func recordUsage(_ usage: TokenUsage, model: String) {
        let normalizedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedModel.isEmpty else {
            return
        }
        var statistics = loadUsageStatistics()
        if let index = statistics.firstIndex(where: { $0.model == normalizedModel }) {
            if statistics[index].collectionStartedAt == nil {
                statistics[index].collectionStartedAt = Date()
            }
            statistics[index].conversionCount += 1
            statistics[index].inputTokens += usage.inputTokens
            statistics[index].cachedInputTokens += usage.cachedInputTokens
            statistics[index].outputTokens += usage.outputTokens
        } else {
            statistics.append(
                ModelUsageStatistics(
                    model: normalizedModel,
                    conversionCount: 1,
                    inputTokens: usage.inputTokens,
                    cachedInputTokens: usage.cachedInputTokens,
                    outputTokens: usage.outputTokens,
                    collectionStartedAt: Date()
                )
            )
        }
        if let data = try? encoder.encode(statistics) {
            defaults.set(data, forKey: Key.usageStatistics)
        }
    }

    public func resetUsageStatistics() {
        let reset = loadUsageStatistics().map {
            ModelUsageStatistics(model: $0.model, collectionStartedAt: Date())
        }
        if let data = try? encoder.encode(reset) {
            defaults.set(data, forKey: Key.usageStatistics)
        }
    }
}

public struct ModelUsageStatistics: Codable, Equatable, Identifiable, Sendable {
    public var id: String { model }

    public let model: String
    public var conversionCount: Int
    public var inputTokens: Int
    public var cachedInputTokens: Int
    public var outputTokens: Int
    public var collectionStartedAt: Date?

    public init(
        model: String,
        conversionCount: Int = 0,
        inputTokens: Int = 0,
        cachedInputTokens: Int = 0,
        outputTokens: Int = 0,
        collectionStartedAt: Date? = nil
    ) {
        self.model = model
        self.conversionCount = conversionCount
        self.inputTokens = inputTokens
        self.cachedInputTokens = cachedInputTokens
        self.outputTokens = outputTokens
        self.collectionStartedAt = collectionStartedAt
    }

    public var totalTokens: Int {
        inputTokens + outputTokens
    }

    public var estimatedCostUSD: Decimal? {
        guard let pricing = ModelPricing.pricing(for: model) else {
            return nil
        }
        let cached = min(cachedInputTokens, inputTokens)
        let uncached = inputTokens - cached
        return (
            Decimal(uncached) * pricing.input
                + Decimal(cached) * pricing.cachedInput
                + Decimal(outputTokens) * pricing.output
        ) / 1_000_000
    }
}

private struct ModelPricing {
    let input: Decimal
    let cachedInput: Decimal
    let output: Decimal

    static func pricing(for model: String) -> ModelPricing? {
        let normalized = model.lowercased()
        if normalized == "gpt-5.6-sol" || normalized.hasPrefix("gpt-5.6-sol-") {
            return ModelPricing(input: 5, cachedInput: 0.5, output: 30)
        }
        if normalized == "gpt-5.6-terra" || normalized.hasPrefix("gpt-5.6-terra-") {
            return ModelPricing(input: 2, cachedInput: 0.2, output: 12)
        }
        return nil
    }
}
