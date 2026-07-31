import Foundation

public struct ConversionSnapshot: Equatable, Sendable {
    public let source: String
    public let textToReplace: String
    public let revision: UInt64
    public let expectedSuffix: String

    public init(
        source: String,
        textToReplace: String? = nil,
        revision: UInt64,
        expectedSuffix: String
    ) {
        self.source = source
        self.textToReplace = textToReplace ?? source
        self.revision = revision
        self.expectedSuffix = expectedSuffix
    }
}

public struct CompositionTracker: Equatable, Sendable {
    public private(set) var source = ""
    public private(set) var revision: UInt64 = 0
    public private(set) var isReplaceable = true
    public private(set) var respectsSlashBoundary = true

    public var expectedSuffix: String {
        String(source.suffix(maximumSuffixLength))
    }

    public var hasComposition: Bool {
        !source.isEmpty
    }

    private let maximumSourceLength: Int
    private let maximumSuffixLength: Int

    public init(maximumSourceLength: Int = 512, maximumSuffixLength: Int = 32) {
        precondition(maximumSourceLength > 0)
        precondition(maximumSuffixLength > 0)
        self.maximumSourceLength = maximumSourceLength
        self.maximumSuffixLength = maximumSuffixLength
    }

    public mutating func append(_ text: String) {
        guard !text.isEmpty else {
            return
        }

        if !isReplaceable {
            reset()
        }

        source.append(text)
        let overflow = source.count - maximumSourceLength
        if overflow > 0 {
            source.removeFirst(overflow)
        }
        revision &+= 1
    }

    @discardableResult
    public mutating func startComposition(
        with text: String,
        respectsSlashBoundary: Bool = true
    ) -> Bool {
        guard !text.isEmpty, text.count <= maximumSourceLength else {
            return false
        }
        source = text
        isReplaceable = true
        self.respectsSlashBoundary = respectsSlashBoundary
        revision &+= 1
        return true
    }

    @discardableResult
    public mutating func deleteLast() -> Bool {
        guard isReplaceable, !source.isEmpty else {
            return false
        }
        source.removeLast()
        revision &+= 1
        return true
    }

    public mutating func invalidate() {
        isReplaceable = false
        revision &+= 1
    }

    public mutating func reset() {
        source.removeAll(keepingCapacity: true)
        isReplaceable = true
        respectsSlashBoundary = true
        revision &+= 1
    }

    public func matches(documentContextBeforeInput context: String?) -> Bool {
        guard
            isReplaceable,
            !expectedSuffix.isEmpty,
            let context
        else {
            return false
        }
        return context.hasSuffix(expectedSuffix)
    }

    public func snapshot() -> ConversionSnapshot? {
        guard isReplaceable, !source.isEmpty else {
            return nil
        }

        let conversionSource: String
        let textToReplace: String
        if respectsSlashBoundary, let boundary = source.lastIndex(of: "/") {
            let targetStart = source.index(after: boundary)
            conversionSource = String(source[targetStart...])
            textToReplace = String(source[boundary...])
        } else {
            conversionSource = source
            textToReplace = source
        }
        guard !conversionSource.isEmpty else {
            return nil
        }

        return ConversionSnapshot(
            source: conversionSource,
            textToReplace: textToReplace,
            revision: revision,
            expectedSuffix: String(textToReplace.suffix(maximumSuffixLength))
        )
    }
}
