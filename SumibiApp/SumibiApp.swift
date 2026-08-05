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

    var body: some View {
        NavigationStack {
            Form {
                introductionSection
                providerSection
                keyboardBehaviorSection
                conversionTestSection
                keyboardSetupSection
                privacySection
            }
            .navigationTitle("Sumibi")
            .task {
                loadSettings()
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
            Label("変換キーを押したときだけ送信", systemImage: "hand.tap")
            Label("変換対象と最小限の周辺文脈を送信", systemImage: "text.quote")
            Label("登録したユーザー辞書は毎回あわせて送信", systemImage: "character.book.closed")
            Label("キー入力や原文をログへ保存しない", systemImage: "doc.badge.ellipsis")
            Label("Sumibi運営のサーバーを経由しない", systemImage: "arrow.left.arrow.right")
            Label("APIキーは端末内のKeychainへ保存", systemImage: "key")
        } header: {
            Text("プライバシー")
        } footer: {
            Text("送信先でのデータ処理は、利用者が選択したAPIプロバイダーの規約に従います。")
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
                ConversionRequest(source: testSource)
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
