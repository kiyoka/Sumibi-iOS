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
        try testProposals(store)
        try testLegacyUsage(store, defaults)
        try await testTransport(store)
        print("Settings chat checks passed: validation, stale changes, legacy usage, request isolation, conversion compatibility")
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
