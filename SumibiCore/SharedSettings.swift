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

public enum AIProvider: String, CaseIterable, Codable, Identifiable, Sendable {
    case openAI, google, other

    public var id: Self { self }
    public var displayName: String {
        switch self {
        case .openAI: "OpenAI"
        case .google: "Google"
        case .other: "その他"
        }
    }
    public var defaultEndpoint: String {
        switch self {
        case .openAI: ProviderConfiguration.defaultEndpoint
        case .google: "https://generativelanguage.googleapis.com/v1beta/openai"
        case .other: ""
        }
    }
}

public enum GeminiModelOption: String, CaseIterable, Identifiable, Sendable {
    case quality = "gemini-3.6-flash"
    case economy = "gemini-3.5-flash-lite"

    public var id: Self { self }
    public var displayName: String {
        switch self {
        case .quality: "精度重視：Gemini 3.6 Flash"
        case .economy: "速度・費用重視：Gemini 3.5 Flash-Lite"
        }
    }
}

public struct ProviderConfiguration: Codable, Equatable, Sendable {
    public static let defaultEndpoint = "https://api.openai.com"
    public static let defaultModel = "gpt-6-sol"
    public static let defaultGoogleModel = GeminiModelOption.quality.rawValue

    public var endpoint: String
    public var model: String
    public var provider: AIProvider

    public init(
        endpoint: String = Self.defaultEndpoint,
        model: String = Self.defaultModel,
        provider: AIProvider = .openAI
    ) {
        self.endpoint = endpoint
        self.model = model
        self.provider = provider
    }

    private enum CodingKeys: String, CodingKey { case endpoint, model, provider }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        endpoint = try values.decode(String.self, forKey: .endpoint)
        model = try values.decode(String.self, forKey: .model)
        provider = try values.decodeIfPresent(AIProvider.self, forKey: .provider)
            ?? (URL(string: endpoint)?.host?.lowercased() == "api.openai.com" ? .openAI
                : URL(string: endpoint)?.host?.lowercased() == "generativelanguage.googleapis.com" ? .google : .other)
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
    case rpgWizard

    public var id: Self { self }
    public var next: Self {
        let themes = Self.allCases
        guard let index = themes.firstIndex(of: self) else { return .rpgDragon }
        return themes[(index + 1) % themes.count]
    }
    public var displayName: String {
        switch self {
        case .rpgDragon: "RPG風ドラゴン"
        case .spaceLaser: "宇宙船のレーザー砲"
        case .persianCat: "獲物を狙うペルシャ猫"
        case .rpgWizard: "魔法使いの白い魔法陣"
        }
    }
}

public struct SharedSettingsStore {
    public static let appGroupIdentifier = "group.org.sumibi.Sumibi-iOS"

