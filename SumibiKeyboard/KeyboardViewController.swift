import SumibiCore
import UIKit

final class KeyboardViewController: UIInputViewController {
    private struct CandidateSession {
        let original: String
        let options: [String]
        var current: String
    }

    private lazy var sharedSettings = SharedSettingsStore()
    private let candidateStack = UIStackView()
    private var letterButtons: [UIButton] = []
    private var compositionTracker = CompositionTracker()
    private var pendingConversion: ConversionSnapshot?
    private var candidateSession: CandidateSession?
    private var conversionTask: Task<Void, Never>?
    private var activeRequestID: UUID?
    private var convertButton: UIButton?
    private var isShifted = false

    override func viewDidLoad() {
        super.viewDidLoad()
        _ = sharedSettings?.loadProviderConfiguration()
        configureKeyboard()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        conversionTask?.cancel()
        conversionTask = nil
        activeRequestID = nil
        compositionTracker.reset()
        pendingConversion = nil
        candidateSession = nil
        refreshConvertButton()
    }

    private func configureKeyboard() {
        view.backgroundColor = .systemGray5

        let keyRows = UIStackView(arrangedSubviews: [
            makeLetterRow(["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"]),
            makeLetterRow(["a", "s", "d", "f", "g", "h", "j", "k", "l"]),
            makeThirdRow(),
            makeBottomRow(),
        ])
        keyRows.axis = .vertical
        keyRows.spacing = 8
        keyRows.distribution = .fillEqually

        let candidateBar = makeCandidateBar()
        let keyboardStack = UIStackView(arrangedSubviews: [candidateBar, keyRows])
        keyboardStack.axis = .vertical
        keyboardStack.spacing = 8
        keyboardStack.distribution = .fill
        keyboardStack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(keyboardStack)
        NSLayoutConstraint.activate([
            candidateBar.heightAnchor.constraint(equalToConstant: 40),
            keyboardStack.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            keyboardStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 6),
            keyboardStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -6),
            keyboardStack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8),
            view.heightAnchor.constraint(greaterThanOrEqualToConstant: 264),
        ])
        showCandidateMessage("ローマ字を入力して変換")
    }

    private func makeCandidateBar() -> UIView {
        let container = UIView()
        container.backgroundColor = .secondarySystemBackground
        container.layer.cornerRadius = 8

        let scrollView = UIScrollView()
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        candidateStack.axis = .horizontal
        candidateStack.spacing = 8
        candidateStack.alignment = .center
        candidateStack.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(scrollView)
        scrollView.addSubview(candidateStack)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: container.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            candidateStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            candidateStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            candidateStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            candidateStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            candidateStack.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
        ])
        return container
    }

    private func makeLetterRow(_ letters: [String]) -> UIStackView {
        let buttons = letters.map(makeLetterButton)
        return makeRow(buttons)
    }

    private func makeThirdRow() -> UIStackView {
        let shiftButton = makeSpecialButton(
            title: "⇧",
            accessibilityLabel: "Shift",
            action: #selector(shiftTapped)
        )
        let deleteButton = makeSpecialButton(
            title: "⌫",
            accessibilityLabel: "削除",
            action: #selector(deleteTapped)
        )
        let letters = ["z", "x", "c", "v", "b", "n", "m"].map(makeLetterButton)
        return makeRow([shiftButton] + letters + [deleteButton])
    }

    private func makeBottomRow() -> UIStackView {
        let nextKeyboardButton = makeKeyButton(
            title: "🌐",
            accessibilityLabel: "次のキーボード"
        )
        nextKeyboardButton.addTarget(
            self,
            action: #selector(handleInputModeList(from:with:)),
            for: .allTouchEvents
        )

        let spaceButton = makeSpecialButton(
            title: "空白",
            accessibilityLabel: "空白",
            action: #selector(spaceTapped)
        )
        let convertButton = makeSpecialButton(
            title: "変換",
            accessibilityLabel: "変換",
            action: #selector(convertTapped)
        )
        let returnButton = makeSpecialButton(
            title: "改行",
            accessibilityLabel: "改行",
            action: #selector(returnTapped)
        )
        self.convertButton = convertButton
        refreshConvertButton()

        let row = makeRow([nextKeyboardButton, spaceButton, convertButton, returnButton])
        row.distribution = .fill
        spaceButton.widthAnchor.constraint(
            equalTo: nextKeyboardButton.widthAnchor,
            multiplier: 3
        ).isActive = true
        convertButton.widthAnchor.constraint(equalTo: nextKeyboardButton.widthAnchor).isActive = true
        returnButton.widthAnchor.constraint(equalTo: nextKeyboardButton.widthAnchor).isActive = true
        return row
    }

    private func makeRow(_ buttons: [UIButton]) -> UIStackView {
        let row = UIStackView(arrangedSubviews: buttons)
        row.axis = .horizontal
        row.spacing = 6
        row.distribution = .fillEqually
        return row
    }

    private func makeLetterButton(_ letter: String) -> UIButton {
        let button = makeKeyButton(
            title: displayedLetter(letter),
            accessibilityLabel: letter.uppercased()
        )
        button.accessibilityIdentifier = letter
        button.addTarget(self, action: #selector(letterTapped), for: .touchUpInside)
        letterButtons.append(button)
        return button
    }

    private func makeSpecialButton(
        title: String,
        accessibilityLabel: String,
        action: Selector
    ) -> UIButton {
        let button = makeKeyButton(title: title, accessibilityLabel: accessibilityLabel)
        button.configuration?.baseBackgroundColor = .systemGray3
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    private func makeKeyButton(title: String, accessibilityLabel: String) -> UIButton {
        var configuration = UIButton.Configuration.filled()
        configuration.title = title
        configuration.baseBackgroundColor = .systemBackground
        configuration.baseForegroundColor = .label
        configuration.cornerStyle = .medium
        configuration.contentInsets = NSDirectionalEdgeInsets(
            top: 4,
            leading: 2,
            bottom: 4,
            trailing: 2
        )

        let button = UIButton(configuration: configuration)
        button.titleLabel?.font = .systemFont(ofSize: 20)
        button.accessibilityLabel = accessibilityLabel
        return button
    }

    private func displayedLetter(_ letter: String) -> String {
        isShifted ? letter.uppercased() : letter
    }

    private func refreshLetterTitles() {
        for button in letterButtons {
            guard let letter = button.accessibilityIdentifier else {
                continue
            }
            button.configuration?.title = displayedLetter(letter)
        }
    }

    private func clearCandidateBar() {
        for view in candidateStack.arrangedSubviews {
            candidateStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
    }

    private func showCandidateMessage(_ message: String, showsProgress: Bool = false) {
        clearCandidateBar()

        if showsProgress {
            let indicator = UIActivityIndicatorView(style: .medium)
            indicator.startAnimating()
            candidateStack.addArrangedSubview(indicator)
        }

        let label = UILabel()
        label.text = message
        label.textColor = .secondaryLabel
        label.font = .systemFont(ofSize: 15)
        candidateStack.addArrangedSubview(label)
    }

    private func showCandidates() {
        guard let session = candidateSession else {
            showCandidateMessage("候補がありません")
            return
        }

        clearCandidateBar()
        for (index, option) in session.options.enumerated() {
            var configuration = UIButton.Configuration.gray()
            configuration.title = option == session.original ? "原文" : option
            configuration.baseForegroundColor = .label
            configuration.cornerStyle = .capsule

            let button = UIButton(configuration: configuration)
            button.tag = index
            button.accessibilityLabel = option == session.original
                ? "原文、\(option)"
                : "変換候補、\(option)"
            button.isSelected = option == session.current
            button.addTarget(self, action: #selector(candidateTapped), for: .touchUpInside)
            candidateStack.addArrangedSubview(button)
        }
    }

    private func cancelConversionForEditing() {
        conversionTask?.cancel()
        conversionTask = nil
        activeRequestID = nil
        pendingConversion = nil
        candidateSession = nil
        showCandidateMessage("入力中")
    }

    private func insertTrackedText(_ text: String) {
        cancelConversionForEditing()

        if compositionTracker.hasComposition,
           !compositionTracker.matches(
               documentContextBeforeInput: textDocumentProxy.documentContextBeforeInput
           ) {
            compositionTracker.reset()
        }

        textDocumentProxy.insertText(text)
        compositionTracker.append(text)
        refreshConvertButton()
    }

    private func refreshConvertButton() {
        let isEnabled = compositionTracker.hasComposition
            && compositionTracker.isReplaceable
            && activeRequestID == nil
        convertButton?.isEnabled = isEnabled
        convertButton?.alpha = isEnabled ? 1 : 0.45
        convertButton?.accessibilityValue = isEnabled
            ? "変換対象\(compositionTracker.source.count)文字"
            : "変換対象なし"
    }

    private func replaceHostText(_ current: String, with replacement: String) {
        for _ in current {
            textDocumentProxy.deleteBackward()
        }
        textDocumentProxy.insertText(replacement)
    }

    private func finishConversion(
        _ response: ConversionResponse,
        snapshot: ConversionSnapshot,
        requestID: UUID
    ) {
        guard activeRequestID == requestID else {
            return
        }
        activeRequestID = nil
        conversionTask = nil

        let candidates = Array(
            response.candidates
                .filter { !$0.isEmpty }
                .reduce(into: [String]()) { unique, candidate in
                    if !unique.contains(candidate) {
                        unique.append(candidate)
                    }
                }
                .prefix(3)
        )
        guard let firstCandidate = candidates.first else {
            pendingConversion = nil
            showCandidateMessage("変換候補がありません")
            refreshConvertButton()
            return
        }

        guard
            compositionTracker.revision == snapshot.revision,
            compositionTracker.matches(
                documentContextBeforeInput: textDocumentProxy.documentContextBeforeInput
            )
        else {
            compositionTracker.invalidate()
            pendingConversion = nil
            showCandidateMessage("入力内容が変更されたため置換しません")
            refreshConvertButton()
            return
        }

        replaceHostText(snapshot.source, with: firstCandidate)
        var options = candidates
        if !options.contains(snapshot.source) {
            options.append(snapshot.source)
        }
        candidateSession = CandidateSession(
            original: snapshot.source,
            options: options,
            current: firstCandidate
        )
        pendingConversion = nil
        compositionTracker.reset()
        showCandidates()
        refreshConvertButton()
    }

    private func failConversion(requestID: UUID) {
        guard activeRequestID == requestID else {
            return
        }
        activeRequestID = nil
        conversionTask = nil
        pendingConversion = nil
        showCandidateMessage("モック変換に失敗しました")
        refreshConvertButton()
    }

    private func makeConversionClient() -> (any ConversionClient)? {
        guard let configuration = sharedSettings?.loadProviderConfiguration() else {
            return MockConversionClient()
        }
        if configuration.endpoint.isEmpty && configuration.model.isEmpty {
            return MockConversionClient()
        }
        guard
            let endpoint = URL(string: configuration.endpoint),
            !configuration.model.isEmpty
        else {
            showCandidateMessage("APIの設定を確認してください")
            return nil
        }
        guard hasFullAccess else {
            showCandidateMessage("API変換にはフルアクセスが必要です")
            return nil
        }

        let apiKey = try? APIKeyStore().load()
        return OpenAICompatibleClient(
            configuration: OpenAICompatibleConfiguration(
                endpoint: endpoint,
                model: configuration.model,
                apiKey: apiKey
            )
        )
    }

    @objc private func letterTapped(_ sender: UIButton) {
        guard let letter = sender.accessibilityIdentifier else {
            return
        }
        insertTrackedText(displayedLetter(letter))

        if isShifted {
            isShifted = false
            refreshLetterTitles()
        }
    }

    @objc private func shiftTapped() {
        isShifted.toggle()
        refreshLetterTitles()
    }

    @objc private func deleteTapped() {
        cancelConversionForEditing()
        if compositionTracker.matches(
            documentContextBeforeInput: textDocumentProxy.documentContextBeforeInput
        ) {
            compositionTracker.deleteLast()
        } else {
            compositionTracker.reset()
        }
        textDocumentProxy.deleteBackward()
        refreshConvertButton()
    }

    @objc private func spaceTapped() {
        insertTrackedText(" ")
    }

    @objc private func convertTapped() {
        guard
            compositionTracker.matches(
                documentContextBeforeInput: textDocumentProxy.documentContextBeforeInput
            ),
            let snapshot = compositionTracker.snapshot()
        else {
            compositionTracker.invalidate()
            pendingConversion = nil
            refreshConvertButton()
            return
        }

        pendingConversion = snapshot
        guard let conversionClient = makeConversionClient() else {
            pendingConversion = nil
            refreshConvertButton()
            return
        }
        let requestID = UUID()
        activeRequestID = requestID
        showCandidateMessage("変換中…", showsProgress: true)
        refreshConvertButton()

        let request = ConversionRequest(
            source: snapshot.source,
            surroundingContext: textDocumentProxy.documentContextBeforeInput ?? ""
        )
        conversionTask = Task { [weak self, conversionClient] in
            do {
                let response = try await conversionClient.convert(request)
                guard let self else {
                    return
                }
                self.finishConversion(response, snapshot: snapshot, requestID: requestID)
            } catch is CancellationError {
                return
            } catch {
                self?.failConversion(requestID: requestID)
            }
        }
    }

    @objc private func candidateTapped(_ sender: UIButton) {
        guard
            var session = candidateSession,
            session.options.indices.contains(sender.tag)
        else {
            return
        }

        let expectedSuffix = String(session.current.suffix(32))
        guard
            !expectedSuffix.isEmpty,
            textDocumentProxy.documentContextBeforeInput?.hasSuffix(expectedSuffix) == true
        else {
            candidateSession = nil
            showCandidateMessage("入力内容が変更されたため置換しません")
            return
        }

        let replacement = session.options[sender.tag]
        guard replacement != session.current else {
            return
        }
        replaceHostText(session.current, with: replacement)
        session.current = replacement
        candidateSession = session
        showCandidates()
    }

    @objc private func returnTapped() {
        cancelConversionForEditing()
        textDocumentProxy.insertText("\n")
        compositionTracker.reset()
        refreshConvertButton()
    }
}
