import FoundationModels
import SumibiCore
import SwiftUI

private struct ChatProposal {
    enum Status { case pending, applied, cancelled }
    var snapshot: SettingsChatSnapshot
    let changes: [SettingsChatChange]
    var status: Status = .pending
    var message = ""
}

private struct ChatEntry: Identifiable {
    let id = UUID()
    let role: SettingsChatMessage.Role
    let text: String
    var responseJSON: String?
    var proposal: ChatProposal?
    var serviceName: String?

    var wireMessage: SettingsChatMessage {
        let content: String
        if let responseJSON {
            let status = switch proposal?.status {
            case .applied: "適用済み"
            case .pending: "未適用"
            case .cancelled: "取り消し済み"
            case nil: "変更案なし"
            }
            content = "変更案の状態：\(status)\n\(responseJSON)"
        } else {
            content = text
        }
        return SettingsChatMessage(role: role, content: content)
    }
}

struct SettingsChatView: View {
    private struct ExternalDestination {
        let provider: AIProvider
        let configuration: ProviderConfiguration
        let client: OpenAICompatibleClient
    }

    private enum ChatRoute {
        case apple
        case external(ExternalDestination)
        case blocked(String)
    }

    @Environment(\.dismiss) private var dismiss
    let onSettingsChanged: () -> Void

    @State private var entries: [ChatEntry] = []
    @State private var input = ""
    @State private var errorMessage = ""
    @State private var connectionMessage = ""
    @State private var routeNotice = ""
    @State private var activeModel = ""
    @State private var isSending = false
    @State private var requestID: UUID?
    @State private var sendTask: Task<Void, Never>?
    @FocusState private var isInputFocused: Bool

    private let examples = [
        "Sumibiの使い方を教えて",
        "遊び心のあるキーボードについて教えて",
        "今どれくらい費用がかかっていますか？",
        "今後15日でどれくらい費用がかかりそうですか？",
        "今の2倍使ったら、今後1週間の費用はどれくらい？",
        "使えるモデルの一覧を見たい",
        "音と振動を全部止めたい",
    ]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    introduction
                    ForEach(entries) { entry in
                        messageView(entry)
                            .id(entry.id)
                    }
                    if isSending {
                        ProgressView("回答を待っています…")
                    }
                    if !errorMessage.isEmpty {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .accessibilityLabel("エラー：\(errorMessage)")
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: entries.count) { _, _ in
                withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onChange(of: isSending) { _, _ in
                withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .safeAreaInset(edge: .bottom) { composer }
        .navigationTitle("チャットで質問")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { refreshConnection() }
        .onDisappear {
            cancelRequest()
            entries.removeAll()
            onSettingsChanged()
        }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ここではAIと会話します。開発者や人間の担当者への問い合わせではありません。")
                .font(.subheadline)
            Text("使い方、遊び心のあるキーボード、概算費用を質問できます。モデル、音や振動の設定変更もできます。")
            Text("変更内容を確認し、「適用する」を押すと保存されます。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if !activeModel.isEmpty {
                Text("会話に使うモデル：\(activeModel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(activeModel == "AppleのAI" || routeNotice.contains("上限に達したため")
                 ? "会話内容、現在の設定、モデル別の利用統計を、まずAppleのAIへ送信します。AppleのAIの上限後は設定済みの外部AIへ切り替わり、API料金が発生する場合があります。"
                 : "会話内容、現在の設定、モデル別の利用統計を、設定済みの外部AIへ送信します。API料金が発生する場合があります。")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("費用予測は端末内の記録に基づく概算で、実際の請求額ではありません。APIキーなどの秘密情報は入力しないでください。会話はこの画面を閉じると消えます。")
                .font(.caption)
                .foregroundStyle(.secondary)
            if !routeNotice.isEmpty {
                Text(routeNotice).font(.caption).foregroundStyle(.orange)
            }
            if !connectionMessage.isEmpty {
                Text(connectionMessage).foregroundStyle(.orange)
                Button("設定画面に戻る") { dismiss() }
            }
            if entries.isEmpty {
                ForEach(examples, id: \.self) { example in
                    Button(example) {
                        input = example
                        isInputFocused = true
                    }
                    .buttonStyle(.bordered)
                    .disabled(isSending)
                }
            }
        }
    }

    private var composer: some View {
        VStack(spacing: 8) {
            HStack(alignment: .bottom, spacing: 12) {
                TextField("使い方・費用・設定について質問", text: $input, axis: .vertical)
                    .lineLimit(1 ... 4)
                    .textFieldStyle(.roundedBorder)
                    .focused($isInputFocused)
                    .disabled(isSending)
                if isSending {
                    Button("キャンセル") { cancelRequest() }
                } else {
                    Button("送信") { startSending() }
                        .buttonStyle(.borderedProminent)
                        .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || !connectionMessage.isEmpty)
                }
            }
        }
        .padding()
        .background(.bar)
    }

