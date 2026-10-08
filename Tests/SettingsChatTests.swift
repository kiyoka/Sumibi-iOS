import Foundation

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
}

private func expectFailure(_ operation: () throws -> Void) {
    do {
        try operation()
        preconditionFailure("Invalid change was accepted")
    } catch {}
}

private final class MockChatProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> Data)?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let data = try Self.handler!(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    override func stopLoading() {}
}

@main
private struct SettingsChatTests {
    static func main() async throws {
        let suite = "sumibi-settings-chat-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SharedSettingsStore(defaults: defaults)
        testGameSettings(store, defaults)
        try testProposals(store)
        try testLegacyUsage(store, defaults)
        try testUsageContext(store)
        try await testTransport(store)
        try await testConsultationTransport(store)
        print("Chat checks passed: settings safety, legacy usage, usage context, consultation requests, conversion compatibility (mock API; not a live LLM evaluation)")
    }

    static func testGameSettings(_ store: SharedSettingsStore, _ defaults: UserDefaults) {
        expect(!store.loadKeyboardGameModeEnabled(), "Game mode must default to OFF")
        expect(store.loadKeyboardGameTheme() == .rpgDragon, "Default prototype must be the dragon")
        store.saveKeyboardGameTheme(.rpgDragon)
        expect(!store.loadKeyboardGameModeEnabled(), "Choosing a theme must not enable game mode")
        store.saveKeyboardGameModeEnabled(true)
        let reloaded = SharedSettingsStore(defaults: defaults)
        expect(reloaded.loadKeyboardGameModeEnabled(), "Game setting must persist")
        expect(reloaded.loadKeyboardGameTheme() == .rpgDragon, "Theme must persist")
        store.saveKeyboardGameTheme(.spaceLaser)
        expect(reloaded.loadKeyboardGameTheme() == .spaceLaser, "Spaceship theme must persist")
        expect(reloaded.loadKeyboardGameModeEnabled(), "Changing theme must preserve ON")
        store.saveKeyboardGameModeEnabled(false)
        expect(reloaded.loadKeyboardGameTheme() == .spaceLaser, "OFF must preserve the selected spaceship")
        store.saveKeyboardGameTheme(.rpgDragon)
        expect(!reloaded.loadKeyboardGameModeEnabled(), "Switching back must preserve OFF")
        store.saveKeyboardGameTheme(.persianCat)
        expect(reloaded.loadKeyboardGameTheme() == .persianCat, "Cat theme must persist")
        expect(!reloaded.loadKeyboardGameModeEnabled(), "Selecting cat must preserve OFF")
        for theme in [KeyboardGameTheme.rpgArcher, .rpgWizard] {
            store.saveKeyboardGameTheme(theme)
            expect(reloaded.loadKeyboardGameTheme() == theme, "New fantasy themes must persist")
            expect(!reloaded.loadKeyboardGameModeEnabled(), "New themes must preserve OFF")
            store.saveKeyboardGameModeEnabled(true)
            expect(reloaded.loadKeyboardGameTheme() == theme, "Enabling must preserve fantasy theme")
            store.saveKeyboardGameModeEnabled(false)
        }
        expect(KeyboardGameTheme.allCases.count == 5, "All implemented themes must be selectable")
        let cycle: [KeyboardGameTheme] = [.rpgDragon, .spaceLaser, .persianCat, .rpgArcher, .rpgWizard]
        expect(KeyboardGameTheme.allCases == cycle, "Picker and tap cycle must share the specified order")
        for enabled in [false, true] {
            store.saveKeyboardGameModeEnabled(enabled)
            store.saveKeyboardGameTheme(.rpgDragon)
            for index in 1...10 {
                store.saveKeyboardGameTheme(reloaded.loadKeyboardGameTheme().next)
                expect(reloaded.loadKeyboardGameTheme() == cycle[index % cycle.count], "Cycle must persist and wrap over two rounds")
                expect(reloaded.loadKeyboardGameModeEnabled() == enabled, "Cycling must not change ON/OFF")
            }
        }
        expect(KeyboardGameTheme.rpgArcher.displayName == "弓使いのチャージショット", "Picker must identify archer")
        expect(KeyboardGameTheme.rpgWizard.displayName == "魔法使いの白い魔法陣", "Picker must identify wizard")
        expect(KeyboardGameTheme.persianCat.displayName == "獲物を狙うペルシャ猫", "Picker must identify cat")
        expect(KeyboardGameTheme.spaceLaser.displayName == "宇宙船のレーザー砲", "Picker must identify spaceship")
        defaults.set("future-theme", forKey: "keyboardGameTheme")
        expect(reloaded.loadKeyboardGameTheme() == .rpgDragon, "Unknown themes must fall back safely")
        store.saveKeyboardGameModeEnabled(false)
        expect(!reloaded.loadKeyboardGameModeEnabled(), "OFF must persist without resetting the theme")
        store.saveKeyboardGameTheme(.rpgDragon)
    }

