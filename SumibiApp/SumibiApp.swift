import SumibiCore
import SwiftUI
import UIKit

@main
struct SumibiApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

private struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase

    private enum APIField: Hashable {
        case endpoint
        case model
        case apiKey
    }

    @State private var endpoint = ProviderConfiguration.defaultEndpoint
    @State private var model = ProviderConfiguration.defaultModel
    @State private var apiKey = ""
    @State private var savedEndpoint = ""
    @State private var savedModel = ""
    @State private var hasLoadedSettings = false
    @State private var hasStoredAPIKey = false
    @State private var storedAPIKeyDisplay: String?
    @State private var statusMessage = ""
    @State private var testSource = "sumibi yakiniku ga sukidesu ."
    @State private var testResult = ""
    @State private var isTesting = false
    @State private var hapticFeedbackEnabled = true
    @State private var conversionCompletionHapticEnabled = true
    @State private var keyClickSoundEnabled = true
    @State private var userDictionary = ""
    @State private var conversionPromptConfiguration = ConversionPromptConfiguration()
    @State private var hasAIDataSharingConsent = false
    @State private var isShowingAPIKeyDeletionConfirmation = false
    @State private var usageStatistics: [ModelUsageStatistics] = []
    @State private var isShowingUsageResetConfirmation = false
    @FocusState private var focusedAPIField: APIField?

    var body: some View {
        NavigationStack {
            Form {
                introductionSection
                providerSection
                keyboardBehaviorSection
                customSystemPromptSection
                userDictionarySection
                conversionTestSection
                usageSection
                keyboardSetupSection
                privacySection
            }
            .navigationTitle("Sumibi")
            .alert(
                "保存したAPIキーを削除しますか？",
                isPresented: $isShowingAPIKeyDeletionConfirmation
            ) {
                Button("キャンセル", role: .cancel) {}
                Button("削除", role: .destructive) {
                    deleteAPIKey()
                }
            } message: {
                Text("削除すると元に戻せません。再度利用するにはAPIキーの入力が必要です。")
            }
            .task {
                loadSettings()
                loadUsageStatistics()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    loadUsageStatistics()
                }
            }
            .onChange(of: endpoint) { _, newEndpoint in
                hasAIDataSharingConsent = SharedSettingsStore()?
                    .hasAIDataSharingConsent(for: newEndpoint) ?? false
            }
            .onChange(of: hasAIDataSharingConsent) { _, isEnabled in
                updateAIDataSharingConsent(isEnabled)
            }
            .alert(
                "利用状況をリセットしますか？",
                isPresented: $isShowingUsageResetConfirmation
            ) {
                Button("キャンセル", role: .cancel) {}
                Button("リセット", role: .destructive) {
                    SharedSettingsStore()?.resetUsageStatistics()
                    loadUsageStatistics()
                }
            } message: {
                Text("モデルごとのトークン数、概算料金、変換回数を0に戻します。")
            }
        }
    }

    private var introductionSection: some View {
        Section {
            Label("英字QWERTYで入力し、変換キーで日本語へ変換します。", systemImage: "keyboard")
            Text("変換には、利用者が設定したOpenAI互換APIを使用します。")
                .foregroundStyle(.secondary)
        } header: {
            Text("Sumibiについて")
        }
    }

    private var providerSection: some View {
        Section {
            TextField("例：https://api.openai.com", text: $endpoint)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focusedAPIField, equals: .endpoint)

            TextField("モデル名", text: $model)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focusedAPIField, equals: .model)

            SecureField(
                hasStoredAPIKey ? "APIキー（保存済み）" : "APIキー",
                text: $apiKey
            )
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .focused($focusedAPIField, equals: .apiKey)

            LabeledContent("保存済みAPIキー") {
                Text(storedAPIKeyDisplay ?? "未設定")
                    .monospaced()
                    .privacySensitive()
            }

            Button("設定を保存") {
                focusedAPIField = nil
                saveSettings()
            }
            .disabled(!hasUnsavedAPISettings)

            if hasStoredAPIKey {
                Button("保存したAPIキーを削除", role: .destructive) {
                    isShowingAPIKeyDeletionConfirmation = true
                }
            }

            if !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("API設定")
        } footer: {
            Text("エンドポイントとモデルはApp Group、APIキーは共有Keychainへ保存します。")
        }
    }

    private var conversionTestSection: some View {
        Section {
            TextField("変換するローマ字", text: $testSource, axis: .vertical)
                .lineLimit(2 ... 4)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            Button {
                Task {
                    await testConversion()
                }
            } label: {
                if isTesting {
                    HStack {
                        ProgressView()
                        Text("変換中")
                    }
                } else {
                    Text("設定したAPIで変換をテスト")
                }
            }
            .disabled(isTesting || testSource.isEmpty)

            if !testResult.isEmpty {
                Text(testResult)
                    .textSelection(.enabled)
            }
        } header: {
            Text("変換テスト")
        } footer: {
            Text("テスト時も入力内容を設定済みAPIへ送信します。")
        }
    }

    private var usageSection: some View {
        Section {
            if usageStatistics.isEmpty {
                Text("利用履歴はありません。")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(usageStatistics) { statistics in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(statistics.model)
                                .font(.headline)
                                .textSelection(.enabled)
                            Spacer()
                            if let startedAt = statistics.collectionStartedAt {
                                Text(
                                    "集計開始 \(startedAt.formatted(date: .numeric, time: .shortened))"
                                )
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        VStack(spacing: 8) {
                            LabeledContent("変換回数", value: "\(statistics.conversionCount)回")
                            LabeledContent("入力トークン", value: statistics.inputTokens.formatted())
                            if statistics.cachedInputTokens > 0 {
                                LabeledContent(
                                    "うちキャッシュ入力",
                                    value: statistics.cachedInputTokens.formatted()
                                )
                            }
                            LabeledContent("出力トークン", value: statistics.outputTokens.formatted())
                            LabeledContent("合計トークン", value: statistics.totalTokens.formatted())
                            LabeledContent("概算料金") {
                                Text(estimatedCostDisplay(for: statistics))
                                    .monospacedDigit()
                            }
                        }
                        .padding(.leading, 16)
                    }
                    .padding(.vertical, 4)
                }

                Button("利用状況をリセット", role: .destructive) {
                    isShowingUsageResetConfirmation = true
                }
            }
        } header: {
            Text("利用状況")
        } footer: {
            Text("APIレスポンスのトークン数を端末内に記録します。料金はOpenAIのStandard料金（短いコンテキスト）による概算です。料金表にないモデルは不明と表示します。")
        }
    }

    private func estimatedCostDisplay(for statistics: ModelUsageStatistics) -> String {
        guard let cost = statistics.estimatedCostUSD else {
            return "不明"
        }
        return cost.formatted(
            .currency(code: "USD")
                .precision(.fractionLength(6))
        )
    }

    private func loadUsageStatistics() {
        usageStatistics = SharedSettingsStore()?.loadUsageStatistics() ?? []
    }

    private var userDictionarySection: some View {
        Section {
            NavigationLink {
                UserDictionaryEditor(
                    initialText: userDictionary,
                    onSave: { savedText in
                        userDictionary = savedText
                    }
                )
            } label: {
                HStack {
                    Label("ユーザー辞書", systemImage: "character.book.closed")
                    Spacer()
                    Text(userDictionarySummary)
                        .foregroundStyle(.secondary)
                }
            }
        } footer: {
            Text("登録内容はすべての変換リクエストへ送信されます。")
        }
    }

    private var customSystemPromptSection: some View {
        Section {
            NavigationLink {
                ConversionPromptSettingsView(
                    initialConfiguration: conversionPromptConfiguration,
                    onSave: { savedConfiguration in
                        conversionPromptConfiguration = savedConfiguration
                    }
                )
            } label: {
                HStack {
                    Label("文体プリセット", systemImage: "text.bubble")
                    Spacer()
                    Text(activeConversionPromptPresetName)
                        .foregroundStyle(.secondary)
                }
            }
        } footer: {
            Text("出力言語や文体、文章の形式をAIへの追加指示として設定します。")
        }
    }

    private var activeConversionPromptPresetName: String {
        guard let activePresetID = conversionPromptConfiguration.activePresetID else {
            return "使用しない"
        }
        return conversionPromptConfiguration.presets.first { $0.id == activePresetID }?.name
            ?? "使用しない"
    }

    private var userDictionarySummary: String {
        let count = UserDictionary.validate(userDictionary).entries.count
        return count == 0 ? "未設定" : "\(count)件"
    }

    private var keyboardBehaviorSection: some View {
        Section {
            Toggle("キー入力の触覚フィードバック", isOn: $hapticFeedbackEnabled)
                .onChange(of: hapticFeedbackEnabled) { _, isEnabled in
                    SharedSettingsStore()?.saveHapticFeedbackEnabled(isEnabled)
                }
            Toggle("変換完了時の触覚フィードバック", isOn: $conversionCompletionHapticEnabled)
                .onChange(of: conversionCompletionHapticEnabled) { _, isEnabled in
                    SharedSettingsStore()?.saveConversionCompletionHapticEnabled(isEnabled)
                }
            Toggle("キークリック音", isOn: $keyClickSoundEnabled)
                .onChange(of: keyClickSoundEnabled) { _, isEnabled in
                    SharedSettingsStore()?.saveKeyClickSoundEnabled(isEnabled)
                }
        } header: {
            Text("キーボード設定")
        } footer: {
            Text("すべて初期設定はONです。変換完了時は短く2回振動します。クリック音はiOS本体の消音・音量・キーボードの設定に従います。")
        }
    }

    private var keyboardSetupSection: some View {
        Section {
            setupStep(number: 1, text: "「設定を開く」を押します。")
            setupStep(number: 2, text: "キーボード設定で「Sumibi」を追加します。")
            setupStep(number: 3, text: "「フルアクセスを許可」を有効にします。")

            Button("設定を開く") {
                guard let url = URL(string: UIApplication.openSettingsURLString) else {
                    return
                }
                UIApplication.shared.open(url)
            }
        } header: {
            Text("キーボードを有効にする")
        } footer: {
            Text("ネットワーク変換と共有設定の読み取りにフルアクセスが必要です。")
        }
    }

    private var privacySection: some View {
        Section {
            Text("送信先：\(normalizedEndpointDisplay)")
                .font(.footnote)
                .textSelection(.enabled)
            Toggle(
                "この第三者AIへのデータ送信に同意する",
                isOn: $hasAIDataSharingConsent
            )
            Label("変換キーを押したときだけ送信", systemImage: "hand.tap")
            Label("変換対象と最小限の周辺文脈を送信", systemImage: "text.quote")
            Label("ユーザー辞書と変換プロンプトは毎回あわせて送信", systemImage: "character.book.closed")
            Label("キー入力や原文をログへ保存しない", systemImage: "doc.badge.ellipsis")
            Label("Sumibi運営のサーバーを経由しない", systemImage: "arrow.left.arrow.right")
            Label("APIキーは端末内のKeychainへ保存", systemImage: "key")
            Link(
                "プライバシーポリシーを確認",
                destination: URL(string: "https://kiyoka.github.io/Sumibi-iOS/privacy.html")!
            )
        } header: {
            Text("プライバシー")
        } footer: {
            Text("同意すると、変換対象、最小限の周辺文脈、登録したユーザー辞書、変換プロンプトを上記の第三者AIへ送信します。送信先でのデータ処理と保存は、利用者が選択したAPIプロバイダーの規約に従います。送信先を変更した場合は、改めて同意が必要です。同意はいつでも取り消せます。")
        }
    }

    private var normalizedEndpointDisplay: String {
        let normalized = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? "未設定" : normalized
    }

    private var hasUnsavedAPISettings: Bool {
        guard hasLoadedSettings else {
            return false
        }
        return endpoint.trimmingCharacters(in: .whitespacesAndNewlines) != savedEndpoint
            || model.trimmingCharacters(in: .whitespacesAndNewlines) != savedModel
            || !apiKey.isEmpty
    }

    private func updateAIDataSharingConsent(_ isEnabled: Bool) {
        guard let store = SharedSettingsStore() else {
            hasAIDataSharingConsent = false
            statusMessage = "共有設定を利用できません。"
            return
        }
        if isEnabled {
            let normalized = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
            guard URL(string: normalized) != nil, !normalized.isEmpty else {
                hasAIDataSharingConsent = false
                statusMessage = "同意する前に有効なAPIのURLを設定してください。"
                return
            }
            store.saveAIDataSharingConsent(for: normalized)
            hasAIDataSharingConsent = true
            statusMessage = "AIへのデータ送信に同意しました。"
        } else {
            store.revokeAIDataSharingConsent()
            hasAIDataSharingConsent = false
            statusMessage = "AIへのデータ送信の同意を取り消しました。"
        }
    }

    private func setupStep(number: Int, text: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text("\(number)")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(.tint, in: Circle())
            Text(text)
        }
    }

    private func loadSettings() {
        if let store = SharedSettingsStore() {
            let configuration = store.loadProviderConfiguration()
            endpoint = configuration.endpoint
            model = configuration.model
            savedEndpoint = configuration.endpoint
                .trimmingCharacters(in: .whitespacesAndNewlines)
            savedModel = configuration.model
                .trimmingCharacters(in: .whitespacesAndNewlines)
            hapticFeedbackEnabled = store.loadHapticFeedbackEnabled()
            conversionCompletionHapticEnabled = store.loadConversionCompletionHapticEnabled()
            keyClickSoundEnabled = store.loadKeyClickSoundEnabled()
            userDictionary = store.loadUserDictionary()
            conversionPromptConfiguration = store.loadConversionPromptConfiguration()
            hasAIDataSharingConsent = store.hasAIDataSharingConsent(for: configuration.endpoint)
        }
        do {
            let storedAPIKey = try APIKeyStore().load()
            hasStoredAPIKey = storedAPIKey != nil
            storedAPIKeyDisplay = storedAPIKey.flatMap(APIKeyStore.maskedDisplay)
        } catch {
            hasStoredAPIKey = false
            storedAPIKeyDisplay = nil
        }
        hasLoadedSettings = true
    }

    private func saveSettings() {
        guard let store = SharedSettingsStore() else {
            statusMessage = "共有設定を利用できません。"
            return
        }

        do {
            try store.saveProviderConfiguration(
                ProviderConfiguration(
                    endpoint: endpoint.trimmingCharacters(in: .whitespacesAndNewlines),
                    model: model.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            )
            if !apiKey.isEmpty {
                let maskedDisplay = APIKeyStore.maskedDisplay(for: apiKey)
                try APIKeyStore().save(apiKey)
                apiKey = ""
                hasStoredAPIKey = true
                storedAPIKeyDisplay = maskedDisplay
            }
            savedEndpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
            savedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
            statusMessage = "設定を保存しました。"
        } catch {
            statusMessage = "設定を保存できませんでした。"
        }
    }

    private func deleteAPIKey() {
        do {
            try APIKeyStore().delete()
            apiKey = ""
            hasStoredAPIKey = false
            storedAPIKeyDisplay = nil
            statusMessage = "APIキーを削除しました。"
        } catch {
            statusMessage = "APIキーを削除できませんでした。"
        }
    }

    @MainActor
    private func testConversion() async {
        let normalizedEndpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let endpointURL = URL(string: normalizedEndpoint), !normalizedModel.isEmpty else {
            testResult = "APIのURLとモデル名を入力してください。"
            return
        }
        guard SharedSettingsStore()?.hasAIDataSharingConsent(for: normalizedEndpoint) == true else {
            testResult = "プライバシー欄で、第三者AIへのデータ送信に同意してください。"
            return
        }

        saveSettings()
        isTesting = true
        testResult = ""
        defer { isTesting = false }

        do {
            let storedAPIKey = try APIKeyStore().load()
            let client = OpenAICompatibleClient(
                configuration: OpenAICompatibleConfiguration(
                    endpoint: endpointURL,
                    model: normalizedModel,
                    apiKey: storedAPIKey
                )
            )
            let response = try await client.convert(
                ConversionRequest(
                    source: testSource,
                    userDictionary: userDictionary,
                    customSystemPrompt: conversionPromptConfiguration.activePrompt
                )
            )
            if let usage = response.usage {
                SharedSettingsStore()?.recordUsage(
                    usage,
                    model: response.model ?? normalizedModel
                )
                loadUsageStatistics()
            }
            testResult = response.candidates.first ?? "候補がありません。"
        } catch let error as OpenAICompatibleClientError {
            testResult = message(for: error)
        } catch let error as URLError {
            testResult = error.code == .timedOut
                ? "変換がタイムアウトしました。"
                : "ネットワーク通信に失敗しました。"
        } catch {
            testResult = "変換に失敗しました。"
        }
    }

    private func message(for error: OpenAICompatibleClientError) -> String {
        switch error {
        case .invalidEndpoint:
            "APIのURLが無効です。"
        case .invalidResponse, .emptyResponse:
            "APIから有効な候補を取得できませんでした。"
        case .invalidCredentials:
            "APIキーを確認してください。"
        case .rateLimited:
            "APIの利用回数上限に達しました。"
        case .serverError:
            "APIサーバーでエラーが発生しました。"
        case .httpError:
            "APIリクエストに失敗しました。"
        }
    }
}

