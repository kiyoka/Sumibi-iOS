import Foundation

public struct ConversionRequest: Equatable, Sendable {
    public let source: String
    public let surroundingContext: String

    public init(source: String, surroundingContext: String = "") {
        self.source = source
        self.surroundingContext = surroundingContext
    }
}

public struct ConversionResponse: Equatable, Sendable {
    public let candidates: [String]

    public init(candidates: [String]) {
        self.candidates = candidates
    }
}

public protocol ConversionClient: Sendable {
    func convert(_ request: ConversionRequest) async throws -> ConversionResponse
}

public struct MockConversionClient: ConversionClient {
    private let delayNanoseconds: UInt64

    public init(delayNanoseconds: UInt64 = 300_000_000) {
        self.delayNanoseconds = delayNanoseconds
    }

    public func convert(_ request: ConversionRequest) async throws -> ConversionResponse {
        try await Task.sleep(nanoseconds: delayNanoseconds)
        try Task.checkCancellation()

        let converted = Self.convertWithSimpleRules(request.source)
        let candidates = converted == request.source
            ? [request.source]
            : [converted]
        return ConversionResponse(candidates: candidates)
    }

    private static func convertWithSimpleRules(_ source: String) -> String {
        let words: [String: String] = [
            "arigatou": "ありがとう",
            "desu": "です",
            "ha": "は",
            "iitenki": "いい天気",
            "kiyoka": "きよか",
            "kyou": "今日",
            "nihongo": "日本語",
            "ohayou": "おはよう",
            "sumibi": "Sumibi",
            "watashi": "私",
            "yoroshiku": "よろしく",
        ]
        let punctuation: [String: String] = [
            ".": "。",
            ",": "、",
            "?": "？",
            "!": "！",
        ]

        return source
            .split(separator: " ", omittingEmptySubsequences: true)
            .map(String.init)
            .map { words[$0.lowercased()] ?? punctuation[$0] ?? $0 }
            .joined()
    }
}
