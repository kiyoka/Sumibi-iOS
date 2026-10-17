import Foundation

/// Local-only candidate index. Keep UTF-8 bytes and row offsets rather than
/// allocating strings/arrays for every surface in the dictionary.
public struct SupplementalCandidateDictionary: Sendable {
    private let homophones: Index
    private let custom: Index
    private let symbols: Index

    public init(homophoneTSV: String = "", customTSV: String = "", symbolTSV: String = "") {
        homophones = Index(homophoneTSV)
        custom = Index(customTSV)
        symbols = Index(symbolTSV)
    }

    public static func load(from bundle: Bundle) -> Self {
        func read(_ name: String) -> String {
            guard let url = bundle.url(
                forResource: name, withExtension: "tsv",
                subdirectory: "ConversionDictionary"
            ) else { return "" }
            return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        }
        // Independent loads: a missing Sudachi index must not disable custom entries.
        return Self(homophoneTSV: read("SudachiCandidates"), customTSV: read("BuiltinCandidates"),
                    symbolTSV: read("MozcSymbols"))
    }

    public func candidates(
        for source: String,
        llmCandidates: [String],
        excluding: Set<String>,
        maximumAdded: Int = 10
    ) -> [String] {
        guard maximumAdded > 0 else { return [] }
        var result: [String] = []
        var seen = excluding
        // Reserve space for explicit custom entries such as the Japanese middle dot.
        let customValues = customCandidates(for: source)
        // Exact whole-input lookup, independent of whether the LLM returns kana.
        // Do not use compatibility normalization: it would turn ① into 1, etc.
        let symbolValues = symbols.surfaces(for: source.precomposedStringWithCanonicalMapping.lowercased())
        let reading = llmCandidates.first(where: Self.isHiraganaWord)
        let dictionaryValues = reading.map { homophones.surfaces(for: $0) } ?? []
        for value in customValues + symbolValues + dictionaryValues where seen.insert(value).inserted {
            result.append(value)
            if result.count == maximumAdded { break }
        }
        return result
    }

    public static func isHiraganaWord(_ value: String) -> Bool {
        !value.isEmpty && value.unicodeScalars.allSatisfy {
            (0x3041 ... 0x3096).contains($0.value) || $0.value == 0x30FC
        }
    }

    fileprivate func customCandidates(for source: String) -> [String] {
        custom.surfaces(for: source)
    }

    private struct Index: Sendable {
        struct Row: Sendable {
            let key: Range<Int>
            let values: Range<Int>
        }
        let bytes: [UInt8]
        let rows: [Row]

        init(_ tsv: String) {
            let bytes = Array(tsv.utf8)
            var parsed: [Row] = []
            var start = 0
            for end in 0...bytes.count where end == bytes.count || bytes[end] == 10 {
                defer { start = end + 1 }
                guard start < end,
                      !(bytes[start] == 35 && (start + 1 == end || bytes[start + 1] == 32)),
                      let tab = bytes[start..<end].firstIndex(of: 9),
                      tab > start, tab + 1 < end else { continue }
                parsed.append(Row(key: start..<tab, values: (tab + 1)..<end))
            }
            // Official generated rows are already sorted; custom/fixture tables need not be.
            let ordered = zip(parsed, parsed.dropFirst()).allSatisfy {
                !bytes[$1.key].lexicographicallyPrecedes(bytes[$0.key])
            }
            if !ordered {
                parsed.sort { bytes[$0.key].lexicographicallyPrecedes(bytes[$1.key]) }
            }
            self.bytes = bytes
            rows = parsed
        }

        func surfaces(for key: String) -> [String] {
            let needle = Array(key.utf8)
            var low = 0
            var high = rows.count
            while low < high {
                let mid = (low + high) / 2
                if bytes[rows[mid].key].lexicographicallyPrecedes(needle) {
                    low = mid + 1
                } else {
                    high = mid
                }
            }
            guard low < rows.count, bytes[rows[low].key].elementsEqual(needle) else { return [] }
            return String(decoding: bytes[rows[low].values], as: UTF8.self)
                .split(separator: "\t").map {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines)
                }.filter { !$0.isEmpty }
        }
    }
}

/// Display metadata stays separate from the strings inserted into the host app.
public struct AdditionalCandidateList: Equatable, Sendable {
    public let options: [String]
    public let dictionaryCandidates: Set<String>

    public init(
        original: String,
        current: String,
        existingOptions: [String],
        existingDictionaryCandidates: Set<String> = [],
        llmCandidates: [String],
        dictionary: SupplementalCandidateDictionary,
        maximumLLMCount: Int = 12,
        maximumDictionaryAdded: Int = 10
    ) {
        let normalized = llmCandidates.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
        var result: [String] = []
        var seen: Set<String> = []
        var dictionarySources: Set<String> = []
        // Keep the current result and its provenance, even across a refresh.
        for candidate in existingOptions where candidate != original
            && (!existingDictionaryCandidates.contains(candidate) || candidate == current) {
            if seen.insert(candidate).inserted {
                result.append(candidate)
                if existingDictionaryCandidates.contains(candidate) {
                    dictionarySources.insert(candidate)
                }
            }
        }
        if !seen.contains(current) {
            result.insert(current, at: 0)
            seen.insert(current)
            if existingDictionaryCandidates.contains(current) { dictionarySources.insert(current) }
        }
        var llmCount = result.count - dictionarySources.count
        let customValues = Set(dictionary.customCandidates(for: original))
        var reserved = Set(normalized.filter { customValues.contains($0) && !seen.contains($0) })
        for candidate in normalized where candidate != original {
            if seen.contains(candidate) { continue }
            guard llmCount < max(0, maximumLLMCount) else { break }
            // Keep a slot for a required custom surface already returned by the LLM,
            // even if it occurs at the end of the response after the visible cap.
            if !reserved.contains(candidate), llmCount >= maximumLLMCount - reserved.count { continue }
            seen.insert(candidate)
            result.append(candidate)
            llmCount += 1
            reserved.remove(candidate)
        }
        // Exclude all LLM response strings, including any omitted by the UI cap:
        // an LLM result must never be relabelled as dictionary-derived.
        let excluded = seen.union(normalized).union([original])
        let added = dictionary.candidates(
            for: original, llmCandidates: normalized, excluding: excluded,
            maximumAdded: maximumDictionaryAdded
        )
        result.append(contentsOf: added)
        dictionarySources.formUnion(added)
        if !result.contains(original) { result.append(original) }
        options = result
        dictionaryCandidates = dictionarySources
    }
}