private struct ConversionPromptSettingsView: View {
    let initialConfiguration: ConversionPromptConfiguration
    let onSave: (ConversionPromptConfiguration) -> Void

    @State private var configuration: ConversionPromptConfiguration

    init(
        initialConfiguration: ConversionPromptConfiguration,
        onSave: @escaping (ConversionPromptConfiguration) -> Void
    ) {
        self.initialConfiguration = initialConfiguration
        self.onSave = onSave
        _configuration = State(initialValue: initialConfiguration)
    }

    var body: some View {
        List {
            Section("使用するプリセット") {
                Picker("現在の設定", selection: $configuration.activePresetID) {
                    Text("使用しない").tag(nil as UUID?)
                    ForEach(configuration.presets) { preset in
                        Text(preset.name).tag(preset.id as UUID?)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
                .onChange(of: configuration.activePresetID) { _, _ in
                    persist()
                }
            }

            Section {
                ForEach(configuration.presets) { preset in
                    NavigationLink {
                        ConversionPromptPresetEditor(
                            initialPreset: preset,
                            onSave: update
                        )
                    } label: {
                        HStack {
                            Text(preset.name)
                            Spacer()
                            if configuration.activePresetID == preset.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                }
                .onDelete(perform: delete)

                Button {
                    addPreset()
                } label: {
                    Label("プリセットを追加", systemImage: "plus")
                }
                .disabled(configuration.presets.count >= ConversionPromptConfiguration.maximumPresetCount)
            } header: {
                Text("保存済みプリセット")
            } footer: {
                Text("最大3件まで登録できます。プリセットを開くと、編集と変換結果の比較ができます。")
            }
        }
        .navigationTitle("文体プリセット")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func addPreset() {
        guard configuration.presets.count < ConversionPromptConfiguration.maximumPresetCount else {
            return
        }
        configuration.presets.append(
            ConversionPromptPreset(
                name: "プリセット\(configuration.presets.count + 1)",
                prompt: ""
            )
        )
        persist()
    }

    private func update(_ preset: ConversionPromptPreset) {
        guard let index = configuration.presets.firstIndex(where: { $0.id == preset.id }) else {
            return
        }
        configuration.presets[index] = preset
        persist()
    }

    private func delete(at offsets: IndexSet) {
        let deletedIDs = offsets.map { configuration.presets[$0].id }
        configuration.presets.remove(atOffsets: offsets)
        if let activePresetID = configuration.activePresetID, deletedIDs.contains(activePresetID) {
            configuration.activePresetID = nil
        }
        persist()
    }

    private func persist() {
        try? SharedSettingsStore()?.saveConversionPromptConfiguration(configuration)
        onSave(configuration)
    }
}

private struct ConversionPromptPresetEditor: View {
    @Environment(\.dismiss) private var dismiss

    private struct Example: Identifiable {
        let title: String
        let prompt: String
        var id: String { title }
    }

    private static let maximumCharacterCount = 1_000
    private static let examples = [
        Example(
            title: "標準に戻す",
            prompt: ""
        ),
        Example(
            title: "中国語（簡体字）",
            prompt: "入力内容の意味を保ったまま、自然な中国語（簡体字）に翻訳してください。"
        ),
        Example(
            title: "韓国語",
            prompt: "入力内容の意味を保ったまま、自然な韓国語に翻訳してください。"
        ),
        Example(
            title: "英語",
            prompt: "入力内容の意味を保ったまま、自然な英語に翻訳してください。"
        ),
        Example(
            title: "論文スタイル",
            prompt: "入力内容の意味を変えず、句読点を日本語の論文で用いられる全角の「，」「．」に統一してください。"
        ),
    ]

    let initialPreset: ConversionPromptPreset
    let onSave: (ConversionPromptPreset) -> Void

    @State private var name: String
    @State private var text: String
    @State private var showsDiscardConfirmation = false
    @State private var showsExampleReplacementConfirmation = false
    @State private var pendingExample: Example?
    @State private var testSource = "ashita made ni kakunin shite kudasai."
    @State private var resultWithoutPrompt = ""
    @State private var resultWithPrompt = ""
    @State private var testMessage = ""
    @State private var isTesting = false

    init(initialPreset: ConversionPromptPreset, onSave: @escaping (ConversionPromptPreset) -> Void) {
        self.initialPreset = initialPreset
        self.onSave = onSave
        _name = State(initialValue: initialPreset.name)
        _text = State(initialValue: initialPreset.prompt)
    }

    private var hasChanges: Bool {
        name != initialPreset.name || text != initialPreset.prompt
    }
    private var exceedsLimit: Bool { text.count > Self.maximumCharacterCount }
    private var normalizedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                TextField("プリセット名", text: $name)
                    .textInputAutocapitalization(.never)
                    .padding(.horizontal)

                Menu {
                    ForEach(Self.examples) { example in
                        Button(example.title) {
                            select(example)
                        }
                    }
                } label: {
                    Label("例文から選ぶ", systemImage: "text.badge.plus")
                }
                .padding(.horizontal)

                ZStack(alignment: .topLeading) {
                    TextEditor(text: $text)
                        .font(.body)
                        .frame(minHeight: 180)
                        .padding(.horizontal, 8)
                    if text.isEmpty {
                        Text("AIへの追加指示を入力してください。\n例：自然な中国語（簡体字）に翻訳してください。")
                            .font(.body)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }
                }

                Text("出力言語、文体、文章の形式などを指定できます。入力内容は変換のたびに設定済みのAIサービスへ送信されます。APIキー、パスワードなどの秘密情報は入力しないでください。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                Text("\(text.count)/\(Self.maximumCharacterCount)文字")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(exceedsLimit ? .red : .secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.horizontal)

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Text("効果を比較")
                        .font(.headline)

                    TextField("変換するローマ字", text: $testSource, axis: .vertical)
                        .lineLimit(2 ... 4)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    Button {
                        Task { await comparePromptEffect() }
                    } label: {
                        if isTesting {
                            HStack {
                                ProgressView()
                                Text("比較中")
                            }
                        } else {
                            Text("設定なし／ありを比較")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        isTesting
                            || testSource.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || exceedsLimit
                    )

                    if !testMessage.isEmpty {
                        Text(testMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }

                    if !resultWithoutPrompt.isEmpty || !resultWithPrompt.isEmpty {
                        comparisonResult(title: "プロンプトなし", result: resultWithoutPrompt)
                        comparisonResult(title: "現在のプロンプトあり", result: resultWithPrompt)
                    }

                    Text("比較では同じ入力を2回送信するため、2回分のAPI利用が発生します。編集中のプロンプトを保存せずに試せます。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
        }
        .navigationTitle("変換プロンプト")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    requestDismissal()
                } label: {
                    Label("戻る", systemImage: "chevron.left")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("保存") {
                    onSave(
                        ConversionPromptPreset(
                            id: initialPreset.id,
                            name: normalizedName,
                            prompt: text
                        )
                    )
                    dismiss()
                }
                .disabled(exceedsLimit || !hasChanges || normalizedName.isEmpty)
            }
        }
        .interactiveDismissDisabled(hasChanges)
        .confirmationDialog(
            "現在の内容を例文で置き換えますか？",
            isPresented: $showsExampleReplacementConfirmation,
            titleVisibility: .visible
        ) {
            Button("置き換える") {
                if let pendingExample {
                    text = pendingExample.prompt
                }
                pendingExample = nil
            }
            Button("キャンセル", role: .cancel) {
                pendingExample = nil
            }
        }
        .confirmationDialog(
            "変更を破棄しますか？",
            isPresented: $showsDiscardConfirmation,
            titleVisibility: .visible
        ) {
            Button("破棄", role: .destructive) { dismiss() }
            Button("編集を続ける", role: .cancel) {}
        } message: {
            Text("保存していない変更があります。")
        }
        .onChange(of: text) { _, _ in clearComparison() }
        .onChange(of: name) { _, _ in clearComparison() }
        .onChange(of: testSource) { _, _ in clearComparison() }
    }

    private func comparisonResult(title: String, result: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            Text(result)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                .textSelection(.enabled)
        }
    }

    private func select(_ example: Example) {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            text = example.prompt
        } else {
            pendingExample = example
            showsExampleReplacementConfirmation = true
        }
    }

    private func requestDismissal() {
        if hasChanges {
            showsDiscardConfirmation = true
        } else {
            dismiss()
        }
    }

    private func clearComparison() {
        resultWithoutPrompt = ""
        resultWithPrompt = ""
        testMessage = ""
    }

    @MainActor
    private func comparePromptEffect() async {
        guard let store = SharedSettingsStore() else {
            testMessage = "共有設定を利用できません。"
            return
        }
        let configuration = store.loadProviderConfiguration()
        guard
            let endpointURL = URL(string: configuration.endpoint),
            store.hasAIDataSharingConsent(for: configuration.endpoint)
        else {
            testMessage = "API設定と第三者AIへのデータ送信への同意を確認してください。"
            return
        }

        isTesting = true
        clearComparison()
        defer { isTesting = false }

        do {
            let apiKey = try APIKeyStore().load()
            let client = OpenAICompatibleClient(
                configuration: OpenAICompatibleConfiguration(
                    endpoint: endpointURL,
                    model: configuration.model,
                    apiKey: apiKey
                )
            )
            let dictionary = store.loadUserDictionary()
            async let baseline = client.convert(
                ConversionRequest(source: testSource, userDictionary: dictionary)
            )
            async let customized = client.convert(
                ConversionRequest(
                    source: testSource,
                    userDictionary: dictionary,
                    customSystemPrompt: text
                )
            )
            let (baselineResponse, customizedResponse) = try await (baseline, customized)
            resultWithoutPrompt = baselineResponse.candidates.first ?? "候補がありません。"
            resultWithPrompt = customizedResponse.candidates.first ?? "候補がありません。"
            if let usage = baselineResponse.usage {
                store.recordUsage(usage, model: baselineResponse.model ?? configuration.model)
            }
            if let usage = customizedResponse.usage {
                store.recordUsage(usage, model: customizedResponse.model ?? configuration.model)
            }
        } catch {
            testMessage = "比較に失敗しました。API設定や通信状態を確認してください。"
        }
    }
}

private struct UserDictionaryEditor: View {
    @Environment(\.dismiss) private var dismiss

    let initialText: String
    let onSave: (String) -> Void

    @State private var text: String
    @State private var errors: [UserDictionaryValidationError] = []
    @State private var showsDiscardConfirmation = false
    @State private var saveMessage = ""

    init(initialText: String, onSave: @escaping (String) -> Void) {
        self.initialText = initialText
        self.onSave = onSave
        _text = State(initialValue: initialText)
    }

    private var hasChanges: Bool { text != initialText }

    private var nonemptyLineCount: Int {
        text.split(separator: "\n").filter {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.count
    }

    private var exceedsLimit: Bool {
        nonemptyLineCount > UserDictionary.maximumEntryCount
            || text.count > UserDictionary.maximumCharacterCount
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !errors.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(errors) { error in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(error.lineNumber.map { "\($0)行目：\(error.reason)" } ?? error.reason)
                                    .font(.footnote.bold())
                                    .foregroundStyle(.red)
                                if let line = error.line {
                                    Text(line)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 150)
                .padding(.horizontal)
            }

            ZStack(alignment: .topLeading) {
                TextEditor(text: $text)
                    .font(.body.monospaced())
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 8)
                    .onChange(of: text) { _, _ in
                        errors = []
                        saveMessage = ""
                    }
                if text.isEmpty {
                    Text("sumibi = Sumibi\nkiyoka = 清香\nopenai = OpenAI")
                        .font(.body.monospaced())
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                }
            }

            HStack {
                Text("1行につき「よみ = 変換後」")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(nonemptyLineCount)件・\(text.count)/2,000文字")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(exceedsLimit ? .red : .secondary)
            }
            .padding(.horizontal)

            if !saveMessage.isEmpty {
                Text(saveMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            }
        }
        .navigationTitle("ユーザー辞書")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    requestDismissal()
                } label: {
                    Label("戻る", systemImage: "chevron.left")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("保存") {
                    save()
                }
                .disabled(exceedsLimit)
            }
        }
        .interactiveDismissDisabled(hasChanges)
        .confirmationDialog(
            "変更を破棄しますか？",
            isPresented: $showsDiscardConfirmation,
            titleVisibility: .visible
        ) {
            Button("破棄", role: .destructive) { dismiss() }
            Button("編集を続ける", role: .cancel) {}
        } message: {
            Text("保存していない変更があります。")
        }
    }

    private func requestDismissal() {
        if hasChanges {
            showsDiscardConfirmation = true
        } else {
            dismiss()
        }
    }

    private func save() {
        let result = UserDictionary.validate(text)
        guard result.isValid else {
            errors = result.errors
            return
        }
        guard let store = SharedSettingsStore() else {
            saveMessage = "共有設定を利用できません。"
            return
        }
        store.saveUserDictionary(text)
        onSave(text)
        dismiss()
    }
}