    private enum Key {
        static let providerConfiguration = "providerConfiguration"
        static let providerConfigurations = "providerConfigurations"
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
                ? (configuration.provider == .google
                    ? ProviderConfiguration.defaultGoogleModel : ProviderConfiguration.defaultModel)
                : configuration.model,
            provider: configuration.provider
        )
    }

    public func saveProviderConfiguration(_ configuration: ProviderConfiguration) throws {
        // Materialize provider attribution while the previous endpoint is still active.
        let migratedUsageData: Data?
        if let usageData = defaults.data(forKey: Key.usageStatistics),
           let rows = (try? JSONSerialization.jsonObject(with: usageData)) as? [[String: Any]],
           rows.contains(where: { $0["provider"] == nil }) {
            migratedUsageData = try encoder.encode(loadUsageStatistics())
        } else {
            migratedUsageData = nil
        }
        var configurations = (defaults.data(forKey: Key.providerConfigurations)
            .flatMap { try? decoder.decode([AIProvider: ProviderConfiguration].self, from: $0) }) ?? [:]
        let previous = loadProviderConfiguration()
        if configurations[previous.provider] == nil {
            configurations[previous.provider] = previous
        }
        configurations[configuration.provider] = configuration
        let data = try encoder.encode(configuration)
        let allData = try encoder.encode(configurations)
        if let migratedUsageData {
            defaults.set(migratedUsageData, forKey: Key.usageStatistics)
        }
        defaults.set(allData, forKey: Key.providerConfigurations)
        defaults.set(data, forKey: Key.providerConfiguration)
    }

    public func loadProviderConfiguration(for provider: AIProvider) -> ProviderConfiguration {
        if let data = defaults.data(forKey: Key.providerConfigurations),
           let configurations = try? decoder.decode([AIProvider: ProviderConfiguration].self, from: data),
           let configuration = configurations[provider] {
            return configuration
        }
        let active = loadProviderConfiguration()
        if active.provider == provider { return active }
        return ProviderConfiguration(
            endpoint: provider.defaultEndpoint,
            model: provider == .openAI ? ProviderConfiguration.defaultModel
                : provider == .google ? ProviderConfiguration.defaultGoogleModel : "",
            provider: provider
        )
    }

    public func resetProviderConfiguration() {
        defaults.removeObject(forKey: Key.providerConfiguration)
        defaults.removeObject(forKey: Key.providerConfigurations)
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
        // Removed themes (including the former archer) use the default without changing ON/OFF.
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
        var migrated = statistics
        if let rawRows = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] {
            let legacyProvider = loadProviderConfiguration().provider
            for index in migrated.indices where index < rawRows.count {
                if rawRows[index]["provider"] == nil {
                    migrated[index].provider = legacyProvider
                }
            }
        }
        return migrated.sorted {
            $0.id.localizedStandardCompare($1.id) == .orderedAscending
        }
    }

    public func recordUsage(
        _ usage: TokenUsage, model: String, provider: AIProvider = .openAI,
        isSettingsChat: Bool = false, at timestamp: Date = Date()
    ) {
        let normalizedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedModel.isEmpty else {
            return
        }
        var statistics = loadUsageStatistics()
        let requestCost = ModelPricing.pricing(for: normalizedModel, provider: provider, at: timestamp)?
            .estimatedCost(for: usage)
        if let index = statistics.firstIndex(where: { $0.model == normalizedModel && $0.provider == provider }) {
            if statistics[index].collectionStartedAt == nil {
                statistics[index].collectionStartedAt = timestamp
            }
            if isSettingsChat {
                statistics[index].settingsChatCount += 1
            } else {
                statistics[index].conversionCount += 1
            }
            statistics[index].inputTokens += usage.inputTokens
            statistics[index].cachedInputTokens += usage.cachedInputTokens
            statistics[index].outputTokens += usage.outputTokens
            statistics[index].unitemizedTokens += usage.unitemizedTokens
            if provider == .google, let requestCost {
                statistics[index].recordedCostUSD = (statistics[index].recordedCostUSD ?? 0) + requestCost
            }
        } else {
            statistics.append(
                ModelUsageStatistics(
                    model: normalizedModel,
                    provider: provider,
                    conversionCount: isSettingsChat ? 0 : 1,
                    settingsChatCount: isSettingsChat ? 1 : 0,
                    inputTokens: usage.inputTokens,
                    cachedInputTokens: usage.cachedInputTokens,
                    outputTokens: usage.outputTokens,
                    unitemizedTokens: usage.unitemizedTokens,
                    collectionStartedAt: timestamp,
                    recordedCostUSD: provider == .google ? requestCost : nil
                )
            )
        }
        if let data = try? encoder.encode(statistics) {
            defaults.set(data, forKey: Key.usageStatistics)
        }
    }

    public func resetUsageStatistics() {
        let reset = loadUsageStatistics().map {
            ModelUsageStatistics(model: $0.model, provider: $0.provider, collectionStartedAt: Date())
        }
        if let data = try? encoder.encode(reset) {
            defaults.set(data, forKey: Key.usageStatistics)
        }
    }
}

public struct ModelUsageStatistics: Codable, Equatable, Identifiable, Sendable {
    public var id: String { "\(provider.rawValue):\(model)" }

