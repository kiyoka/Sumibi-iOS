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

/// A read-only, point-in-time view of usage. No forecast is computed here.
public struct SettingsChatUsageContext: Sendable {
    public let statistics: [ModelUsageStatistics]
    public let capturedAt: Date
    public let timeZone: TimeZone

    public init(
        statistics: [ModelUsageStatistics],
        capturedAt: Date = Date(),
        timeZone: TimeZone = .current
    ) {
        self.statistics = statistics
        self.capturedAt = capturedAt
        self.timeZone = timeZone
    }

    func contextJSON() throws -> String {
        struct ModelUsage: Encodable {
            let model: String
            let collectionStartedAt: String?
            let conversionCount: Int
            let settingsChatCount: Int
            let inputTokens: Int
            let cachedInputTokens: Int
            let outputTokens: Int
            let estimatedCostUSD: String?

            enum CodingKeys: String, CodingKey {
                case model, collectionStartedAt, conversionCount, settingsChatCount
                case inputTokens, cachedInputTokens, outputTokens, estimatedCostUSD
            }

            func encode(to encoder: Encoder) throws {
                var values = encoder.container(keyedBy: CodingKeys.self)
                try values.encode(model, forKey: .model)
                // Explicit nulls distinguish missing history/pricing from zero cost.
                try values.encode(collectionStartedAt, forKey: .collectionStartedAt)
                try values.encode(conversionCount, forKey: .conversionCount)
                try values.encode(settingsChatCount, forKey: .settingsChatCount)
                try values.encode(inputTokens, forKey: .inputTokens)
                try values.encode(cachedInputTokens, forKey: .cachedInputTokens)
                try values.encode(outputTokens, forKey: .outputTokens)
                try values.encode(estimatedCostUSD, forKey: .estimatedCostUSD)
            }
        }
        struct Context: Encodable {
            let capturedAt: String
            let timeZone: String
            let utcOffsetSeconds: Int
            let currency = "USD"
            let scope = "この端末のSumibiが記録した累積統計。今回の回答のAPI費用は未計上。他アプリ・他端末の利用、実際の請求額・残高は含まない。日別履歴はない。"
            let models: [ModelUsage]
            let knownCostSubtotalUSD: String
            let modelsWithUnknownCost: [String]
        }
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = timeZone
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var subtotal = Decimal.zero
        let models = statistics.map { row in
            let cost = row.estimatedCostUSD
            if let cost { subtotal += cost }
            return ModelUsage(
                model: row.model,
                collectionStartedAt: row.collectionStartedAt.map { formatter.string(from: $0) },
                conversionCount: row.conversionCount,
                settingsChatCount: row.settingsChatCount,
                inputTokens: row.inputTokens,
                cachedInputTokens: row.cachedInputTokens,
                outputTokens: row.outputTokens,
                estimatedCostUSD: cost.map { NSDecimalNumber(decimal: $0).stringValue }
            )
        }
        let context = Context(
            capturedAt: formatter.string(from: capturedAt),
            timeZone: timeZone.identifier,
            utcOffsetSeconds: timeZone.secondsFromGMT(for: capturedAt),
            models: models,
            knownCostSubtotalUSD: NSDecimalNumber(decimal: subtotal).stringValue,
            modelsWithUnknownCost: statistics.filter { $0.estimatedCostUSD == nil }.map(\.model)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(context), as: UTF8.self)
    }
}

enum SettingsChatHelp {
    // Use the same theme names and order as the picker and keyboard tap cycle.
    static var gameThemeGuide: String {
        KeyboardGameTheme.allCases.map { theme in
            let description: String
            switch theme {
            case .rpgDragon:
                description = "8ビット風のドラゴンが、ためた力に応じて炎を吹く。"
            case .spaceLaser:
                description = "宇宙船のコアが光り、ためた力に応じて光弾や太いレーザーを放つ。"
            case .persianCat:
                description = "ペルシャ猫がお尻をふりふりしてピンクのボールを狙い、変換で右へダッシュ。ボールをくわえて大きな正面ポーズで約2秒こちらを見る。本物の動物を捕まえる演出ではない。"
            case .rpgWizard:
                description = "魔法使いが白い魔法陣に力をため、変換で魔法を放つ。"
            }
            return "・\(theme.displayName)：\(description)"
        }.joined(separator: "\n")
    }

