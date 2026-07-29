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

    private struct CandidatePayload: Decodable {
        let candidates: [String]
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
        let candidateCount = ConversionCandidatePolicy.candidateCount(for: request.source)
        urlRequest.httpBody = try encoder.encode(
            ChatRequest(
                model: configuration.model,
                messages: [
                    Message(
                        role: "system",
                        content: """
                        あなたはローマ字と英語を自然な日本語へ変換するIMEです。
                        Markdown記法、URL、固有名詞は可能な限り維持してください。
                        入力にない情報は追加しないでください。
                        \(candidateInstructions(count: candidateCount))
                        JSON以外の説明やMarkdownのコードフェンスは返さないでください。
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
            .flatMap { decodeCandidates(from: $0.message.content) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .reduce(into: [String]()) { unique, candidate in
                if !unique.contains(candidate) {
                    unique.append(candidate)
                }
            }
            .prefix(candidateCount)
        guard !candidates.isEmpty else {
            throw OpenAICompatibleClientError.emptyResponse
        }
        return ConversionResponse(candidates: Array(candidates))
    }

    private func candidateInstructions(count: Int) -> String {
        if count == 5 {
            return """
            次の順序で異なる5候補を作り、{"candidates":["候補1","候補2","候補3","候補4","候補5"]}というJSONだけを返してください。
            1. 文脈に最も自然な、通常の漢字変換を含む候補
            2. 全文をひらがなにした候補（句読点は維持）
            3. 全文をカタカナにした候補（句読点は維持）
            4. 候補1よりひらがなを少なくし、漢字を多くした候補
            5. 候補1よりひらがなを多くし、漢字を少なくした候補
            """
        }
        return """
        次の順序で異なる3候補を作り、{"candidates":["候補1","候補2","候補3"]}というJSONだけを返してください。
        1. 文脈に最も自然な、通常の漢字変換を含む候補
        2. 全文をひらがなにした候補（句読点は維持）
        3. 全文をカタカナにした候補（句読点は維持）
        """
    }

    private func decodeCandidates(from content: String) -> [String] {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return []
        }

        if let candidates = decodeCandidateJSON(trimmed) {
            return candidates
        }
        if
            let firstBrace = trimmed.firstIndex(of: "{"),
            let lastBrace = trimmed.lastIndex(of: "}"),
            firstBrace <= lastBrace,
            let candidates = decodeCandidateJSON(String(trimmed[firstBrace ... lastBrace]))
        {
            return candidates
        }
        if
            let firstBracket = trimmed.firstIndex(of: "["),
            let lastBracket = trimmed.lastIndex(of: "]"),
            firstBracket <= lastBracket,
            let candidates = decodeCandidateJSON(String(trimmed[firstBracket ... lastBracket]))
        {
            return candidates
        }
        return [trimmed]
    }

    private func decodeCandidateJSON(_ json: String) -> [String]? {
        guard let data = json.data(using: .utf8) else {
            return nil
        }
        if let payload = try? decoder.decode(CandidatePayload.self, from: data) {
            return payload.candidates
        }
        return try? decoder.decode([String].self, from: data)
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