    static func testProposals(_ store: SharedSettingsStore) throws {
        let preset = ConversionPromptPreset(name: "PRIVATE_PRESET_NAME", prompt: "PRIVATE_PRESET_BODY")
        try store.saveProviderConfiguration(ProviderConfiguration(model: "gpt-5.6-terra"))
        let originalPrompts = ConversionPromptConfiguration(presets: [preset], activePresetID: preset.id)
        try store.saveConversionPromptConfiguration(originalPrompts)
        let original = store.loadSettingsChatSnapshot()
        let payload = try SettingsChatPayload.decode("""
        {"reply":"変更案です","changes":[
          {"setting":"model","value":"gpt-6-luna"},
          {"setting":"keyClickSoundEnabled","value":"false"}
        ]}
        """)
        _ = try original.applying(payload.changes)
        expect(store.loadSettingsChatSnapshot() == original, "A proposal must not save settings")
        try store.applySettingsChatChanges(payload.changes, basedOn: original)
        let updated = store.loadSettingsChatSnapshot()
        expect(updated.provider.model == "gpt-6-luna", "Model did not change")
        expect(!updated.keyClickSoundEnabled, "Sound did not change")
        expect(store.loadConversionPromptConfiguration() == originalPrompts, "Preset settings changed")
        expect(updated.provider.endpoint == original.provider.endpoint, "Endpoint changed")
        expect(updated.hapticFeedbackEnabled == original.hapticFeedbackEnabled, "Unrequested setting changed")

        expectFailure {
            try store.applySettingsChatChanges([SettingsChatChange(setting: .model, value: "custom-model")], basedOn: original)
        }
        expect(store.loadSettingsChatSnapshot() == updated, "A stale proposal changed settings")

        let invalidJSON = [
            #"{"reply":"変更します","changes":[{"setting":"timeout","value":"30"}]}"#,
            #"{"reply":"変更します","changes":[],"endpoint":"https://other.example"}"#,
            #"{"reply":"変更します","changes":[{"setting":"model","value":"custom","extra":true}]}"#,
            #"{"reply":"変更します","changes":[{"setting":"model","value":"a"},{"setting":"model","value":"b"}]}"#,
            #"{"reply":"変更します","changes":[{"setting":"keyClickSoundEnabled","value":false}]}"#,
            #"{"reply":"変更します","changes":[{"setting":"activePresetID","value":"none"}]}"#,
            #"{"reply":"変更します","changes":[{"setting":"model","value":"gpt-6-sol"},{"setting":"activePresetID","value":"none"}]}"#,
            #"{"reply":"変更しました","changes":[{"setting":"keyboardGameModeEnabled","value":"true"}]}"#,
            #"{"reply":"変更しました","changes":[{"setting":"keyboardGameTheme","value":"persianCat"}]}"#,
        ]
        for json in invalidJSON {
            expectFailure { _ = try SettingsChatPayload.decode(json) }
            expect(store.loadConversionPromptConfiguration() == originalPrompts, "Unsupported request changed presets")
        }
        for change in [
            SettingsChatChange(setting: .model, value: " "),
            SettingsChatChange(setting: .hapticFeedbackEnabled, value: "off"),
        ] {
            expectFailure { _ = try updated.applying([change]) }
            expectFailure {
                try store.applySettingsChatChanges([
                    SettingsChatChange(setting: .model, value: "gpt-6-sol"), change,
                ], basedOn: updated)
            }
            expect(store.loadSettingsChatSnapshot() == updated, "An invalid multi-setting plan partially saved")
        }

        try store.applySettingsChatChanges([
            SettingsChatChange(setting: .model, value: "gpt-5.6-terra"),
        ], basedOn: updated)
        expect(store.loadProviderConfiguration().model == "gpt-5.6-terra", "Explicit Terra choice was lost")
        let answer = try SettingsChatPayload.decode(#"{"reply":"現在のモデルです","changes":[]}"#)
        expect(answer.changes.isEmpty, "An informational answer contains changes")
    }

    static func testLegacyUsage(_ store: SharedSettingsStore, _ defaults: UserDefaults) throws {
        defaults.set(Data("""
        [{"model":"gpt-6-sol","conversionCount":7,"inputTokens":10,"cachedInputTokens":2,"outputTokens":4}]
        """.utf8), forKey: "usageStatistics")
        expect(store.loadUsageStatistics().first?.settingsChatCount == 0, "Legacy statistics did not decode")
        store.recordUsage(TokenUsage(inputTokens: 20, outputTokens: 8), model: "gpt-6-sol", isSettingsChat: true)
        let stats = store.loadUsageStatistics().first!
        expect(stats.conversionCount == 7, "Chat was counted as a conversion")
        expect(stats.settingsChatCount == 1, "Chat count was not added")
        expect(stats.inputTokens == 30 && stats.outputTokens == 12, "Chat tokens were not included")
        store.resetUsageStatistics()
        let reset = store.loadUsageStatistics().first!
        expect(reset.conversionCount == 0 && reset.settingsChatCount == 0 && reset.totalTokens == 0,
               "Usage reset did not include chat")
    }

    static func testTransport(_ store: SharedSettingsStore) async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockChatProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let client = OpenAICompatibleClient(configuration: OpenAICompatibleConfiguration(
            endpoint: URL(string: "https://api.openai.com")!, model: "gpt-6-sol", apiKey: "TEST_ONLY_KEY"
        ), session: session)
        let snapshot = store.loadSettingsChatSnapshot()
        MockChatProtocol.handler = { request in
            expect(request.url?.path == "/v1/chat/completions", "Wrong endpoint")
            expect(request.timeoutInterval == 15, "Chat timeout is not fixed at 15 seconds")
            expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer TEST_ONLY_KEY", "Missing authentication")
            let data = try requestBody(request)
            let bodyText = String(decoding: data, as: UTF8.self)
            expect(!bodyText.contains("TEST_ONLY_KEY"), "API key leaked into the messages")
            expect(!bodyText.contains("PRIVATE_PRESET_BODY"), "Preset text leaked into chat context")
            expect(!bodyText.contains("PRIVATE_PRESET_NAME"), "Preset name leaked into chat context")
            let context = try JSONSerialization.jsonObject(with: Data(snapshot.contextJSON().utf8)) as! [String: Any]
            expect(context["presets"] == nil && context["activePresetID"] == nil, "Preset context remains enabled")
            expect(!bodyText.contains("PRIVATE_DICTIONARY"), "Dictionary leaked into chat context")
            let body = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            let format = body["response_format"] as? [String: Any]
            expect(format?["type"] as? String == "json_schema", "OpenAI structured output schema missing")
            let definition = format!["json_schema"] as! [String: Any]
            let schema = definition["schema"] as! [String: Any]
            let properties = schema["properties"] as! [String: Any]
            let changes = properties["changes"] as! [String: Any]
            let items = changes["items"] as! [String: Any]
            let itemProperties = items["properties"] as! [String: Any]
            let setting = itemProperties["setting"] as! [String: Any]
            let allowed = setting["enum"] as! [String]
            expect(allowed.count == 4 && !allowed.contains("activePresetID"), "Preset action remains in schema")
            expect(body["reasoning_effort"] as? String == "none", "Existing model options lost")
            return try response(content: #"{"reply":"候補です","changes":[{"setting":"model","value":"gpt-6-luna"}]}"#)
        }
        store.saveUserDictionary("PRIVATE_DICTIONARY")
        let completion = try await client.chatForSettings(
            messages: [SettingsChatMessage(role: .user, content: "安いモデルにして")], snapshot: snapshot
        )
        expect(completion.usage?.totalTokens == 14, "Usage did not decode")
        let decoded = try SettingsChatPayload.decode(completion.content)
        expect(decoded.changes.first?.value == "gpt-6-luna",
               "Structured reply did not decode")

        MockChatProtocol.handler = { request in
            let body = try JSONSerialization.jsonObject(with: requestBody(request)) as! [String: Any]
            let messages = body["messages"] as! [[String: String]]
            let instructions = messages.first!["content"]!
            expect(instructions.contains("modelChoices"), "Model catalog missing from chat context")
            for option in ModelOption.allCases {
                expect(instructions.contains(option.displayName), "Picker choice missing from chat context")
                if let modelID = option.modelID {
                    expect(instructions.contains(modelID), "Picker model ID missing from chat context")
                }
                if let summary = option.summary {
                    expect(instructions.contains(summary), "Picker description missing from chat context")
                }
            }
            expect(instructions.contains("changesは空"), "Model-list questions could request changes")
            expect(instructions.contains("利用可能モデル一覧を取得したものではありません"),
                   "Model catalog could be mistaken for verified API availability")
            return try response(content: #"{"reply":"GPT-6 Sol、GPT-6 Luna、自由入力を選べます。API側の利用可否は未確認です。","changes":[]}"#)
        }
        let beforeList = store.loadSettingsChatSnapshot()
        let listCompletion = try await client.chatForSettings(
            messages: [SettingsChatMessage(role: .user, content: "使えるモデルの一覧を見たい")],
            snapshot: beforeList
        )
        let listPayload = try SettingsChatPayload.decode(listCompletion.content)
        expect(listPayload.changes.isEmpty, "Model-list answer contains settings changes")
        expect(store.loadSettingsChatSnapshot() == beforeList, "Model-list answer changed saved settings")

        MockChatProtocol.handler = { request in
            let body = try JSONSerialization.jsonObject(with: requestBody(request)) as! [String: Any]
            let messages = body["messages"] as! [[String: String]]
            expect(messages.first!["content"]!.contains("「文体プリセット」を開く"),
                   "Preset request is not redirected to the settings screen")
            return try response(content: #"{"reply":"前の設定画面へ戻って「文体プリセット」を開いてください。","changes":[]}"#)
        }
        let presetAnswer = try await client.chatForSettings(
            messages: [SettingsChatMessage(role: .user, content: "論文スタイルに切り替えて")], snapshot: snapshot
        )
        let presetPayload = try SettingsChatPayload.decode(presetAnswer.content)
        expect(presetPayload.changes.isEmpty,
               "Preset guidance contains settings changes")

        let compatible = OpenAICompatibleClient(configuration: OpenAICompatibleConfiguration(
            endpoint: URL(string: "https://compatible.example/v1")!, model: "custom-model", apiKey: nil
        ), session: session)
        MockChatProtocol.handler = { request in
            let body = try JSONSerialization.jsonObject(with: requestBody(request)) as! [String: Any]
            expect(body["response_format"] == nil, "Unsupported schema forced on compatible service")
            expect(body["reasoning_effort"] == nil, "Model-specific options forced on free-input model")
            return try response(content: #"{"reply":"説明です","changes":[]}"#)
        }
        _ = try await compatible.chatForSettings(messages: [], snapshot: snapshot)

        MockChatProtocol.handler = { request in
            let body = try JSONSerialization.jsonObject(with: requestBody(request)) as! [String: Any]
            expect(body["response_format"] == nil, "Conversion contract was changed")
            return try response(content: #"{"candidates":["タリーズ"]}"#)
        }
        let conversion = try await client.convert(ConversionRequest(source: "tari-zu"))
        expect(conversion.candidates == ["タリーズ"], "Existing conversion no longer works")
    }

    static func response(content: String) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "model": "gpt-6-sol",
            "choices": [["message": ["role": "assistant", "content": content]]],
            "usage": ["prompt_tokens": 10, "completion_tokens": 4],
        ])
    }

    static func testUsageContext(_ store: SharedSettingsStore) throws {
        let now = ISO8601DateFormatter().date(from: "2026-10-05T03:00:00Z")!
        let rows = [
            ModelUsageStatistics(model: "gpt-6-sol", conversionCount: 7, settingsChatCount: 3,
                                 inputTokens: 500_000, collectionStartedAt: now.addingTimeInterval(-10 * 86_400)),
            ModelUsageStatistics(model: "custom-model", conversionCount: 2, inputTokens: 100,
                                 collectionStartedAt: now.addingTimeInterval(-5 * 86_400)),
            ModelUsageStatistics(model: "gpt-5.6-terra", inputTokens: 10, cachedInputTokens: 5, outputTokens: 2),
        ]
        let context = SettingsChatUsageContext(statistics: rows, capturedAt: now,
                                              timeZone: TimeZone(identifier: "Asia/Tokyo")!)
        let data = Data(try context.contextJSON().utf8)
        let object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        expect(object["capturedAt"] as? String == "2026-10-05T12:00:00.000+09:00", "Local captured time missing")
        expect(object["timeZone"] as? String == "Asia/Tokyo", "Time zone missing")
        expect(object["utcOffsetSeconds"] as? Int == 32_400, "UTC offset missing")
        expect(object["currency"] as? String == "USD", "Cost currency missing")
        let models = object["models"] as! [[String: Any]]
        for (row, model) in zip(rows, models) {
            let serialized = model["estimatedCostUSD"] as? String
            expect(serialized == row.estimatedCostUSD.map { NSDecimalNumber(decimal: $0).stringValue },
                   "Chat cost differs from the existing usage calculation")
        }
        expect(models[0]["estimatedCostUSD"] as? String == "1", "Fixed evaluation fixture cost should be 1 USD")
        expect(models[0]["settingsChatCount"] as? Int == 3, "Chat count not sent")
        expect(models[1]["estimatedCostUSD"] is NSNull, "Unknown price was not explicit null")
        expect(models[2]["collectionStartedAt"] is NSNull, "Unknown start time was fabricated")
        expect(object["modelsWithUnknownCost"] as? [String] == ["custom-model"], "Unknown-price models missing")
        let known = rows.compactMap(\.estimatedCostUSD).reduce(Decimal.zero, +)
        expect(object["knownCostSubtotalUSD"] as? String == NSDecimalNumber(decimal: known).stringValue,
               "Known subtotal includes unknown prices")
        expect(object["forecast"] == nil && object["dailyCost"] == nil, "App must not precompute the LLM forecast")

        let empty = try JSONSerialization.jsonObject(with: Data(SettingsChatUsageContext(
            statistics: [], capturedAt: now
        ).contextJSON().utf8)) as! [String: Any]
        expect((empty["models"] as! [Any]).isEmpty, "Empty usage was fabricated")
        expect(empty["knownCostSubtotalUSD"] as? String == "0", "Empty subtotal incorrect")

        let reset = store.loadUsageStatistics()
        let before = store.loadSettingsChatSnapshot()
        _ = try SettingsChatUsageContext(statistics: reset).contextJSON()
        expect(store.loadUsageStatistics() == reset && store.loadSettingsChatSnapshot() == before,
               "Reading usage context changed saved data")
        expect(reset.allSatisfy { $0.totalTokens == 0 }, "Reset test statistics were not retained")

        for start in [now, now.addingTimeInterval(-60), now.addingTimeInterval(60)] {
            let short = SettingsChatUsageContext(statistics: [
                ModelUsageStatistics(model: "gpt-6-sol", collectionStartedAt: start),
            ], capturedAt: now)
            let json = try JSONSerialization.jsonObject(with: Data(short.contextJSON().utf8)) as! [String: Any]
            let model = (json["models"] as! [[String: Any]])[0]
            expect(model["estimatedCostUSD"] as? String == "0", "Recorded zero became unknown")
            expect(model["collectionStartedAt"] is String, "Short/future timestamp was discarded")
        }
    }

    static func testConsultationTransport(_ store: SharedSettingsStore) async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockChatProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let client = OpenAICompatibleClient(configuration: OpenAICompatibleConfiguration(
            endpoint: URL(string: "https://api.openai.com")!, model: "gpt-6-sol", apiKey: "TEST_ONLY_KEY"
        ), session: session)
        let snapshot = store.loadSettingsChatSnapshot()
        let now = ISO8601DateFormatter().date(from: "2026-10-05T03:00:00Z")!
        let gameEnabled = store.loadKeyboardGameModeEnabled()
        let gameTheme = store.loadKeyboardGameTheme()
        let fixedUsage = SettingsChatUsageContext(statistics: [
            ModelUsageStatistics(model: "gpt-6-sol", inputTokens: 500_000,
                                 collectionStartedAt: now.addingTimeInterval(-10 * 86_400)),
        ], capturedAt: now, timeZone: TimeZone(identifier: "Asia/Tokyo")!)
        var history: [SettingsChatMessage] = []
        for (question, reply) in [
            ("今どれくらい費用がかかっていますか？", "記録された概算は1 USDです。"),
            ("今後15日でどれくらい費用がかかりそうですか？", "同じペースなら追加約1.5 USDです。"),
            ("では30日なら？", "追加約3 USDです。"),
            ("2倍使ったら今後1週間は？", "追加約1.4 USDです。"),
            ("範囲だけ変換するには？", "文字列を選択して「範囲を変換」を押してください。"),
            ("遊び心のあるキーボードについて教えて", "打鍵でエネルギーをため、変換で放出する任意のゲーム風演出です。設定からONにできます。"),
            ("どんなキャラクターを選べる？", "ドラゴン、宇宙船、ペルシャ猫、弓使い、魔法使いを選べます。"),
            ("猫にして", "前の設定画面の「遊び心のあるキーボード」でテーマから「獲物を狙うペルシャ猫」を選んでください。未使用ならゲーム演出もONにしてください。"),
            ("キャラクターをタップするとどうなる？", "候補バー左端のキャラクターをタップすると次のテーマへ切り替わり、一周すると最初に戻ります。"),
            ("遊ぶと料金や変換精度は変わる？", "演出自体では追加API通信は発生せず、変換結果や料金は変わりません。ただし通常の変換・相談にはAPI利用料金が発生します。"),
            ("動かないのはなぜ？", "ゲーム演出のON/OFFと、iOSの「視差効果を減らす」を確認してください。ここでは現在の設定は確認できません。"),
            ("ゲーム演出をOFFにして", "前の設定画面へ戻り「遊び心のあるキーボード」の「ゲーム演出」をOFFにしてください。"),
        ] {
            history.append(SettingsChatMessage(role: .user, content: question))
            let expectedHistoryCount = history.count
            MockChatProtocol.handler = { request in
                let data = try requestBody(request)
                let text = String(decoding: data, as: UTF8.self)
                expect(!text.contains("TEST_ONLY_KEY") && !text.contains("PRIVATE_DICTIONARY")
                       && !text.contains("PRIVATE_PRESET_NAME") && !text.contains("PRIVATE_PRESET_BODY"),
                       "Private data was included in the consultation")
                let body = try JSONSerialization.jsonObject(with: data) as! [String: Any]
                let messages = body["messages"] as! [[String: String]]
                expect(messages.count == expectedHistoryCount + 1, "Conversation history lost")
                expect(messages.last?["content"] == question, "Arbitrary question changed")
                let instructions = messages.first!["content"]!
                for required in ["<operation_guide>", "<examples>", "<usage_context>",
                                 "未来の見積もりはあなた自身が統計から計算", "固定30日の回答にしない",
                                 "今回渡されたusage_contextの最新統計", "changesを空", "1日未満",
                                 "実際の請求", "範囲を変換", "tari-zu = タリーズ",
                                 "ゲーム演出のON/OFF・テーマ変更もチャットからの変更対象外",
                                 "初期設定はOFF", "速く打つほど強くたまる", "徐々に減る",
                                 "ピンクのボール", "約2秒", "白い魔法陣", "視差効果を減らす",
                                 "追加のAPI通信も発生しない", "現在の状態を推測しない",
                                 "通常の文字キーでは切り替わらない"] {
                    expect(instructions.contains(required), "Consultation instructions missing: \(required)")
                }
                let themeNames = KeyboardGameTheme.allCases.map(\.displayName)
                let themeLines = instructions.components(separatedBy: "\n").filter { $0.hasPrefix("・") }
                expect(themeLines.count == themeNames.count, "Theme catalog duplicated or incomplete")
                for (line, name) in zip(themeLines, themeNames) {
                    expect(line.hasPrefix("・\(name)：") && line.count > name.count + 2,
                           "Theme names, descriptions or cycle order differ from picker")
                }
                let usageJSON = instructions.components(separatedBy: "<usage_context>\n").last!
                    .components(separatedBy: "\n</usage_context>").first!
                let usage = try JSONSerialization.jsonObject(with: Data(usageJSON.utf8)) as! [String: Any]
                let model = (usage["models"] as! [[String: Any]])[0]
                expect(model["estimatedCostUSD"] as? String == "1", "Real fixture confused with example")
                expect(request.timeoutInterval == 15, "Consultation timeout changed")
                return try response(content: String(decoding: JSONSerialization.data(withJSONObject: [
                    "reply": reply, "changes": [],
                ]), as: UTF8.self))
            }
            let completion = try await client.chatForSettings(messages: history, snapshot: snapshot,
                                                              usageContext: fixedUsage)
            let payload = try SettingsChatPayload.decode(completion.content)
            expect(payload.changes.isEmpty, "Informational mock answer contained settings changes")
            expect(store.loadSettingsChatSnapshot() == snapshot, "Consultation changed settings")
            expect(store.loadKeyboardGameModeEnabled() == gameEnabled
                   && store.loadKeyboardGameTheme() == gameTheme, "Consultation changed game settings")
            history.append(SettingsChatMessage(role: .assistant, content: completion.content))
        }
    }

    static func requestBody(_ request: URLRequest) throws -> Data {
        if let data = request.httpBody { return data }
        let stream = request.httpBodyStream!
        stream.open()
        defer { stream.close() }
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let length = stream.read(&buffer, maxLength: buffer.count)
            if length <= 0 { break }
            result.append(buffer, count: length)
        }
        return result
    }
}
