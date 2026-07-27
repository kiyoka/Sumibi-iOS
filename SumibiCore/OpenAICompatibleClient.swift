import Foundation

public struct OpenAICompatibleConfiguration: Equatable, Sendable {
    public let endpoint: URL
    public let model: String
    public let apiKey: String?
    public let timeout: TimeInterval

    public init(
        endpoint: URL,
        model: String,
        apiKey: String?,
        timeout: TimeInterval = 15
    ) {
        self.endpoint = endpoint
        self.model = model
        self.apiKey = apiKey
        self.timeout = timeout
    }
}

public enum OpenAICompatibleClientError: Error, Equatable, Sendable {
    case invalidEndpoint
    case invalidResponse
    case invalidCredentials
    case rateLimited
    case serverError(statusCode: Int)
    case httpError(statusCode: Int)
    case emptyResponse
}

public struct OpenAICompatibleClient: ConversionClient {
    private struct ChatRequest: Encodable {
        let model: String
        let messages: [Message]
    }

    private struct Message: Codable {
        let role: String
        let content: String
    }

    private struct ChatResponse: Decodable {
        let choices: [Choice]
    }

    private struct Choice: Decodable {
        let message: Message
    }

    private let configuration: OpenAICompatibleConfiguration
    private let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(
        configuration: OpenAICompatibleConfiguration,
        session: URLSession = .shared
    ) {
        self.configuration = configuration
        self.session = session
    }

    public func convert(_ request: ConversionRequest) async throws -> ConversionResponse {
        guard let endpoint = chatCompletionsURL(from: configuration.endpoint) else {
            throw OpenAICompatibleClientError.invalidEndpoint
        }

        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = configuration.timeout
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey = configuration.apiKey, !apiKey.isEmpty {
            urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        urlRequest.httpBody = try encoder.encode(
            ChatRequest(
                model: configuration.model,
                messages: [
                    Message(
                        role: "system",
                        content: """
                        あなたはローマ字と英語を自然な日本語へ変換するIMEです。
                        入力にない情報を追加せず、変換後の本文だけを返してください。
                        Markdown記法、URL、固有名詞は可能な限り維持してください。
                        """
                    ),
                    Message(
                        role: "user",
                        content: """
                        周辺文脈：
                        \(request.surroundingContext)

                        変換対象：
                        \(request.source)
                        """
                    ),
                ]
            )
        )

        let (data, response) = try await session.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAICompatibleClientError.invalidResponse
        }
        try validate(statusCode: httpResponse.statusCode)

        let chatResponse = try decoder.decode(ChatResponse.self, from: data)
        let candidates = chatResponse.choices
            .map(\.message.content)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !candidates.isEmpty else {
            throw OpenAICompatibleClientError.emptyResponse
        }
        return ConversionResponse(candidates: candidates)
    }

    private func chatCompletionsURL(from baseURL: URL) -> URL? {
        let normalizedPath = baseURL.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if normalizedPath.hasSuffix("chat/completions") {
            return baseURL
        }
        if normalizedPath.hasSuffix("v1") {
            return baseURL
                .appendingPathComponent("chat")
                .appendingPathComponent("completions")
        }
        return baseURL
            .appendingPathComponent("v1")
            .appendingPathComponent("chat")
            .appendingPathComponent("completions")
    }

    private func validate(statusCode: Int) throws {
        switch statusCode {
        case 200 ..< 300:
            return
        case 401, 403:
            throw OpenAICompatibleClientError.invalidCredentials
        case 429:
            throw OpenAICompatibleClientError.rateLimited
        case 500 ..< 600:
            throw OpenAICompatibleClientError.serverError(statusCode: statusCode)
        default:
            throw OpenAICompatibleClientError.httpError(statusCode: statusCode)
        }
    }
}
