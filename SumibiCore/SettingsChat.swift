import Foundation

public enum SettingsChatSetting: String, Codable, CaseIterable, Sendable {
    case model
    case hapticFeedbackEnabled
    case conversionCompletionHapticEnabled
    case keyClickSoundEnabled

    public var title: String {
        switch self {
        case .model: "変換モデル"
        case .hapticFeedbackEnabled: "キー入力時の振動"
        case .conversionCompletionHapticEnabled: "変換完了時の振動"
        case .keyClickSoundEnabled: "キークリック音"
        }
    }
}

public struct SettingsChatChange: Codable, Equatable, Sendable {
    public let setting: SettingsChatSetting
    public let value: String

    public init(setting: SettingsChatSetting, value: String) {
        self.setting = setting
        self.value = value
    }
}

public enum SettingsChatError: Error, Equatable {
    case invalidProposal
    case settingsChanged
}

public struct SettingsChatPayload: Codable, Sendable {
    public let reply: String
    public let changes: [SettingsChatChange]

    public static func decode(_ content: String) throws -> Self {
        let data = Data(content.trimmingCharacters(in: .whitespacesAndNewlines).utf8)
        // Codable alone ignores unknown fields. Reject them before interpreting any action.
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys) == ["reply", "changes"],
              let changes = object["changes"] as? [[String: Any]],
              changes.allSatisfy({ Set($0.keys) == ["setting", "value"] }),
              let payload = try? JSONDecoder().decode(Self.self, from: data),
              !payload.reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              payload.reply.count <= 8_000,
              payload.changes.count <= SettingsChatSetting.allCases.count,
              Set(payload.changes.map(\.setting)).count == payload.changes.count
        else { throw SettingsChatError.invalidProposal }
        return payload
    }
}

public struct SettingsChatSnapshot: Equatable, Sendable {
    public var provider: ProviderConfiguration
    public var hapticFeedbackEnabled: Bool
    public var conversionCompletionHapticEnabled: Bool
    public var keyClickSoundEnabled: Bool

    public func applying(_ changes: [SettingsChatChange]) throws -> Self {
        guard changes.count <= SettingsChatSetting.allCases.count,
              Set(changes.map(\.setting)).count == changes.count
        else { throw SettingsChatError.invalidProposal }
        var result = self
        for change in changes {
            switch change.setting {
            case .model:
                let model = change.value.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !model.isEmpty, model.count <= 200,
                      !model.contains(where: { $0.isWhitespace || $0.isNewline })
                else { throw SettingsChatError.invalidProposal }
                result.provider.model = model
            case .hapticFeedbackEnabled:
                result.hapticFeedbackEnabled = try Self.bool(change.value)
            case .conversionCompletionHapticEnabled:
                result.conversionCompletionHapticEnabled = try Self.bool(change.value)
            case .keyClickSoundEnabled:
                result.keyClickSoundEnabled = try Self.bool(change.value)
            }
        }
        return result
    }

    public func displayValue(for setting: SettingsChatSetting) -> String {
        switch setting {
        case .model: return provider.model
        case .hapticFeedbackEnabled: return hapticFeedbackEnabled ? "ON" : "OFF"
        case .conversionCompletionHapticEnabled: return conversionCompletionHapticEnabled ? "ON" : "OFF"
        case .keyClickSoundEnabled: return keyClickSoundEnabled ? "ON" : "OFF"
        }
    }

    public func value(for setting: SettingsChatSetting) -> String {
        switch setting {
        case .model: provider.model
        case .hapticFeedbackEnabled: String(hapticFeedbackEnabled)
        case .conversionCompletionHapticEnabled: String(conversionCompletionHapticEnabled)
        case .keyClickSoundEnabled: String(keyClickSoundEnabled)
        }
    }

    private static func bool(_ value: String) throws -> Bool {
        switch value {
        case "true": true
        case "false": false
        default: throw SettingsChatError.invalidProposal
        }
    }

    // Only these non-secret values are included in the assistant's context.
    func contextJSON() throws -> String {
        struct ModelChoice: Encodable {
            let name: String
            let modelID: String?
            let summary: String?
        }
        struct Context: Encodable {
            let model: String
            let hapticFeedbackEnabled: Bool
            let conversionCompletionHapticEnabled: Bool
            let keyClickSoundEnabled: Bool
            let modelChoices: [ModelChoice]
        }
        let context = Context(
            model: provider.model,
            hapticFeedbackEnabled: hapticFeedbackEnabled,
            conversionCompletionHapticEnabled: conversionCompletionHapticEnabled,
            keyClickSoundEnabled: keyClickSoundEnabled,
            modelChoices: ModelOption.allCases.map {
                ModelChoice(name: $0.displayName, modelID: $0.modelID, summary: $0.summary)
            }
        )
        return String(decoding: try JSONEncoder().encode(context), as: UTF8.self)
    }
}

public struct SettingsChatMessage: Encodable, Sendable {
    public enum Role: String, Encodable, Sendable { case user, assistant }
    public let role: Role
    public let content: String

    public init(role: Role, content: String) {
        self.role = role
        self.content = content
    }
}

public struct SettingsChatCompletion: Sendable {
    public let content: String
    public let model: String
    public let usage: TokenUsage?
}

// Send a strict response schema only to the known OpenAI endpoint/models.
// Other compatible services use the same JSON instructions and local validation.
struct SettingsChatOutputFormat: Encodable {
    let type = "json_schema"
    let jsonSchema = Definition()
    enum CodingKeys: String, CodingKey { case type; case jsonSchema = "json_schema" }

    struct Definition: Encodable {
        let name = "sumibi_settings_reply"
        let strict = true
        let schema = ObjectSchema(
            properties: [
                "reply": Property(type: "string"),
                "changes": Property(type: "array", items: ObjectSchema(
                    properties: [
                        "setting": Property(type: "string", enumValues: SettingsChatSetting.allCases.map(\.rawValue)),
                        "value": Property(type: "string"),
                    ],
                    required: ["setting", "value"]
                )),
            ],
            required: ["reply", "changes"]
        )
    }

    struct ObjectSchema: Encodable {
        let type = "object"
        let properties: [String: Property]
        let required: [String]
        let additionalProperties = false
    }

    struct Property: Encodable {
        let type: String
        var enumValues: [String]? = nil
        var items: ObjectSchema? = nil
        enum CodingKeys: String, CodingKey { case type, items; case enumValues = "enum" }
    }
}
