import Foundation

public struct ConversionRequest: Equatable, Sendable {
    public let source: String
    public let surroundingContext: String
    public let mode: ConversionCandidateMode
    public let currentConversion: String?
    public let userDictionary: String
    public let customSystemPrompt: String

    public init(
        source: String,
        surroundingContext: String = "",
        mode: ConversionCandidateMode = .primary,
        currentConversion: String? = nil,
        userDictionary: String = "",
        customSystemPrompt: String = ""
    ) {
        self.source = source
        self.surroundingContext = surroundingContext
        self.mode = mode
        self.currentConversion = currentConversion
        self.userDictionary = userDictionary
        self.customSystemPrompt = customSystemPrompt
    }
}

/// Emacs版 Sumibi の `sumibi--romaji-to-hiragana-table` と同じ読みを使う。
/// PCCへ送る読みだけに適用し、外部AIへの入力や実際の入力文字列は変更しない。
public enum PCCRomajiReading {
    private static let table: [String: String] = {
        let entries = """
        kya=きゃ kyu=きゅ kyo=きょ sha=しゃ shu=しゅ sho=しょ she=しぇ
        cha=ちゃ chu=ちゅ cho=ちょ che=ちぇ tya=ちゃ tyu=ちゅ tyo=ちょ tye=ちぇ
        nya=にゃ nyu=にゅ nyo=にょ nna=んな nni=んに nnu=んぬ nne=んね nno=んの
        hya=ひゃ hyu=ひゅ hyo=ひょ mya=みゃ myu=みゅ myo=みょ rya=りゃ ryu=りゅ ryo=りょ
        gya=ぎゃ gyu=ぎゅ gyo=ぎょ jya=じゃ jyu=じゅ jyo=じょ bya=びゃ byu=びゅ byo=びょ
        pya=ぴゃ pyu=ぴゅ pyo=ぴょ kwa=くぁ kwi=くぃ kwe=くぇ kwo=くぉ
        tsa=つぁ tsi=つぃ tse=つぇ tso=つぉ gwa=ぐぁ gwi=ぐぃ gwe=ぐぇ gwo=ぐぉ
        dyi=でぃ dyu=どゅ dye=でぇ dyo=どぉ xwi=うぃ xwe=うぇ xwo=うぉ tyi=てぃ
        xtu=っ xya=ゃ xyu=ゅ xyo=ょ xwa=ゎ xka=ヵ xke=ヶ
        shi=し chi=ち tsu=つ fu=ふ ja=じゃ ju=じゅ ji=じ jo=じょ je=じぇ
        fa=ふぁ fi=ふぃ fe=ふぇ fo=ふぉ va=ヴぁ vi=ヴぃ vu=ヴ ve=ヴぇ vo=ヴぉ
        wi=うぃ we=うぇ wo=を nn=ん xa=ぁ xi=ぃ xu=ぅ xe=ぇ xo=ぉ
        ka=か ki=き ku=く ke=け ko=こ sa=さ si=し su=す se=せ so=そ
        ta=た ti=ち tu=つ te=て to=と na=な ni=に nu=ぬ ne=ね no=の
        ha=は hi=ひ hu=ふ he=へ ho=ほ ma=ま mi=み mu=む me=め mo=も
        ya=や yi=い yu=ゆ ye=いぇ yo=よ ra=ら ri=り ru=る re=れ ro=ろ wa=わ
        ga=が gi=ぎ gu=ぐ ge=げ go=ご za=ざ zi=じ zu=ず ze=ぜ zo=ぞ
        da=だ di=ぢ du=づ de=で do=ど ba=ば bi=び bu=ぶ be=べ bo=ぼ
        pa=ぱ pi=ぴ pu=ぷ pe=ぺ po=ぽ a=あ i=い u=う e=え o=お n=ん -=ー
        """
        return Dictionary(uniqueKeysWithValues: entries.split(whereSeparator: \.isWhitespace).map { entry in
            let pair = entry.split(separator: "=", maxSplits: 1)
            return (String(pair[0]), String(pair[1]))
        })
    }()

