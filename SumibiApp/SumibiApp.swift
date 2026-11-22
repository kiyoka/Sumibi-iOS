import DeclaredAgeRange
import FoundationModels
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

    private enum PCCQuotaDisplay {
        case available, approaching, reached, unsupportedOS, ineligible, notReady

        var label: String {
            switch self {
            case .available: "利用可能"
            case .approaching: "1日の上限が近づいています"
            case .reached: "1日の上限に達しました"
            case .unsupportedOS: "iOS 27以降が必要です"
            case .ineligible: "端末または地域が非対応です"
            case .notReady: "現在利用できません"
            }
        }
    }

    private enum APIField: Hashable {
        case endpoint
        case model
        case apiKey
    }

    @State private var endpoint = ProviderConfiguration.defaultEndpoint
    @State private var provider = AIProvider.openAI
    @State private var model = ProviderConfiguration.defaultModel
    @State private var selectedModelOption = ModelOption.selection(
        for: ProviderConfiguration.defaultModel
    )
    @State private var selectedGeminiModel: GeminiModelOption? = .economy
    @State private var apiKey = ""
    @State private var savedEndpoint = ""
    @State private var savedModel = ""
    @State private var savedProvider = AIProvider.openAI
    @State private var hasLoadedSettings = false
    @State private var hasStoredAPIKey = false
    @State private var storedAPIKeyDisplay: String?
    @State private var statusMessage = ""
    @State private var testSource = "sumibi yakiniku ga sukidesu ."
    @State private var externalTestSource = "sumibi yakiniku ga sukidesu ."
    @State private var appleTestResult = ""
    @State private var externalTestResult = ""
    @State private var isTesting = false
    @State private var hapticFeedbackEnabled = true
    @State private var conversionCompletionHapticEnabled = true
    @State private var keyClickSoundEnabled = true
    @State private var keyboardGameModeEnabled = false
    @State private var keyboardGameTheme = KeyboardGameTheme.rpgDragon
    @State private var userDictionary = ""
    @State private var conversionPromptConfiguration = ConversionPromptConfiguration()
    @State private var hasAIDataSharingConsent = false
    @State private var pccPreferred = true
    @State private var pccConversionCount = 0
    @State private var pccChatCount = 0
    @State private var pccDailyUsage: [PCCDailyUsage] = []
    @State private var pccQuotaStatus = PCCQuotaDisplay.notReady
    @State private var pccQuotaResetDate: Date?
    @State private var pccQuotaCheckedAt: Date?
    @State private var isShowingAPIKeyDeletionConfirmation = false
    @State private var usageStatistics: [ModelUsageStatistics] = []
    @State private var isShowingUsageResetConfirmation = false
    @FocusState private var focusedAPIField: APIField?

    var body: some View {
        NavigationStack {
            Form {
                introductionSection
                appleAISection
                settingsChatSection
                appleConversionTestSection
                keyboardBehaviorSection
                keyboardGameSection
                customSystemPromptSection
                userDictionarySection
                usageSection
                keyboardSetupSection
                providerSection
                privacySection
                Section("このアプリについて") {
                    NavigationLink {
                        LicenseView()
                    } label: {
                        Label("ライセンス", systemImage: "doc.text")
                    }
                }
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
                    if let store = SharedSettingsStore() {
                        keyboardGameModeEnabled = store.loadKeyboardGameModeEnabled()
                        keyboardGameTheme = store.loadKeyboardGameTheme()
                    }
                }
            }
            .onChange(of: endpoint) { _, newEndpoint in
                hasAIDataSharingConsent = SharedSettingsStore()?
                    .hasAIDataSharingConsent(for: newEndpoint) ?? false
                refreshStoredAPIKey(for: newEndpoint)
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
                Text("AppleのAIの日別履歴・変換・チャット回数と、外部AIのモデルごとのトークン数、概算料金、変換・チャット回数を0に戻します。")
            }
        }
    }

    private var introductionSection: some View {
        Section {
            Label("英字QWERTYで入力し、変換キーで日本語へ変換します。", systemImage: "keyboard")
        } header: {
            Text("Sumibiについて")
        }
    }

    private var appleAISection: some View {
        Section {
            Label("ローマ字から日本語へ変換", systemImage: "character.cursor.ibeam")
            Label("チャットで使い方や費用を質問", systemImage: "bubble.left.and.bubble.right")
            Text(AppleAIAvailabilityCopy.requirements)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Link("対応機種と条件をAppleで確認", destination: URL(string: "https://support.apple.com/ja-jp/121115")!)
            Toggle("変換とチャットでAppleのAIを優先", isOn: $pccPreferred)
                .onChange(of: pccPreferred) { _, preferred in
                    SharedSettingsStore()?.savePCCPreferred(preferred)
                }
            LabeledContent("1日の利用枠", value: pccQuotaStatus.label)
            if let pccQuotaResetDate {
                LabeledContent(
                    "利用枠の更新予定",
                    value: pccQuotaResetDate.formatted(date: .numeric, time: .shortened)
                )
            } else if case .reached = pccQuotaStatus {
                LabeledContent("利用枠の更新予定", value: "Appleから未通知")
            }
            Button("利用枠の状態を更新", systemImage: "arrow.clockwise") {
                loadUsageStatistics()
            }
            if let pccQuotaCheckedAt {
                Text("状態確認：\(pccQuotaCheckedAt.formatted(date: .numeric, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("AppleのAIでできること")
        } footer: {
            Text("AppleのAIは無料ですが、1日の利用上限があります。利用できないiPhoneや上限到達後も使う場合は、画面下の「外部AI（オプション）」にご自身のAPIキーを設定してください。外部AIのAPI料金が発生する場合があります。")
        }
    }

    private var providerSection: some View {
        Section {
            Text("AppleのAIの1日の上限後、またはAppleのAIを優先しない場合に使います。OpenAI／GeminiなどのAPIキーはご自身で用意してください。接続先ごとのAPIキーは端末のKeychainに保存します。テスト時も入力内容を選択した外部AIへ送信します。")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Picker("外部AIの接続先", selection: Binding(
                get: { provider },
                set: { selectProvider($0) }
            )) {
                ForEach(AIProvider.allCases) { option in
                    Text(option.displayName).tag(option)
                }
            }

            if provider == .other {
                TextField("OpenAI互換APIのURL", text: $endpoint)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedAPIField, equals: .endpoint)
            } else {
                LabeledContent("エンドポイント", value: endpoint)
            }

            if let url = URL(string: endpoint.trimmingCharacters(in: .whitespacesAndNewlines)),
               GeminiAgeGate.applies(to: url) {
                Text("Geminiは18歳以上が対象です。Google Cloudの請求が有効なプロジェクトのAPIキーを使用し、無料枠のキーは使用しないでください。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if #available(iOS 26.0, *) {
                    GeminiAgeConfirmationView()
                } else {
                    Text("Geminiの年齢確認にはiOS 26以降が必要です。この端末ではOpenAIなど別の接続先をご利用ください。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if provider == .openAI {
                Picker("モデル", selection: $selectedModelOption) {
                    ForEach(ModelOption.allCases) { option in
                        Text(option.pickerLabel).tag(option)
                    }
                }
                .onChange(of: selectedModelOption) { _, newValue in
                    if let modelID = newValue.modelID {
                        model = modelID
                    } else if ModelOption.selection(for: model) != .custom {
                        model = ""
                    }
                }
                .accessibilityLabel("モデル")
            } else if provider == .google {
                Picker("モデル", selection: $selectedGeminiModel) {
                    ForEach(GeminiModelOption.recommendedCases) { option in
                        Text(option.displayName).tag(Optional(option))
                    }
                    Text("自由入力").tag(nil as GeminiModelOption?)
                }
                .onChange(of: selectedGeminiModel) { _, selection in
                    if let selection {
                        model = selection.rawValue
                    } else if GeminiModelOption.recommendedSelection(for: model) != nil {
                        // Clear only a previous recommendation; keep loaded custom model IDs.
                        model = ""
                    }
                }
                .accessibilityLabel("モデル")
            }

            if provider == .other || (provider == .openAI && selectedModelOption == .custom)
                || (provider == .google && selectedGeminiModel == nil) {
                TextField("モデル名を入力", text: $model)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedAPIField, equals: .model)
                    .accessibilityLabel("自由入力のモデル名")
            } else {
                LabeledContent("モデルID") {
                    Text(model)
                        .monospaced()
                        .textSelection(.enabled)
                }
            }

            SecureField(
                hasStoredAPIKey ? "\(provider.displayName)のAPIキー（保存済み）"
                    : "\(provider.displayName)のAPIキー",
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

            Toggle("この外部AIへのデータ送信に同意する", isOn: $hasAIDataSharingConsent)

            Button("設定を保存") {
                focusedAPIField = nil
                saveSettings()
            }
            .disabled(
                !hasUnsavedAPISettings
                    || endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            )

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
            TextField("外部AIで変換するローマ字", text: $externalTestSource, axis: .vertical)
                .lineLimit(2 ... 4)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            Button {
                Task { await testExternalConversion() }
            } label: {
                if isTesting {
                    HStack { ProgressView(); Text("変換中") }
                } else {
                    Text("設定した外部AIで変換をテスト")
                }
            }
            .disabled(isTesting || externalTestSource.isEmpty || hasUnsavedAPISettings)

            if !externalTestResult.isEmpty {
                Text(externalTestResult).textSelection(.enabled)
            }
        } header: {
            Text("外部AI（オプション）")
        }
    }

    private var appleConversionTestSection: some View {
        Section {
            TextField("変換するローマ字", text: $testSource, axis: .vertical)
                .lineLimit(2 ... 4)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            Button {
                Task {
                    await testAppleConversion()
                }
            } label: {
                if isTesting {
                    HStack {
                        ProgressView()
                        Text("変換中")
                    }
                } else {
                    Text("AppleのAI変換をテスト")
                }
            }
            .disabled(isTesting || testSource.isEmpty)

            if !appleTestResult.isEmpty {
                Text(appleTestResult)
                    .textSelection(.enabled)
            }
        } header: {
            Text("AppleのAI変換テスト")
        } footer: {
            Text("外部AIの設定とは別に、AppleのAIだけで変換を確認します。入力内容はAppleへ送信します。")
        }
    }

    private var settingsChatSection: some View {
        Section {
            NavigationLink {
                SettingsChatView(onSettingsChanged: {
                    loadSettings()
                    loadUsageStatistics()
                })
            } label: {
                Label("チャットで質問", systemImage: "bubble.left.and.bubble.right")
            }
            .disabled(!hasLoadedSettings)
        } footer: {
            Text(hasUnsavedAPISettings
                 ? "チャットは保存済みの接続先を使います。編集中の外部AI設定は保存後に反映されます。"
                 : "AppleのAIを優先して使い方や概算費用を質問できます。上限後は設定済みの外部AIへ切り替わります。")
        }
    }

    private var usageSection: some View {
        Section {
            NavigationLink {
                PCCDailyHistoryView()
            } label: {
                Label("AppleのAI・日別履歴", systemImage: "calendar")
            }
            if pccConversionCount > 0 {
                LabeledContent("AppleのAI変換回数", value: "\(pccConversionCount)回")
            }
            if pccChatCount > 0 {
                LabeledContent("AppleのAIチャット回数", value: "\(pccChatCount)回")
            }
            if usageStatistics.isEmpty && pccConversionCount == 0
                && pccChatCount == 0 && pccDailyUsage.isEmpty {
                Text("利用履歴はありません。")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(usageStatistics) { statistics in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("\(statistics.provider.displayName) · \(statistics.model)")
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
                            if statistics.settingsChatCount > 0 {
                                LabeledContent("設定チャット回数", value: "\(statistics.settingsChatCount)回")
                            }
                            LabeledContent("入力トークン", value: statistics.inputTokens.formatted())
                            if statistics.cachedInputTokens > 0 {
                                LabeledContent(
                                    "うちキャッシュ入力",
                                    value: statistics.cachedInputTokens.formatted()
                                )
                            }
                            LabeledContent("出力トークン", value: statistics.outputTokens.formatted())
                            if statistics.unitemizedTokens > 0 {
                                LabeledContent("内訳不明のトークン", value: statistics.unitemizedTokens.formatted())
                            }
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
            Text("AppleのAIは、この版以降の変換・チャット成功回数と、確認できた上限状態を日付別に記録します。旧版の累計は日別履歴に振り分けられません。正確な残り回数・上限回数は表示できません。外部AIの料金は概算です。")
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
        refreshPCCQuotaStatus()
        let store = SharedSettingsStore()
        usageStatistics = store?.loadUsageStatistics() ?? []
        pccConversionCount = store?.loadPCCConversionCount() ?? 0
        pccChatCount = store?.loadPCCChatCount() ?? 0
        pccDailyUsage = store?.loadPCCDailyUsage() ?? []
    }

    private func refreshPCCQuotaStatus() {
        pccQuotaCheckedAt = Date()
        pccQuotaResetDate = nil
        guard #available(iOS 27.0, *) else {
            pccQuotaStatus = .unsupportedOS
            return
        }
        let model = PrivateCloudComputeLanguageModel()
        switch model.availability {
        case .available:
            break
        case .unavailable(.deviceNotEligible):
            pccQuotaStatus = .ineligible
            return
        case .unavailable:
            pccQuotaStatus = .notReady
            return
        }
        let quota = model.quotaUsage
        pccQuotaResetDate = quota.resetDate
        if quota.isLimitReached {
            pccQuotaStatus = .reached
            SharedSettingsStore()?.recordPCCLimitReached()
        } else {
            SharedSettingsStore()?.recordPCCQuotaObservation(isLimitReached: false)
            if case .belowLimit(let detail) = quota.status, detail.isApproachingLimit {
                pccQuotaStatus = .approaching
            } else {
                pccQuotaStatus = .available
            }
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
            Text("すべて初期設定はONです。変換完了時は短く2回振動します。クリック音はキーの種類で変わり、iPhoneのメディア音量に合わせて再生します。消音モードでは鳴りません。音のON/OFFは上のスイッチで設定してください。フルアクセスが無効な場合はiOS標準のクリック音を使用します。")
        }
    }

    private var keyboardGameSection: some View {
        Section {
            Toggle("ゲーム演出", isOn: $keyboardGameModeEnabled)
                .onChange(of: keyboardGameModeEnabled) { _, enabled in
                    SharedSettingsStore()?.saveKeyboardGameModeEnabled(enabled)
                }
            Picker("テーマ", selection: $keyboardGameTheme) {
                ForEach(KeyboardGameTheme.allCases) { theme in
                    Text(theme.displayName).tag(theme)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: keyboardGameTheme) { _, theme in
                SharedSettingsStore()?.saveKeyboardGameTheme(theme)
            }
        } header: {
            Text("遊び心のあるキーボード")
        } footer: {
            Text("初期設定はOFFです。入力で力をため、変換すると候補バーでドラゴンの炎、宇宙船のレーザー、猫のダッシュ、魔法使いの白い魔法陣の4種類を楽しめます。速く打つほど強くたまり、入力を休むと減っていきます。変換結果やAPIの利用料金には影響しません。「視差効果を減らす」がONの場合は演出の動きを控えます。")
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
            Text("優先する変換・チャット先：AppleのAI（対応端末のみ）")
                .font(.footnote)
            Text("外部AIの送信先：\(normalizedEndpointDisplay)")
                .font(.footnote)
                .textSelection(.enabled)
            Label("変換・チャット・テスト操作時に送信", systemImage: "hand.tap")
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
            Text("AppleのAI（Private Cloud Compute）を優先する場合、変換内容やチャットの会話・設定値・利用統計をAppleへ送信します。1日の上限後は、APIキーと送信同意のある外部AIへ切り替わり、API料金が発生する場合があります。第三者AIへの同意は接続先ごとに保存・取消できます。")
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
            || provider != savedProvider
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
            store.revokeAIDataSharingConsent(for: endpoint)
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
            provider = configuration.provider
            endpoint = configuration.endpoint
            model = configuration.model
            selectedModelOption = ModelOption.selection(for: configuration.model)
            selectedGeminiModel = GeminiModelOption.recommendedSelection(for: configuration.model)
            savedEndpoint = configuration.endpoint
                .trimmingCharacters(in: .whitespacesAndNewlines)
            savedModel = configuration.model
                .trimmingCharacters(in: .whitespacesAndNewlines)
            savedProvider = configuration.provider
            hapticFeedbackEnabled = store.loadHapticFeedbackEnabled()
            conversionCompletionHapticEnabled = store.loadConversionCompletionHapticEnabled()
            keyClickSoundEnabled = store.loadKeyClickSoundEnabled()
            keyboardGameModeEnabled = store.loadKeyboardGameModeEnabled()
            keyboardGameTheme = store.loadKeyboardGameTheme()
            userDictionary = store.loadUserDictionary()
            conversionPromptConfiguration = store.loadConversionPromptConfiguration()
            hasAIDataSharingConsent = store.hasAIDataSharingConsent(for: configuration.endpoint)
            pccPreferred = store.loadPCCPreferred()
        }
        refreshStoredAPIKey(for: endpoint)
        hasLoadedSettings = true
    }

    private func refreshStoredAPIKey(for endpoint: String) {
        do {
            let storedAPIKey = try APIKeyStore().load(for: endpoint)
            hasStoredAPIKey = storedAPIKey != nil
            storedAPIKeyDisplay = storedAPIKey.flatMap(APIKeyStore.maskedDisplay)
        } catch {
            hasStoredAPIKey = false
            storedAPIKeyDisplay = nil
        }
    }

    private func selectProvider(_ selection: AIProvider) {
        guard selection != provider else { return }
        let configuration = SharedSettingsStore()?.loadProviderConfiguration(for: selection)
        provider = selection
        endpoint = configuration?.endpoint ?? selection.defaultEndpoint
        model = configuration?.model ?? (selection == .openAI ? ProviderConfiguration.defaultModel
            : selection == .google ? ProviderConfiguration.defaultGoogleModel : "")
        selectedModelOption = ModelOption.selection(for: model)
        selectedGeminiModel = GeminiModelOption.recommendedSelection(for: model)
        apiKey = ""
        refreshStoredAPIKey(for: endpoint)
    }

    private func saveSettings() {
        guard let store = SharedSettingsStore() else {
            statusMessage = "共有設定を利用できません。"
            return
        }

        do {
            // The old single key belongs to the saved endpoint, never to a newly selected provider.
            try APIKeyStore().migrateLegacyKey(for: savedEndpoint)
            let normalizedEndpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
            if !apiKey.isEmpty {
                try APIKeyStore().save(apiKey, for: normalizedEndpoint)
            }
            try store.saveProviderConfiguration(
                ProviderConfiguration(
                    endpoint: normalizedEndpoint,
                    model: model.trimmingCharacters(in: .whitespacesAndNewlines),
                    provider: provider
                )
            )
            if !apiKey.isEmpty {
                apiKey = ""
            }
            refreshStoredAPIKey(for: normalizedEndpoint)
            savedEndpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
            savedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
            savedProvider = provider
            statusMessage = "設定を保存しました。"
        } catch {
            statusMessage = "設定を保存できませんでした。"
        }
    }

    private func deleteAPIKey() {
        do {
            try APIKeyStore().delete(for: endpoint)
            apiKey = ""
            hasStoredAPIKey = false
            storedAPIKeyDisplay = nil
            statusMessage = "APIキーを削除しました。"
        } catch {
            statusMessage = "APIキーを削除できませんでした。"
        }
    }

    @MainActor
    private func testAppleConversion() async {
        guard #available(iOS 27.0, *) else {
            appleTestResult = AppleAIAvailabilityCopy.olderOS
            return
        }
        let pcc = PrivateCloudComputeLanguageModel()
        switch pcc.availability {
        case .available:
            break
        case .unavailable(.deviceNotEligible):
            appleTestResult = AppleAIAvailabilityCopy.ineligible
            return
        case .unavailable:
            appleTestResult = AppleAIAvailabilityCopy.notReady
            return
        }
        if pcc.quotaUsage.isLimitReached {
            appleTestResult = "AppleのAI変換は本日の上限に達しました。"
            loadUsageStatistics()
            return
        }
        isTesting = true
        appleTestResult = ""
        defer { isTesting = false }
        do {
            let response = try await PCCConversionClient().convert(
                ConversionRequest(
                    source: testSource,
                    userDictionary: userDictionary,
                    customSystemPrompt: conversionPromptConfiguration.activePrompt
                )
            )
            SharedSettingsStore()?.recordPCCConversion()
            loadUsageStatistics()
            appleTestResult = response.candidates.first ?? "候補がありません。"
        } catch let error as PrivateCloudComputeLanguageModel.Error {
            if case .quotaLimitReached = error {
                appleTestResult = "AppleのAI変換は本日の上限に達しました。"
                loadUsageStatistics()
            } else {
                appleTestResult = "AppleのAI変換を利用できません。通信状態を確認してください。"
            }
        } catch {
            appleTestResult = "AppleのAI変換に失敗しました。"
        }
    }

    @MainActor
    private func testExternalConversion() async {
        let normalizedEndpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let endpointURL = URL(string: normalizedEndpoint), !normalizedModel.isEmpty else {
            externalTestResult = "APIのURLとモデル名を入力してください。"
            return
        }
        if GeminiAgeGate.applies(to: endpointURL), SharedSettingsStore()?.canUseExternalAI(for: endpointURL) != true {
            externalTestResult = GeminiAgeGate.requiredMessage
            return
        }
        guard SharedSettingsStore()?.hasAIDataSharingConsent(for: normalizedEndpoint) == true else {
            externalTestResult = "外部AIへのデータ送信に同意してください。"
            return
        }

        isTesting = true
        externalTestResult = ""
        defer { isTesting = false }

        do {
            let storedAPIKey = try APIKeyStore().load(for: normalizedEndpoint)
            let client = OpenAICompatibleClient(
                configuration: OpenAICompatibleConfiguration(
                    endpoint: endpointURL,
                    model: normalizedModel,
                    apiKey: storedAPIKey
                )
            )
            let response = try await client.convert(
                ConversionRequest(
                    source: externalTestSource,
                    userDictionary: userDictionary,
                    customSystemPrompt: conversionPromptConfiguration.activePrompt
                )
            )
            if let usage = response.usage {
                SharedSettingsStore()?.recordUsage(
                    usage,
                    model: response.model ?? normalizedModel,
                    provider: provider
                )
                loadUsageStatistics()
            }
            externalTestResult = response.candidates.first ?? "候補がありません。"
        } catch let error as OpenAICompatibleClientError {
            externalTestResult = message(for: error)
        } catch let error as URLError {
            externalTestResult = error.code == .timedOut
                ? "変換がタイムアウトしました。"
                : "ネットワーク通信に失敗しました。"
        } catch {
            externalTestResult = "変換に失敗しました。"
        }
    }

    private func message(for error: OpenAICompatibleClientError) -> String {
        switch error {
        case .geminiAgeConfirmationRequired:
            GeminiAgeGate.requiredMessage
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

@available(iOS 26.0, *)
private struct GeminiAgeConfirmationView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var confirmed = false
    @State private var checking = false
    @State private var message = ""

    var body: some View {
        Button(confirmed ? "Geminiの年齢を再確認" : "18歳以上であることを確認") {
            Task { await confirmAge() }
        }
        .disabled(checking)
        .task { refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refresh() }
        }
        if confirmed {
            Label("Gemini：18歳以上を確認済み", systemImage: "checkmark.circle")
        }
        if !message.isEmpty {
            Text(message).font(.footnote).foregroundStyle(.secondary)
        }
    }

    private func refresh() {
        confirmed = SharedSettingsStore()?.hasGeminiAdultConfirmation() == true
    }

    @MainActor
    private func confirmAge() async {
        guard !checking, let store = SharedSettingsStore() else { return }
        checking = true
        message = ""
        store.saveGeminiAgeRange(lowerBound: nil)
        refresh()
        defer {
            refresh()
            checking = false
        }
        guard var presenter = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })?
            .keyWindow?.rootViewController else {
            message = "年齢確認を表示できませんでした。もう一度お試しください。"
            return
        }
        while let presented = presenter.presentedViewController {
            presenter = presented
        }
        do {
            switch try await AgeRangeService.shared.requestAgeRange(
                ageGates: GeminiAgeGate.minimumAge, in: presenter
            ) {
            case .sharing(let range):
                store.saveGeminiAgeRange(lowerBound: range.lowerBound)
                if !store.hasGeminiAdultConfirmation() {
                    message = "18歳以上と確認できなかったため、Geminiは利用できません。"
                }
            case .declinedSharing:
                message = "年齢範囲が共有されなかったため、Geminiは利用できません。"
            @unknown default:
                message = "年齢を確認できませんでした。Geminiは利用できません。"
            }
        } catch {
            message = "年齢を確認できませんでした。Geminiは利用できません。"
        }
    }
}

private struct PCCDailyHistoryView: View {
    private struct DayEntry: Identifiable {
        let date: Date
        let day: String
        let usage: PCCDailyUsage?

        var id: String { day }

        var limitStatus: String {
            if let reachedAt = usage?.limitReachedAt {
                return "到達（\(reachedAt.formatted(date: .omitted, time: .shortened))）"
            }
            if let checkedAt = usage?.lastQuotaCheckedAt {
                return "未到達（\(checkedAt.formatted(date: .omitted, time: .shortened))確認）"
            }
            if (usage?.totalCount ?? 0) > 0 {
                return "未到達（使用時点）"
            }
            return "未確認"
        }

        var limitColor: Color {
            usage?.limitReachedAt != nil ? .orange : .secondary
        }
    }

    @Environment(\.scenePhase) private var scenePhase
    @State private var records: [PCCDailyUsage] = []

    private var days: [DayEntry] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let byDay = Dictionary(uniqueKeysWithValues: records.map { ($0.day, $0) })
        return (0..<30).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else {
                return nil
            }
            let day = PCCDailyUsage.dayKey(for: date, calendar: calendar)
            return DayEntry(date: date, day: day, usage: byDay[day])
        }
    }

    var body: some View {
        List {
            Section {
                Text("端末の現地時刻で毎日0:00（前日の24:00）に区切ります。Appleの利用枠の更新時刻とは一致しない場合があります。")
                Text("「未到達」は記載した時刻に確認できた状態です。その後確認できなかった時間帯は含みません。記録のない日は「未確認」です。")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)

            Section("直近30日") {
                ForEach(days) { entry in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(entry.date.formatted(date: .numeric, time: .omitted))
                                .font(.headline)
                            Spacer()
                            Text(entry.limitStatus)
                                .font(.subheadline)
                                .foregroundStyle(entry.limitColor)
                        }
                        Text("変換 \(entry.usage?.conversionCount ?? 0)回  ·  チャット \(entry.usage?.chatCount ?? 0)回")
                            .font(.subheadline)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 3)
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .navigationTitle("AppleのAI・日別履歴")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { reload() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { reload() }
        }
    }

    private func reload() {
        records = SharedSettingsStore()?.loadPCCDailyUsage() ?? []
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
            prompt: "入力内容の意味を変えず、出力中の句読点を必ず日本語の論文で用いられる全角の「，」「．」に統一してください。「、」「。」および半角の「,」「.」は使用せず、それぞれ「，」「．」に置き換えてください。"
        ),
    ]

    let initialPreset: ConversionPromptPreset
    let onSave: (ConversionPromptPreset) -> Void

    @State private var name: String
    @State private var text: String
    @State private var showsDiscardConfirmation = false
    @State private var showsExampleReplacementConfirmation = false
    @State private var pendingExample: Example?
    @State private var testSource = "ashita made ni kakunin shi, kekka wo houkoku shite kudasai."
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
            Text("「\(result)」")
                .font(.body.monospaced())
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
        if let endpoint = URL(string: configuration.endpoint), !store.canUseExternalAI(for: endpoint) {
            testMessage = GeminiAgeGate.requiredMessage
            return
        }
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
            let apiKey = try APIKeyStore().load(for: configuration.endpoint)
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
                store.recordUsage(usage, model: baselineResponse.model ?? configuration.model,
                                  provider: configuration.provider)
            }
            if let usage = customizedResponse.usage {
                store.recordUsage(usage, model: customizedResponse.model ?? configuration.model,
                                  provider: configuration.provider)
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
                    Text("sumibi = Sumibi\ntari-zu = タリーズ\nopenai = OpenAI")
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
