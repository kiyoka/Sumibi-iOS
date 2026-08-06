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
    @State private var endpoint = ProviderConfiguration.defaultEndpoint
    @State private var model = ProviderConfiguration.defaultModel
    @State private var apiKey = ""
    @State private var hasStoredAPIKey = false
    @State private var statusMessage = ""
    @State private var testSource = "sumibi yakiniku ga sukidesu ."
    @State private var testResult = ""
    @State private var isTesting = false
    @State private var hapticFeedbackEnabled = true
    @State private var keyClickSoundEnabled = true
    @State private var userDictionary = ""
    @State private var hasAIDataSharingConsent = false

    var body: some View {
        NavigationStack {
            Form {
                introductionSection
                providerSection
                keyboardBehaviorSection
                userDictionarySection
                conversionTestSection
                keyboardSetupSection
                privacySection
            }
            .navigationTitle("Sumibi")
            .task {
                loadSettings()
            }
            .onChange(of: endpoint) { _, newEndpoint in
                hasAIDataSharingConsent = SharedSettingsStore()?
                    .hasAIDataSharingConsent(for: newEndpoint) ?? false
            }
            .onChange(of: hasAIDataSharingConsent) { _, isEnabled in
                updateAIDataSharingConsent(isEnabled)
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

            TextField("モデル名", text: $model)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            SecureField(
                hasStoredAPIKey ? "APIキー（保存済み）" : "APIキー",
                text: $apiKey
            )
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()

            Button("設定を保存") {
                saveSettings()
            }

            if hasStoredAPIKey {
                Button("保存したAPIキーを削除", role: .destructive) {
                    deleteAPIKey()
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
            Toggle("キークリック音", isOn: $keyClickSoundEnabled)
                .onChange(of: keyClickSoundEnabled) { _, isEnabled in
                    SharedSettingsStore()?.saveKeyClickSoundEnabled(isEnabled)
                }
        } header: {
            Text("キーボード設定")
        } footer: {
            Text("どちらも初期設定はONです。クリック音はiOS本体の消音・音量・キーボードの設定に従います。")
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
            Label("登録したユーザー辞書は毎回あわせて送信", systemImage: "character.book.closed")
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
            Text("同意すると、変換対象、最小限の周辺文脈、登録したユーザー辞書を上記の第三者AIへ送信します。送信先でのデータ処理と保存は、利用者が選択したAPIプロバイダーの規約に従います。送信先を変更した場合は、改めて同意が必要です。同意はいつでも取り消せます。")
        }
    }

    private var normalizedEndpointDisplay: String {
        let normalized = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? "未設定" : normalized
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
            hapticFeedbackEnabled = store.loadHapticFeedbackEnabled()
            keyClickSoundEnabled = store.loadKeyClickSoundEnabled()
            userDictionary = store.loadUserDictionary()
            hasAIDataSharingConsent = store.hasAIDataSharingConsent(for: configuration.endpoint)
        }
        do {
            hasStoredAPIKey = try APIKeyStore().load() != nil
        } catch {
            hasStoredAPIKey = false
        }
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
                try APIKeyStore().save(apiKey)
                apiKey = ""
                hasStoredAPIKey = true
            }
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
                    userDictionary: userDictionary
                )
            )
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