    /// Emacs版の部分変換と同じく、一致しない文字だけを元のまま残す。
    public static func convert(_ source: String) -> String {
        let characters = Array(source)
        var result = ""
        var index = 0
        while index < characters.count {
            let start = index
            if characters[index].isASCII && characters[index].isLetter {
                while index < characters.count,
                      characters[index].isASCII,
                      characters[index].isLetter || characters[index] == "-" {
                    index += 1
                }
                let word = String(characters[start..<index])
                // URL・メール・ファイル名の一部は変換対象にしない。
                let before = start > 0 ? characters[start - 1] : nil
                let after = index < characters.count ? characters[index] : nil
                let partOfIdentifier = before.map { "@/:._".contains($0) } == true
                    || after.map { "@/:_".contains($0) } == true
                    || (after == "." && index + 1 < characters.count && characters[index + 1].isLetter)
                if partOfIdentifier {
                    result += word
                } else {
                    result += convertWord(word)
                }
            } else {
                result.append(characters[index])
                index += 1
            }
        }
        return result
    }

    private static func convertWord(_ word: String) -> String {
        let letters = Array(word.lowercased())
        let original = Array(word)
        var result = ""
        var index = 0
        while index < letters.count {
            if index + 1 < letters.count, letters[index] == letters[index + 1],
               !"aiueon".contains(letters[index]) {
                result += "っ"
                index += 1
                continue
            }
            var matched = false
            for length in stride(from: min(3, letters.count - index), through: 1, by: -1) {
                let key = String(letters[index..<(index + length)])
                if let kana = table[key] {
                    result += kana
                    index += length
                    matched = true
                    break
                }
            }
            if !matched {
                result.append(original[index])
                index += 1
            }
        }
        return result
    }
}

public struct ConversionResponse: Equatable, Sendable {
    public let candidates: [String]
    public let model: String?
    public let usage: TokenUsage?
    public let backend: ConversionBackend?
    public let usedPCCFallback: Bool

    public init(
        candidates: [String],
        model: String? = nil,
        usage: TokenUsage? = nil,
        backend: ConversionBackend? = nil,
        usedPCCFallback: Bool = false
    ) {
        self.candidates = candidates
        self.model = model
        self.usage = usage
        self.backend = backend
        self.usedPCCFallback = usedPCCFallback
    }
}

public enum ConversionBackend: Equatable, Sendable {
    case privateCloudCompute
    case external(AIProvider)
}

public struct TokenUsage: Equatable, Sendable {
    public let inputTokens: Int
    public let cachedInputTokens: Int
    public let outputTokens: Int
    public let unitemizedTokens: Int

    public init(
        inputTokens: Int,
        cachedInputTokens: Int = 0,
        outputTokens: Int,
        unitemizedTokens: Int = 0
    ) {
        self.inputTokens = inputTokens
        self.cachedInputTokens = cachedInputTokens
        self.outputTokens = outputTokens
        self.unitemizedTokens = unitemizedTokens
    }

    public var totalTokens: Int {
        inputTokens + outputTokens + unitemizedTokens
    }
}

public enum ConversionCandidateMode: Equatable, Sendable {
    case primary
    case additional

    public var candidateCount: Int {
        switch self {
        case .primary:
            1
        case .additional:
            12
        }
    }
}

public protocol ConversionClient: Sendable {
    func convert(_ request: ConversionRequest) async throws -> ConversionResponse
}

public struct PCCQuotaReached: Error, Equatable, Sendable {
    public let resetDate: Date?

    public init(resetDate: Date?) {
        self.resetDate = resetDate
    }
}

/// Only a quota error permits external fallback. Recheck Apple on every request.
public enum PCCQuotaRouting {
    public static func run<Result>(
        isolation: isolated (any Actor)? = #isolation,
        primary: () async throws -> Result,
        onQuota: (PCCQuotaReached) async throws -> Result
    ) async throws -> Result {
        do {
            return try await primary()
        } catch let quota as PCCQuotaReached {
            try Task.checkCancellation()
            return try await onQuota(quota)
        }
    }

    public static func fallbackProviders(preferred: AIProvider) -> [AIProvider] {
        preferred == .google ? [.google, .openAI] : [.openAI, .google]
    }
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
