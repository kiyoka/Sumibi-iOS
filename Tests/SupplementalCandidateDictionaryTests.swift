import Foundation
import Darwin

private final class DictionaryMockProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requests = 0
    nonisolated(unsafe) static var body = ""

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests += 1
        if let data = request.httpBody {
            Self.body = String(decoding: data, as: UTF8.self)
        } else if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            var bytes = Data()
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                bytes.append(buffer, count: count)
            }
            Self.body = String(decoding: bytes, as: UTF8.self)
        }
        let data = try! JSONSerialization.data(withJSONObject: [
            "choices": [["message": ["role": "assistant",
                "content": "{\"candidates\":[\"橋\",\"はし\"]}"]]],
            "usage": ["prompt_tokens": 10, "completion_tokens": 5],
        ])
        let response = HTTPURLResponse(url: request.url!, statusCode: 200,
                                       httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main
private struct SupplementalCandidateDictionaryTests {
    static let custom = "ten\t・\nnakaguro\t・\n.\t・\n"
    static let dictionary = SupplementalCandidateDictionary(
        homophoneTSV: "# comment\nはし\t橋\t端\t箸\t椅\nかみ\t紙\t神\t髪\nてん\t天\t点\n",
        customTSV: custom
    )

    static func main() async throws {
        testLookup()
        testMerge()
        testSymbols()
        try testMissingResources()
        try testBundledData()
        try await testLocalOnlyTransport()
        print("Dictionary checks passed: lookup, symbols, limits, provenance, middle dot, fallback, real data, local-only mock transport")
    }

    static func testLookup() {
        precondition(dictionary.candidates(for: "hashi", llmCandidates: ["橋", "はし"],
                                          excluding: ["橋", "はし"]) == ["端", "箸", "椅"])
        precondition(dictionary.candidates(for: "hashi", llmCandidates: ["はし"],
                                          excluding: [], maximumAdded: 2) == ["橋", "端"])
        precondition(dictionary.candidates(for: "hashi", llmCandidates: ["橋", "このはしを渡る"],
                                          excluding: []).isEmpty)
        precondition(dictionary.candidates(for: "unknown", llmCandidates: ["みしゅうろく"],
                                          excluding: []).isEmpty)
        // The FIRST whole-hiragana candidate determines the reading, as on macOS.
        precondition(dictionary.candidates(for: "hashi", llmCandidates: ["みしゅうろく", "はし"],
                                          excluding: []).isEmpty)
        precondition(dictionary.candidates(for: "hashi", llmCandidates: ["はし"],
                                          excluding: [], maximumAdded: 0).isEmpty)
        for source in ["ten", "nakaguro", "."] {
            let customOnly = SupplementalCandidateDictionary(customTSV: custom)
            precondition(customOnly.candidates(for: source, llmCandidates: ["点"],
                                              excluding: []) == ["・"])
            precondition(customOnly.candidates(for: source, llmCandidates: ["・"],
                                              excluding: ["・"]).isEmpty)
        }
        for source in ["hello.", "nihongo .", "..", "TEN", " ten ", "nakaguro desu"] {
            precondition(dictionary.candidates(for: source, llmCandidates: ["。"],
                                              excluding: []).isEmpty)
        }
        precondition(dictionary.candidates(for: "ten", llmCandidates: ["てん"],
                                          excluding: [], maximumAdded: 1) == ["・"])
        let malformed = SupplementalCandidateDictionary(
            homophoneTSV: "#comment\ninvalid\n\tno reading\nはし\t\nかみ\t紙\t\t神\r\n"
        )
        precondition(malformed.candidates(for: "", llmCandidates: ["はし"], excluding: []).isEmpty)
        precondition(malformed.candidates(for: "", llmCandidates: ["かみ"], excluding: []) == ["紙", "神"])
    }

    static func testMerge() {
        let combined = AdditionalCandidateList(
            original: "hashi", current: "橋", existingOptions: ["橋", "hashi"],
            llmCandidates: [" 橋 ", "はし", "端", "橋", ""], dictionary: dictionary
        )
        precondition(combined.options == ["橋", "はし", "端", "箸", "椅", "hashi"])
        precondition(combined.dictionaryCandidates == ["箸", "椅"])
        let many = (0..<20).map { "候補\($0)" }
        let large = SupplementalCandidateDictionary(homophoneTSV: "はし\t" + many.joined(separator: "\t"))
        let capped = AdditionalCandidateList(
            original: "hashi", current: "橋", existingOptions: ["橋", "hashi"],
            llmCandidates: ["はし"] + (0..<15).map { "LLM\($0)" }, dictionary: large
        )
        precondition(capped.dictionaryCandidates.count == 10)
        precondition(capped.options.count == 12 + 10 + 1)
        precondition(capped.options.prefix(12) == ["橋", "はし"] + (0..<10).map { "LLM\($0)" })
        precondition(capped.options.last == "hashi")
        for source in ["ten", "nakaguro", "."] {
            let middle = AdditionalCandidateList(
                original: source, current: "点", existingOptions: ["点", source],
                llmCandidates: (0..<20).map { "候補\($0)" }, dictionary: dictionary
            )
            precondition(middle.dictionaryCandidates == ["・"])
            precondition(middle.options.contains("・"))
            let fromLLM = AdditionalCandidateList(
                original: source, current: "点", existingOptions: ["点", source],
                llmCandidates: ["・"], dictionary: dictionary
            )
            precondition(fromLLM.options.filter { $0 == "・" }.count == 1)
            precondition(!fromLLM.dictionaryCandidates.contains("・"))
            let lastLLM = AdditionalCandidateList(
                original: source, current: "点", existingOptions: ["点", source],
                llmCandidates: (0..<12).map { "候補\($0)" } + ["・"], dictionary: dictionary
            )
            precondition(lastLLM.options.contains("・"), "Middle dot must survive the LLM display cap")
            precondition(!lastLLM.dictionaryCandidates.contains("・"))
        }
        let refreshed = AdditionalCandidateList(
            original: "hashi", current: "箸",
            existingOptions: combined.options, existingDictionaryCandidates: combined.dictionaryCandidates,
            llmCandidates: ["箸", "はし"], dictionary: dictionary
        )
        precondition(refreshed.dictionaryCandidates.contains("箸"))
        precondition(refreshed.options.filter { $0 == "箸" }.count == 1)
        precondition(!refreshed.options.contains(where: { $0.contains("辞書") || $0.contains("LLM") }))
        let empty = AdditionalCandidateList(
            original: "hashi", current: "橋", existingOptions: ["橋", "hashi"],
            llmCandidates: [], dictionary: SupplementalCandidateDictionary()
        )
        precondition(empty.options == ["橋", "hashi"])
    }

    static func testSymbols() {
        let symbols = SupplementalCandidateDictionary(
            homophoneTSV: "ほし\t星\t干し\n", customTSV: custom,
            symbolTSV: "hoshi\t☆\t★\t☆\nhosi\t☆\t★\nほし\t☆\t★\nmaru1\t①\t❶\n.\t。\t．\t・\n"
        )
        for source in ["hoshi", "hosi", "ほし", "HOSHI"] {
            precondition(symbols.candidates(for: source, llmCandidates: ["星"], excluding: []) == ["☆", "★"])
        }
        precondition(symbols.candidates(for: "maru1", llmCandidates: [], excluding: []) == ["①", "❶"])
        precondition(symbols.candidates(for: "maru1", llmCandidates: [], excluding: ["①"]) == ["❶"])
        precondition(symbols.candidates(for: "hoshi", llmCandidates: ["ほし"], excluding: []) == ["☆", "★", "星", "干し"])
        precondition(symbols.candidates(for: ".", llmCandidates: [], excluding: [], maximumAdded: 1) == ["・"])
        for source in ["hoshi desu", "hello.", " maru1 ", "unknown", "①"] {
            precondition(symbols.candidates(for: source, llmCandidates: ["星"], excluding: []).isEmpty)
        }
        let merged = AdditionalCandidateList(
            original: "hoshi", current: "星", existingOptions: ["星", "hoshi"],
            llmCandidates: [" ★ ", "★"], dictionary: symbols
        )
        precondition(merged.options == ["星", "★", "☆", "hoshi"])
        precondition(merged.dictionaryCandidates == ["☆"])
        let capped = AdditionalCandidateList(
            original: "hoshi", current: "星", existingOptions: ["星", "hoshi"],
            llmCandidates: (0..<12).map { "LLM\($0)" } + ["★"], dictionary: symbols
        )
        precondition(!capped.dictionaryCandidates.contains("★"), "Capped LLM results must not become dictionary results")
        precondition(capped.dictionaryCandidates == ["☆"])
    }

    static func testMissingResources() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("sumibi-dictionary-tests-\(UUID().uuidString).bundle")
        defer { try? FileManager.default.removeItem(at: root) }
        let resources = root.appendingPathComponent("ConversionDictionary")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        let info = try PropertyListSerialization.data(
            fromPropertyList: ["CFBundleIdentifier": "org.sumibi.dictionary.tests",
                               "CFBundlePackageType": "BNDL"],
            format: .xml, options: 0
        )
        try info.write(to: root.appendingPathComponent("Info.plist"))
        let empty = SupplementalCandidateDictionary.load(from: Bundle.main)
        precondition(empty.candidates(for: "ten", llmCandidates: [], excluding: []).isEmpty)
        try custom.write(to: resources.appendingPathComponent("BuiltinCandidates.tsv"),
                         atomically: true, encoding: .utf8)
        try Data([0xff, 0xfe]).write(to: resources.appendingPathComponent("SudachiCandidates.tsv"))
        try "hoshi\t☆\t★\n".write(to: resources.appendingPathComponent("MozcSymbols.tsv"),
                                   atomically: true, encoding: .utf8)
        let bundle = Bundle(path: root.path)!
        let partial = SupplementalCandidateDictionary.load(from: bundle)
        precondition(partial.candidates(for: "ten", llmCandidates: [], excluding: []) == ["・"])
        precondition(partial.candidates(for: "hoshi", llmCandidates: [], excluding: []) == ["☆", "★"])
        try Data([0xff, 0xfe]).write(to: resources.appendingPathComponent("MozcSymbols.tsv"))
        let corruptSymbols = SupplementalCandidateDictionary.load(from: bundle)
        precondition(corruptSymbols.candidates(for: "hoshi", llmCandidates: [], excluding: []).isEmpty)
        precondition(corruptSymbols.candidates(for: "ten", llmCandidates: [], excluding: []) == ["・"])
    }

    static func testBundledData() throws {
        var before = rusage()
        getrusage(RUSAGE_SELF, &before)
        let start = Date()
        let base = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("SumibiKeyboard/ConversionDictionary")
        let bundled = SupplementalCandidateDictionary(
            homophoneTSV: try String(contentsOf: base.appendingPathComponent("SudachiCandidates.tsv"), encoding: .utf8),
            customTSV: try String(contentsOf: base.appendingPathComponent("BuiltinCandidates.tsv"), encoding: .utf8),
            symbolTSV: try String(contentsOf: base.appendingPathComponent("MozcSymbols.tsv"), encoding: .utf8)
        )
        let elapsed = Date().timeIntervalSince(start)
        var after = rusage()
        getrusage(RUSAGE_SELF, &after)
        let hashi = bundled.candidates(for: "hashi", llmCandidates: ["橋", "はし"], excluding: ["橋", "はし"])
        precondition(hashi.contains("箸") && hashi.contains("端"))
        let kami = bundled.candidates(for: "kami", llmCandidates: ["かみ"], excluding: [])
        precondition(kami.contains("紙") && kami.contains("神") && kami.contains("髪"))
        for source in ["ten", "nakaguro", "."] {
            precondition(bundled.candidates(for: source, llmCandidates: [], excluding: []).first == "・")
        }
        for source in ["hoshi", "hosi", "ほし", "HOSHI", "kuroboshi"] {
            precondition(bundled.candidates(for: source, llmCandidates: ["星"], excluding: []).contains("★"))
        }
        for (source, surface) in [("maru1", "①"), ("maruichi", "①"), ("maruiti", "①"),
                                  ("maru2", "②"), ("まる1", "①"), ("yajirushi", "→"),
                                  ("yazirusi", "→"), ("mugendai", "∞"), ("sankaku", "△"), ("#", "＃")] {
            precondition(bundled.candidates(for: source, llmCandidates: [], excluding: []).contains(surface), source)
        }
        precondition(bundled.candidates(for: "hoshi", llmCandidates: [], excluding: []).count == 10)
        precondition(bundled.candidates(for: "hoshi desu", llmCandidates: ["星です"], excluding: []).isEmpty)
        for _ in 0..<1000 {
            precondition(bundled.candidates(for: "hashi", llmCandidates: ["はし"], excluding: []).count <= 10)
        }
        print(String(format: "Host dictionary load %.1f ms; peak RSS growth %.2f MiB (not iOS extension measurement)",
                     elapsed * 1000, Double(max(0, after.ru_maxrss - before.ru_maxrss)) / 1_048_576))
    }

    static func testLocalOnlyTransport() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DictionaryMockProtocol.self]
        let client = OpenAICompatibleClient(configuration: OpenAICompatibleConfiguration(
            endpoint: URL(string: "https://sumibi-tests.invalid")!, model: "mock", apiKey: nil
        ), session: URLSession(configuration: configuration))
        let response = try await client.convert(ConversionRequest(
            source: "hashi", mode: .additional, currentConversion: "橋",
            userDictionary: "product = UserPreferredName", customSystemPrompt: "文体の指定"
        ))
        let requestsBefore = DictionaryMockProtocol.requests
        let local = SupplementalCandidateDictionary(
            homophoneTSV: "はし\t橋\tローカル専用マーカー\n", customTSV: custom,
            symbolTSV: "hashi\t記号のローカル専用マーカー\n"
        )
        let merged = AdditionalCandidateList(
            original: "hashi", current: "橋", existingOptions: ["橋", "hashi"],
            llmCandidates: response.candidates, dictionary: local
        )
        precondition(merged.dictionaryCandidates.contains("ローカル専用マーカー"))
        precondition(merged.dictionaryCandidates.contains("記号のローカル専用マーカー"))
        precondition(requestsBefore == 1 && DictionaryMockProtocol.requests == 1)
        precondition(!DictionaryMockProtocol.body.contains("ローカル専用マーカー"))
        precondition(!DictionaryMockProtocol.body.contains("MozcSymbols"))
        precondition(!DictionaryMockProtocol.body.contains("BuiltinCandidates"))
        precondition(DictionaryMockProtocol.body.contains("UserPreferredName"))
        precondition(response.usage?.inputTokens == 10 && response.usage?.outputTokens == 5)
    }
}