    public let model: String
    public var provider: AIProvider
    public var conversionCount: Int
    public var settingsChatCount: Int
    public var inputTokens: Int
    public var cachedInputTokens: Int
    public var outputTokens: Int
    public var unitemizedTokens: Int
    public var collectionStartedAt: Date?
    public var recordedCostUSD: Decimal?

    public init(
        model: String,
        provider: AIProvider = .openAI,
        conversionCount: Int = 0,
        settingsChatCount: Int = 0,
        inputTokens: Int = 0,
        cachedInputTokens: Int = 0,
        outputTokens: Int = 0,
        unitemizedTokens: Int = 0,
        collectionStartedAt: Date? = nil,
        recordedCostUSD: Decimal? = nil
    ) {
        self.model = model
        self.provider = provider
        self.conversionCount = conversionCount
        self.settingsChatCount = settingsChatCount
        self.inputTokens = inputTokens
        self.cachedInputTokens = cachedInputTokens
        self.outputTokens = outputTokens
        self.unitemizedTokens = unitemizedTokens
        self.collectionStartedAt = collectionStartedAt
        self.recordedCostUSD = recordedCostUSD
    }

    private enum CodingKeys: String, CodingKey {
        case model, provider, conversionCount, settingsChatCount
        case inputTokens, cachedInputTokens, outputTokens, unitemizedTokens
        case collectionStartedAt, recordedCostUSD
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        model = try values.decode(String.self, forKey: .model)
        provider = try values.decodeIfPresent(AIProvider.self, forKey: .provider) ?? .openAI
        conversionCount = try values.decode(Int.self, forKey: .conversionCount)
        settingsChatCount = try values.decodeIfPresent(Int.self, forKey: .settingsChatCount) ?? 0
        inputTokens = try values.decode(Int.self, forKey: .inputTokens)
        cachedInputTokens = try values.decode(Int.self, forKey: .cachedInputTokens)
        outputTokens = try values.decode(Int.self, forKey: .outputTokens)
        unitemizedTokens = try values.decodeIfPresent(Int.self, forKey: .unitemizedTokens) ?? 0
        collectionStartedAt = try values.decodeIfPresent(Date.self, forKey: .collectionStartedAt)
        recordedCostUSD = try values.decodeIfPresent(Decimal.self, forKey: .recordedCostUSD)
    }

    public var totalTokens: Int {
        inputTokens + outputTokens + unitemizedTokens
    }

    public var estimatedCostUSD: Decimal? {
        if provider == .google && unitemizedTokens > 0 { return nil }
        if provider == .google, let recordedCostUSD { return recordedCostUSD }
        return ModelPricing.pricing(for: model, provider: provider)?
            .estimatedCost(for: TokenUsage(inputTokens: inputTokens,
                                           cachedInputTokens: cachedInputTokens,
                                           outputTokens: outputTokens))
    }
}

private struct ModelPricing {
    let input: Decimal
    let cachedInput: Decimal
    let output: Decimal

    func estimatedCost(for usage: TokenUsage) -> Decimal {
        let cached = min(usage.cachedInputTokens, usage.inputTokens)
        return (Decimal(usage.inputTokens - cached) * input
                + Decimal(cached) * cachedInput
                + Decimal(usage.outputTokens) * output) / 1_000_000
    }

    static func pricing(for model: String, provider: AIProvider, at date: Date = Date()) -> ModelPricing? {
        let normalized = model.lowercased()
        if provider == .google {
            // Google Gemini API paid-tier Standard text pricing, checked 2026-10-31.
            // https://ai.google.dev/gemini-api/docs/pricing
            if normalized == GeminiModelOption.quality.rawValue {
                let introductory = date < ISO8601DateFormatter().date(from: "2027-01-01T00:00:00Z")!
                return introductory
                    ? ModelPricing(input: 0.75, cachedInput: 0.075, output: 3.75)
                    : ModelPricing(input: 1.5, cachedInput: 0.15, output: 7.5)
            }
            if normalized == GeminiModelOption.economy.rawValue {
                return ModelPricing(input: 0.3, cachedInput: 0.03, output: 2.5)
            }
            return nil
        }
        guard provider == .openAI else { return nil }
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
