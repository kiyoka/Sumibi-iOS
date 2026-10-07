import Foundation

// Shared by the settings picker and the settings chat context.
public enum ModelOption: String, CaseIterable, Identifiable, Codable, Sendable {
    case gpt6Sol = "gpt-6-sol"
    case gpt6Luna = "gpt-6-luna"
    case custom

    public var id: Self { self }

    public var displayName: String {
        switch self {
        case .gpt6Sol: "GPT-6 Sol"
        case .gpt6Luna: "GPT-6 Luna"
        case .custom: "自由入力"
        }
    }

    public var summary: String? {
        switch self {
        case .gpt6Sol: "既定・精度重視"
        case .gpt6Luna: "低コスト・高速重視"
        case .custom: nil
        }
    }

    public var pickerLabel: String {
        guard let summary else { return displayName }
        return "\(displayName)（\(summary)）"
    }

    public var modelID: String? { self == .custom ? nil : rawValue }

    public static func selection(for model: String) -> Self {
        let normalized = model.trimmingCharacters(in: .whitespacesAndNewlines)
        return allCases.first { $0.modelID == normalized } ?? .custom
    }
}

public struct ProviderConfiguration: Codable, Equatable, Sendable {
    public static let defaultEndpoint = "https://api.openai.com"
    public static let defaultModel = "gpt-6-sol"

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

public struct ConversionPromptPreset: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var prompt: String

    public init(id: UUID = UUID(), name: String, prompt: String) {
        self.id = id
        self.name = name
        self.prompt = prompt
    }
}

public struct ConversionPromptConfiguration: Codable, Equatable, Sendable {
    public static let maximumPresetCount = 3

    public var presets: [ConversionPromptPreset]
    public var activePresetID: UUID?

    public init(presets: [ConversionPromptPreset] = [], activePresetID: UUID? = nil) {
        self.presets = Array(presets.prefix(Self.maximumPresetCount))
        self.activePresetID = self.presets.contains { $0.id == activePresetID }
            ? activePresetID
            : nil
    }

    public var activePrompt: String {
        guard let activePresetID else { return "" }
        return presets.first { $0.id == activePresetID }?.prompt ?? ""
    }
}

/// More themes can be added without coupling theme selection to the ON/OFF switch.
public enum KeyboardGameTheme: String, CaseIterable, Identifiable, Sendable {
    case rpgDragon
    case spaceLaser
    case persianCat

    public var id: Self { self }
    public var displayName: String {
        switch self {
        case .rpgDragon: "RPG風ドラゴン"
        case .spaceLaser: "宇宙船のレーザー砲"
        case .persianCat: "獲物を狙うペルシャ猫"
        }
    }
}

public struct SharedSettingsStore {
    public static let appGroupIdentifier = "group.org.sumibi.Sumibi-iOS"

    private enum Key {
        static let providerConfiguration = "providerConfiguration"
        static let hapticFeedbackEnabled = "hapticFeedbackEnabled"
        static let conversionCompletionHapticEnabled = "conversionCompletionHapticEnabled"
        static let keyClickSoundEnabled = "keyClickSoundEnabled"
        static let keyboardGameModeEnabled = "keyboardGameModeEnabled"
        static let keyboardGameTheme = "keyboardGameTheme"
        static let userDictionary = "userDictionary"
        static let customSystemPrompt = "customSystemPrompt"
        static let conversionPromptConfiguration = "conversionPromptConfiguration"
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

    public func loadSettingsChatSnapshot() -> SettingsChatSnapshot {
        SettingsChatSnapshot(
            provider: loadProviderConfiguration(),
            hapticFeedbackEnabled: loadHapticFeedbackEnabled(),
            conversionCompletionHapticEnabled: loadConversionCompletionHapticEnabled(),
            keyClickSoundEnabled: loadKeyClickSoundEnabled()
        )
    }