    static let guide = """
    SumibiはiPhone向けのAI日本語キーボード。英字QWERTYの1画面でローマ字を入力し「変換」を押して自然な日本語にする。自動変換や、かなキーボードへの切替は不要。
    初期設定：SumibiアプリでAPIのURL・モデル・利用者が用意したAPIキーを設定し「設定を保存」。プライバシー欄で第三者AIへの送信に同意。iOSの設定 > 一般 > キーボード > キーボード > 新しいキーボードを追加でSumibiを追加し、Sumibiの「フルアクセスを許可」をON。入力アプリで地球儀からSumibiへ切り替える。
    APIキーが必要な場合は利用者自身がAPI提供者で準備する。アプリのダウンロードは無料だが、設定したAPIの利用料金は別途かかる。Sumibi運営のサーバーは経由せず、設定した第三者AIへ直接送信する。
    範囲変換：入力先アプリで変換したい文字列を選択し、Sumibiの「範囲を変換」を押す。選択した部分だけを変換する。選択がなければSumibiが追跡中の入力を変換する。例えば英語の文章の後にローマ字を入力し、そのローマ字部分だけを選択して変換できる。ホストアプリによって選択の扱いは異なる。
    候補・Undo：初回は候補1件を反映。「さらに変換候補を取得」で別の表現や同音異義語などを追加取得できる（追加API通信あり）。候補バーの候補を押して切替。「Undo」で変換前の原文へ戻せる。候補が画面に収まらない場合は横にスクロールする。
    記号入力：「記号」で記号一覧を開き、使いたい記号を押す。もう一度切替キーを押すと閉じる。通常のQWERTYキーは切り替えない。
    ユーザー辞書：Sumibiアプリの「ユーザー辞書」を開き、1行につき「tari-zu = タリーズ」のように登録して保存。最大100件・2,000文字。登録辞書は変換リクエストへ送信される。チャットでは辞書を読んだり編集したりしない。
    文体プリセット：Sumibiアプリの「文体プリセット」を開き、最大3件の名前付き追加プロンプトを登録できる。「使用するプリセット」で選択するか「使用しない」。各プリセットを開くと編集・効果の比較ができる。論文スタイルなどの文体・表記や出力言語を指定できる。チャットから選択・編集しない。
    利用状況：Sumibiアプリの「利用状況」でモデルごとの集計開始、変換回数、設定チャット回数、トークン数、概算料金を確認。「利用状況をリセット」は確認後に端末の集計をリセットするだけで、API請求・残高は変わらない。
    遊び心のあるキーボード：文字を打つ楽しさを加える、任意のゲーム風演出。初期設定はOFF。前の設定画面へ戻り「遊び心のあるキーボード」の「ゲーム演出」をONにして、「テーマ」のプルダウンから選ぶ。テーマを選ぶだけではONにならない。OFFにすれば通常表示へ戻る。
    通常の文字・数字・記号・空白のタップでエネルギーがたまり、速く打つほど強くたまる。入力を休むとゲージが徐々に減る。通常変換・範囲変換の通信開始で蓄積したエネルギーを放出し、候補帯で演出する。追加候補取得や候補選択では再発射しない。エネルギーは演出専用で、変換の精度・結果・速度やAPIの利用料金には影響せず、追加のAPI通信も発生しない。演出の終了を待たず候補を操作できる。
    現在選べるテーマと特徴：
    \(gameThemeGuide)
    ゲーム演出ONのときは、候補バー左端のキャラクターをタップしても、上記の順番でテーマが切り替わり、最後から先頭へ戻る。通常の文字キーでは切り替わらない。選択は保存される。猫の拡大ポーズは候補帯右端から下方向にキーの上へ重ねて表示し、キーボード上部に余白を追加せず、高さも変えない。猫に重なったキーも操作できる。
    動きが不要な場合は「ゲーム演出」をOFFにする。iOSの「設定」>「アクセシビリティ」>「動作」>「視差効果を減らす」がONのときはキャラクターの動きを抑え、ゲージの値だけ更新する。この演出はiOS 17以降で利用でき、Liquid Glassとは別の機能。
    この会話にはゲーム演出の現在のON/OFFや選択テーマは渡されていないため、現在の状態を推測しない。ゲーム演出やテーマはチャットから変更できないので、設定画面の操作を案内する。
    変換できない場合：保存したAPI設定、第三者AIへの同意、キーボードのフルアクセス、通信状況を確認し、Sumibiアプリの変換テストを使う。認証・利用上限はAPI提供者側も確認する。タイムアウトは15秒固定。
    """
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
