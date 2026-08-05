import Foundation

public struct UserDictionaryEntry: Equatable, Sendable {
    public let reading: String
    public let replacement: String

    public init(reading: String, replacement: String) {
        self.reading = reading
        self.replacement = replacement
    }
}

public struct UserDictionaryValidationError: Equatable, Identifiable, Sendable {
    public let lineNumber: Int?
    public let reason: String
    public let line: String?

    public var id: String {
        "\(lineNumber.map(String.init) ?? "dictionary"):\(reason):\(line ?? "")"
    }

    public init(lineNumber: Int?, reason: String, line: String?) {
        self.lineNumber = lineNumber
        self.reason = reason
        self.line = line
    }
}

public struct UserDictionaryValidationResult: Equatable, Sendable {
    public let entries: [UserDictionaryEntry]
    public let errors: [UserDictionaryValidationError]

    public var isValid: Bool { errors.isEmpty }

    public init(
        entries: [UserDictionaryEntry],
        errors: [UserDictionaryValidationError]
    ) {
        self.entries = entries
        self.errors = errors
    }
}

public enum UserDictionary {
    public static let maximumEntryCount = 100
    public static let maximumCharacterCount = 2_000

    public static func validate(_ text: String) -> UserDictionaryValidationResult {
        var entries: [UserDictionaryEntry] = []
        var errors: [UserDictionaryValidationError] = []
        var firstLineByReading: [String: Int] = [:]

        for (offset, substring) in text.split(
            separator: "\n",
            omittingEmptySubsequences: false
        ).enumerated() {
            let lineNumber = offset + 1
            let line = String(substring).trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                continue
            }
            guard let separator = line.firstIndex(of: "=") else {
                errors.append(error(lineNumber, "区切りの「=」がありません", line))
                continue
            }

            let reading = line[..<separator].trimmingCharacters(in: .whitespaces)
            let replacement = line[line.index(after: separator)...]
                .trimmingCharacters(in: .whitespaces)
            var lineHasError = false

            if reading.isEmpty {
                errors.append(error(lineNumber, "よみが空です", line))
                lineHasError = true
            } else if reading.contains(where: { $0.isASCII && $0.isUppercase }) {
                errors.append(error(lineNumber, "よみに大文字は使えません", line))
                lineHasError = true
            } else if reading.contains(where: { !$0.isASCII }) {
                errors.append(error(lineNumber, "よみにはローマ字と記号だけを使えます", line))
                lineHasError = true
            } else if reading.contains(where: { $0.isWhitespace }) {
                errors.append(error(lineNumber, "よみに空白は使えません", line))
                lineHasError = true
            } else if reading.contains(where: { !$0.isASCIIPrintable }) {
                errors.append(error(lineNumber, "よみにはローマ字と記号だけを使えます", line))
                lineHasError = true
            }

            if replacement.isEmpty {
                errors.append(error(lineNumber, "変換後が空です", line))
                lineHasError = true
            }

            if !reading.isEmpty, let firstLine = firstLineByReading[String(reading)] {
                errors.append(error(
                    lineNumber,
                    "よみ「\(reading)」が\(firstLine)行目と重複しています",
                    line
                ))
                lineHasError = true
            } else if !reading.isEmpty {
                firstLineByReading[String(reading)] = lineNumber
            }

            if !lineHasError {
                entries.append(UserDictionaryEntry(
                    reading: String(reading),
                    replacement: String(replacement)
                ))
            }
        }

        let nonemptyLineCount = text.split(separator: "\n").filter {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.count
        if nonemptyLineCount > maximumEntryCount {
            errors.append(UserDictionaryValidationError(
                lineNumber: nil,
                reason: "登録が100件を超えています（\(nonemptyLineCount)件）",
                line: nil
            ))
        }
        if text.count > maximumCharacterCount {
            errors.append(UserDictionaryValidationError(
                lineNumber: nil,
                reason: "2,000文字を超えています（\(text.count)文字）",
                line: nil
            ))
        }

        return UserDictionaryValidationResult(entries: entries, errors: errors)
    }

    private static func error(
        _ lineNumber: Int,
        _ reason: String,
        _ line: String
    ) -> UserDictionaryValidationError {
        UserDictionaryValidationError(
            lineNumber: lineNumber,
            reason: reason,
            line: line
        )
    }
}

private extension Character {
    var isASCIIPrintable: Bool {
        guard let scalar = unicodeScalars.only else { return false }
        return scalar.value >= 0x21 && scalar.value <= 0x7E
    }
}

private extension String.UnicodeScalarView {
    var only: Unicode.Scalar? {
        count == 1 ? first : nil
    }
}