    public func applySettingsChatChanges(
        _ changes: [SettingsChatChange],
        basedOn snapshot: SettingsChatSnapshot
    ) throws {
        guard loadSettingsChatSnapshot() == snapshot else {
            throw SettingsChatError.settingsChanged
        }
        let updated = try snapshot.applying(changes)
        // Validate every action and prepare all throwing work before writing any setting.
        let providerData = try encoder.encode(updated.provider)
        if updated.provider != snapshot.provider {
            defaults.set(providerData, forKey: Key.providerConfiguration)
        }
        if updated.hapticFeedbackEnabled != snapshot.hapticFeedbackEnabled {
            saveHapticFeedbackEnabled(updated.hapticFeedbackEnabled)
        }
        if updated.conversionCompletionHapticEnabled != snapshot.conversionCompletionHapticEnabled {
            saveConversionCompletionHapticEnabled(updated.conversionCompletionHapticEnabled)
        }
        if updated.keyClickSoundEnabled != snapshot.keyClickSoundEnabled {
            saveKeyClickSoundEnabled(updated.keyClickSoundEnabled)
        }
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

    public func loadKeyboardGameModeEnabled() -> Bool {
        defaults.bool(forKey: Key.keyboardGameModeEnabled)
    }

    public func saveKeyboardGameModeEnabled(_ isEnabled: Bool) {
        defaults.set(isEnabled, forKey: Key.keyboardGameModeEnabled)
    }

    public func loadKeyboardGameTheme() -> KeyboardGameTheme {
        defaults.string(forKey: Key.keyboardGameTheme)
            .flatMap(KeyboardGameTheme.init(rawValue:)) ?? .rpgDragon
    }

    public func saveKeyboardGameTheme(_ theme: KeyboardGameTheme) {
        defaults.set(theme.rawValue, forKey: Key.keyboardGameTheme)
    }

    public func saveUserDictionary(_ dictionary: String) {
        defaults.set(dictionary, forKey: Key.userDictionary)
    }

    public func loadConversionPromptConfiguration() -> ConversionPromptConfiguration {
        if
            let data = defaults.data(forKey: Key.conversionPromptConfiguration),
            let configuration = try? decoder.decode(ConversionPromptConfiguration.self, from: data)
        {
            return ConversionPromptConfiguration(
                presets: configuration.presets,
                activePresetID: configuration.activePresetID
            )
        }

        let legacyPrompt = defaults.string(forKey: Key.customSystemPrompt) ?? ""
        guard !legacyPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ConversionPromptConfiguration()
        }
        let preset = ConversionPromptPreset(
            id: UUID(uuidString: "3C307E6D-C21C-45A6-B42B-A6B6700266A1")!,
            name: "プリセット1",
            prompt: legacyPrompt
        )
        return ConversionPromptConfiguration(presets: [preset], activePresetID: preset.id)
    }

    public func saveConversionPromptConfiguration(_ configuration: ConversionPromptConfiguration) throws {
        let normalized = ConversionPromptConfiguration(
            presets: configuration.presets,
            activePresetID: configuration.activePresetID
        )
        defaults.set(try encoder.encode(normalized), forKey: Key.conversionPromptConfiguration)
        defaults.removeObject(forKey: Key.customSystemPrompt)
    }

    public func loadCustomSystemPrompt() -> String {
        loadConversionPromptConfiguration().activePrompt
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

    public func recordUsage(_ usage: TokenUsage, model: String, isSettingsChat: Bool = false) {
        let normalizedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedModel.isEmpty else {
            return
        }
        var statistics = loadUsageStatistics()
        if let index = statistics.firstIndex(where: { $0.model == normalizedModel }) {
            if statistics[index].collectionStartedAt == nil {
                statistics[index].collectionStartedAt = Date()
            }
            if isSettingsChat {
                statistics[index].settingsChatCount += 1
            } else {
                statistics[index].conversionCount += 1
            }
            statistics[index].inputTokens += usage.inputTokens
            statistics[index].cachedInputTokens += usage.cachedInputTokens
            statistics[index].outputTokens += usage.outputTokens
        } else {
            statistics.append(
                ModelUsageStatistics(
                    model: normalizedModel,
                    conversionCount: isSettingsChat ? 0 : 1,
                    settingsChatCount: isSettingsChat ? 1 : 0,
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
    public var settingsChatCount: Int
    public var inputTokens: Int
    public var cachedInputTokens: Int
    public var outputTokens: Int
    public var collectionStartedAt: Date?

    public init(
        model: String,
        conversionCount: Int = 0,
        settingsChatCount: Int = 0,
        inputTokens: Int = 0,
        cachedInputTokens: Int = 0,
        outputTokens: Int = 0,
        collectionStartedAt: Date? = nil
    ) {
        self.model = model
        self.conversionCount = conversionCount
        self.settingsChatCount = settingsChatCount
        self.inputTokens = inputTokens
        self.cachedInputTokens = cachedInputTokens
        self.outputTokens = outputTokens
        self.collectionStartedAt = collectionStartedAt
    }

    private enum CodingKeys: String, CodingKey {
        case model, conversionCount, settingsChatCount
        case inputTokens, cachedInputTokens, outputTokens, collectionStartedAt
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        model = try values.decode(String.self, forKey: .model)
        conversionCount = try values.decode(Int.self, forKey: .conversionCount)
        settingsChatCount = try values.decodeIfPresent(Int.self, forKey: .settingsChatCount) ?? 0
        inputTokens = try values.decode(Int.self, forKey: .inputTokens)
        cachedInputTokens = try values.decode(Int.self, forKey: .cachedInputTokens)
        outputTokens = try values.decode(Int.self, forKey: .outputTokens)
        collectionStartedAt = try values.decodeIfPresent(Date.self, forKey: .collectionStartedAt)
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
        if normalized == "gpt-6-sol" || normalized.hasPrefix("gpt-6-sol-") {
            return ModelPricing(input: 2, cachedInput: 0.2, output: 10)
        }
        if normalized == "gpt-6-luna" || normalized.hasPrefix("gpt-6-luna-") {
            return ModelPricing(input: 0.1, cachedInput: 0.01, output: 0.5)
        }
        if normalized == "gpt-5.6-sol" || normalized.hasPrefix("gpt-5.6-sol-") {
            return ModelPricing(input: 4, cachedInput: 0.4, output: 20)
        }
        if normalized == "gpt-5.6-terra" || normalized.hasPrefix("gpt-5.6-terra-") {
            return ModelPricing(input: 2, cachedInput: 0.2, output: 12)
        }
        return nil
    }
}
