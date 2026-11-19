import Foundation
import FoundationModels
import SumibiCore

enum PCCSettingsChatError: Error {
    case deviceNotEligible
    case notReady
}

@available(iOS 27.0, *)
@Generable
private struct PCCSettingsChatReply {
    @Guide(description: "ユーザーへの日本語の回答。設定変更は適用するまで保存されないことを守る")
    var reply: String

    @Guide(description: "明確に依頼された設定変更案だけ。質問や説明では空配列")
    var changes: [PCCSettingsChatChange]
}

@available(iOS 27.0, *)
@Generable
private struct PCCSettingsChatChange {
    @Guide(description: "model、hapticFeedbackEnabled、conversionCompletionHapticEnabled、keyClickSoundEnabled のいずれか")
    var setting: String

    @Guide(description: "変更後の設定値。常に文字列")
    var value: String
}

@available(iOS 27.0, *)
struct PCCSettingsChatClient {
    func chatForSettings(
        messages: [SettingsChatMessage],
        snapshot: SettingsChatSnapshot,
        usageContext: SettingsChatUsageContext
    ) async throws -> SettingsChatCompletion {
        let model = PrivateCloudComputeLanguageModel()
        if case .unavailable(.deviceNotEligible) = model.availability {
            throw PCCSettingsChatError.deviceNotEligible
        }
        guard case .available = model.availability else {
            throw PCCSettingsChatError.notReady
        }
        if model.quotaUsage.isLimitReached {
            throw PCCQuotaReached(resetDate: model.quotaUsage.resetDate)
        }

        let instructions = try OpenAICompatibleClient.settingsChatInstructions(
            snapshot: snapshot,
            usageContext: usageContext
        )
        let history = messages.suffix(12).map { message in
            let speaker = message.role == .user ? "ユーザー" : "AI"
            return "<turn speaker=\"\(speaker)\">\n\(message.content)\n</turn>"
        }.joined(separator: "\n")
        let session = LanguageModelSession(model: model, instructions: instructions)
        let answer: PCCSettingsChatReply
        do {
            answer = try await session.respond(
                to: "次の会話履歴を踏まえ、最後のユーザー発言に回答してください。\n<conversation>\n\(history)\n</conversation>",
                generating: PCCSettingsChatReply.self
            ).content
        } catch let error as PrivateCloudComputeLanguageModel.Error {
            if case .quotaLimitReached(let details) = error {
                throw PCCQuotaReached(resetDate: details.resetDate)
            }
            throw error
        }
        let object: [String: Any] = [
            "reply": answer.reply,
            "changes": answer.changes.map { ["setting": $0.setting, "value": $0.value] },
        ]
        let content = String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
        _ = try SettingsChatPayload.decode(content)
        return SettingsChatCompletion(content: content, model: "Private Cloud Compute", usage: nil)
    }
}