    private func messageView(_ entry: ChatEntry) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(entry.role == .user ? "あなた" : "AI（\(entry.serviceName ?? "Sumibi")）")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            Text(entry.text).textSelection(.enabled)
            if let proposal = entry.proposal {
                proposalView(proposal, entryID: entry.id)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            entry.role == .user ? Color.orange.opacity(0.1) : Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 16)
        )
    }

    private func proposalView(_ proposal: ChatProposal, entryID: UUID) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let updated = try? proposal.snapshot.applying(proposal.changes) {
                ForEach(proposal.changes, id: \.setting) { change in
                    let before = proposal.snapshot.displayValue(for: change.setting)
                    let after = updated.displayValue(for: change.setting)
                    if proposal.snapshot.value(for: change.setting) != updated.value(for: change.setting) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(change.setting.title).font(.subheadline.bold())
                            Text("\(before) → \(after)")
                                .font(.subheadline)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            switch proposal.status {
            case .pending:
                HStack {
                    Button("適用する") { applyProposal(entryID) }
                        .buttonStyle(.borderedProminent)
                    Button("取り消す") { cancelProposal(entryID) }
                        .buttonStyle(.bordered)
                }
                .disabled(isSending)
            case .applied:
                Label("設定を変更しました", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .cancelled:
                Text("変更案を取り消しました").foregroundStyle(.secondary)
            }
            if !proposal.message.isEmpty {
                Text(proposal.message).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private func refreshConnection() {
        guard let store = SharedSettingsStore() else {
            connectionMessage = "共有設定を読み込めません。"
            return
        }
        switch chatRoute(using: store) {
        case .apple:
            activeModel = "AppleのAI"
            connectionMessage = ""
        case .external(let destination):
            activeModel = "\(destination.provider.displayName)・\(destination.configuration.model)"
            connectionMessage = ""
        case .blocked(let message):
            activeModel = ""
            connectionMessage = message
        }
    }

    private func chatRoute(using store: SharedSettingsStore) -> ChatRoute {
        var pccUnavailableMessage: String?
        if store.loadPCCPreferred() {
            if #available(iOS 27.0, *) {
                switch PrivateCloudComputeLanguageModel().availability {
                case .available:
                    return .apple
                case .unavailable(.deviceNotEligible):
                    pccUnavailableMessage = AppleAIAvailabilityCopy.ineligible
                case .unavailable:
                    return .blocked(AppleAIAvailabilityCopy.notReady)
                }
            } else {
                pccUnavailableMessage = AppleAIAvailabilityCopy.olderOS
            }
        }
        if let destination = externalDestination(using: store) {
            return .external(destination)
        }
        if let endpoint = URL(string: store.loadProviderConfiguration().endpoint),
           !store.canUseExternalAI(for: endpoint) {
            return .blocked(GeminiAgeGate.requiredMessage)
        }
        return .blocked(pccUnavailableMessage
            ?? "外部AIのAPIキーと送信同意を設定してください。")
    }

    private func externalDestination(
        using store: SharedSettingsStore, provider: AIProvider? = nil
    ) -> ExternalDestination? {
        let configuration = provider.map { store.loadProviderConfiguration(for: $0) }
            ?? store.loadProviderConfiguration()
        guard let url = URL(string: configuration.endpoint), url.host != nil,
              ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              !configuration.model.isEmpty,
              store.canUseExternalAI(for: url),
              store.hasAIDataSharingConsent(for: configuration.endpoint) else { return nil }
        let key: String?
        do {
            key = try APIKeyStore().load(for: configuration.endpoint)
        } catch {
            return nil
        }
        guard configuration.provider == .other || key?.isEmpty == false else { return nil }
        return ExternalDestination(
            provider: configuration.provider,
            configuration: configuration,
            client: OpenAICompatibleClient(configuration: OpenAICompatibleConfiguration(
                endpoint: url, model: configuration.model, apiKey: key
            ))
        )
    }

    @MainActor
    private func sendChat(
        route: ChatRoute,
        messages: [SettingsChatMessage],
        snapshot: SettingsChatSnapshot,
        usageContext: SettingsChatUsageContext,
        store: SharedSettingsStore
    ) async throws -> (SettingsChatCompletion, String, AIProvider?) {
        switch route {
        case .apple:
            if #available(iOS 27.0, *) {
                return try await PCCQuotaRouting.run {
                    let response = try await PCCSettingsChatClient().chatForSettings(
                        messages: messages, snapshot: snapshot, usageContext: usageContext
                    )
                    routeNotice = ""
                    return (response, "AppleのAI", nil)
                } onQuota: { quota in
                    store.recordPCCLimitReached()
                    let providers = PCCQuotaRouting.fallbackProviders(
                        preferred: store.loadProviderConfiguration().provider
                    )
                    guard let destination = providers.lazy.compactMap({
                        externalDestination(using: store, provider: $0)
                    }).first else {
                        throw quota
                    }
                    let response = try await destination.client.chatForSettings(
                        messages: messages, snapshot: snapshot, usageContext: usageContext
                    )
                    routeNotice = "AppleのAIの上限に達したため、\(destination.provider.displayName)に切り替えました（API費用に注意）。"
                    activeModel = "\(destination.provider.displayName)・\(destination.configuration.model)"
                    return (response, destination.provider.displayName, destination.provider)
                }
            }
            throw PCCSettingsChatError.notReady
        case .external(let destination):
            let response = try await destination.client.chatForSettings(
                messages: messages, snapshot: snapshot, usageContext: usageContext
            )
            routeNotice = ""
            return (response, destination.provider.displayName, destination.provider)
        case .blocked(let message):
            throw NSError(domain: "SumibiChat", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    private func startSending() {
        guard !isSending else { return }
        refreshConnection()
        guard connectionMessage.isEmpty, let store = SharedSettingsStore() else { return }
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard text.count <= 2_000 else {
            errorMessage = "1回の入力は2,000文字以内にしてください。"
            return
        }
        let snapshot = store.loadSettingsChatSnapshot()
        let route = chatRoute(using: store)
        if case .blocked(let message) = route {
            connectionMessage = message
            return
        }
        let id = UUID()
        requestID = id
        isSending = true
        errorMessage = ""
        isInputFocused = false
        let entry = ChatEntry(role: .user, text: text)
        entries.append(entry)
        let history = entries.map(\.wireMessage)
        let usageContext = SettingsChatUsageContext(
            statistics: store.loadUsageStatistics(),
            appleAIConversionCount: store.loadPCCConversionCount(),
            appleAIChatCount: store.loadPCCChatCount()
        )
        sendTask = Task { @MainActor in
            defer {
                if requestID == id {
                    requestID = nil
                    isSending = false
                    sendTask = nil
                }
            }
            do {
                let (completion, serviceName, externalProvider) = try await sendChat(
                    route: route, messages: history, snapshot: snapshot,
                    usageContext: usageContext, store: store
                )
                guard requestID == id, !Task.isCancelled else { return }
                if let externalProvider, let usage = completion.usage {
                    store.recordUsage(usage, model: completion.model,
                                      provider: externalProvider, isSettingsChat: true)
                } else if externalProvider == nil {
                    store.recordPCCChat()
                }
                let payload = try SettingsChatPayload.decode(completion.content)
                let updated = try snapshot.applying(payload.changes)
                let changes = payload.changes.filter {
                    snapshot.value(for: $0.setting) != updated.value(for: $0.setting)
                }
                entries.append(ChatEntry(
                    role: .assistant,
                    text: payload.reply,
                    responseJSON: completion.content,
                    proposal: changes.isEmpty ? nil : ChatProposal(snapshot: snapshot, changes: changes),
                    serviceName: serviceName
                ))
                input = ""
                onSettingsChanged()
            } catch {
                guard requestID == id, !Task.isCancelled else { return }
                entries.removeAll { $0.id == entry.id }
                errorMessage = errorDescription(error)
            }
        }
    }

    private func cancelRequest() {
        if isSending, entries.last?.role == .user { entries.removeLast() }
        requestID = nil
        isSending = false
        sendTask?.cancel()
        sendTask = nil
    }

    private func applyProposal(_ entryID: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == entryID }),
              var proposal = entries[index].proposal,
              proposal.status == .pending, let store = SharedSettingsStore()
        else { return }
        do {
            let current = store.loadSettingsChatSnapshot()
            if current != proposal.snapshot {
                let updated = try current.applying(proposal.changes)
                proposal.snapshot = current
                if updated == current {
                    proposal.status = .applied
                    proposal.message = "変更内容は既に反映されています。"
                } else {
                    proposal.message = "設定が変わったため、変更前後を更新しました。内容を確認して、もう一度適用してください。"
                }
                entries[index].proposal = proposal
                return
            }
            try store.applySettingsChatChanges(proposal.changes, basedOn: proposal.snapshot)
            proposal.status = .applied
            proposal.message = ""
            entries[index].proposal = proposal
            refreshConnection()
            onSettingsChanged()
        } catch {
            errorMessage = "変更案を適用できませんでした。現在の設定を確認して、もう一度会話してください。"
        }
    }

    private func cancelProposal(_ entryID: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == entryID }) else { return }
        entries[index].proposal?.status = .cancelled
        entries[index].proposal?.message = ""
    }

    private func errorDescription(_ error: Error) -> String {
        if let quota = error as? PCCQuotaReached {
            let restart = quota.resetDate.map { "（\($0.formatted(date: .abbreviated, time: .shortened))頃に再開）" } ?? ""
            return "AppleのAIは本日の上限に達しました\(restart)。利用できる代替AIがありません。"
        }
        if let pccError = error as? PCCSettingsChatError {
            switch pccError {
            case .deviceNotEligible:
                return AppleAIAvailabilityCopy.ineligible
            case .notReady:
                return AppleAIAvailabilityCopy.notReady
            }
        }
        if #available(iOS 27.0, *), let pccError = error as? PrivateCloudComputeLanguageModel.Error {
            switch pccError {
            case .networkFailure: return "AppleのAIに接続できません。通信状態を確認してください。"
            case .serviceUnavailable: return "AppleのAIを現在利用できません。後ほど再試行してください。"
            case .quotaLimitReached: return "AppleのAIは本日の上限に達しました。"
            @unknown default: return "AppleのAIから回答を取得できませんでした。"
            }
        }
        if error is SettingsChatError || error is DecodingError {
            return "AIから有効な回答を取得できませんでした。入力を変えるか、もう一度送信してください。"
        }
        if let error = error as? URLError {
            return error.code == .timedOut ? "通信がタイムアウトしました。もう一度送信してください。" : "通信に失敗しました。接続を確認してもう一度送信してください。"
        }
        if let error = error as? OpenAICompatibleClientError {
            switch error {
            case .geminiAgeConfirmationRequired: return GeminiAgeGate.requiredMessage
            case .invalidCredentials: return "APIキーを確認してください。API設定は前の画面で変更できます。"
            case .rateLimited: return "APIの利用上限に達しました。時間をおいて再試行してください。"
            case .serverError: return "APIサーバーでエラーが発生しました。もう一度送信してください。"
            case .invalidEndpoint: return "APIのURLを確認してください。"
            default: return "APIから回答を取得できませんでした。API設定やモデル名を確認してください。"
            }
        }
        return "回答を取得できませんでした。API設定を確認してもう一度送信してください。"
    }
}
