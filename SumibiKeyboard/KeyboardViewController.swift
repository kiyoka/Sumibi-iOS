import SumibiCore
import UIKit

private final class AudioFeedbackInputView: UIInputView, UIInputViewAudioFeedback {
    var enableInputClicksWhenVisible: Bool {
        true
    }
}

final class KeyboardViewController: UIInputViewController {
    private enum RepeatableKeyKind {
        case letter
        case symbol
        case number
        case delete
        case space
    }

    private struct CandidateSession {
        let original: String
        let undoOriginal: String
        let surroundingContext: String
        var options: [String]
        var current: String
        var hasRequestedAdditionalCandidates: Bool
    }

    private struct UndoRecord {
        let original: String
        var replacement: String
    }

    private lazy var sharedSettings = SharedSettingsStore()
    private let hapticFeedbackGenerator = UIImpactFeedbackGenerator(style: .light)
    private let candidateStack = UIStackView()
    private var letterButtons: [UIButton] = []
    private var compositionTracker = CompositionTracker()
    private var pendingConversion: ConversionSnapshot?
    private var candidateSession: CandidateSession?
    private var undoRecord: UndoRecord?
    private var retrySnapshot: ConversionSnapshot?
    private var additionalCandidateErrorMessage: String?
    private var conversionTask: Task<Void, Never>?
    private var activeRequestID: UUID?
    private var convertButton: UIButton?
    private var keyRowsStack: UIStackView?
    private var candidateBarHeightConstraint: NSLayoutConstraint?
    private var candidateBarBottomSpacingConstraint: NSLayoutConstraint?
    private var keyRowsHeightConstraint: NSLayoutConstraint?
    private var keyRowsBottomConstraint: NSLayoutConstraint?
    private var keyboardHeightConstraint: NSLayoutConstraint?
    private var numberDividerCenterYConstraint: NSLayoutConstraint?
    private var symbolPanelBottomSpacingConstraint: NSLayoutConstraint?
    private var symbolPanelHeightConstraint: NSLayoutConstraint?
    private var symbolPanel: UIStackView?
    private var symbolToggleButton: UIButton?
    private var repeatableKeyKinds: [ObjectIdentifier: RepeatableKeyKind] = [:]
    private var keyRepeatTimer: Timer?
    private weak var repeatingButton: UIButton?
    private var isCollapsingSymbolPanel = false
    private var isSymbolPanelExpanded = false
    private var isShifted = false

    override func loadView() {
        let keyboardInputView = AudioFeedbackInputView(
            frame: .zero,
            inputViewStyle: .keyboard
        )
        inputView = keyboardInputView
        view = keyboardInputView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        _ = sharedSettings?.loadProviderConfiguration()
        configureKeyboard()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopKeyRepeat()
        setSymbolPanelExpanded(false, animated: false)
        conversionTask?.cancel()
        conversionTask = nil
        activeRequestID = nil
        compositionTracker.reset()
        pendingConversion = nil
        candidateSession = nil
        undoRecord = nil
        retrySnapshot = nil
        additionalCandidateErrorMessage = nil
        refreshConvertButton()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateKeyboardHeight()
    }

    private func configureKeyboard() {
        view.backgroundColor = .systemGray5
        view.layer.cornerCurve = .continuous
        view.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        view.layer.masksToBounds = true

        let numberRow = makeNumberRow()
        let keyRows = UIStackView(arrangedSubviews: [
            numberRow,
            makeLetterRow(["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"]),
            makeSecondRow(),
            makeThirdRow(),
            makeSymbolRow(),
            makeBottomRow(),
        ])
        keyRows.axis = .vertical
        keyRows.spacing = 8
        keyRows.distribution = .fillEqually
        keyRows.translatesAutoresizingMaskIntoConstraints = false
        keyRowsStack = keyRows
        addNumberDivider(to: keyRows, below: numberRow)

        let candidateBar = makeCandidateBar()
        candidateBar.translatesAutoresizingMaskIntoConstraints = false
        let symbolPanel = makeExpandedSymbolPanel()
        symbolPanel.translatesAutoresizingMaskIntoConstraints = false
        symbolPanel.alpha = 0
        symbolPanel.isUserInteractionEnabled = false
        symbolPanel.accessibilityElementsHidden = true
        self.symbolPanel = symbolPanel

        view.addSubview(candidateBar)
        view.addSubview(symbolPanel)
        view.addSubview(keyRows)
        let candidateBarHeightConstraint = candidateBar.heightAnchor.constraint(equalToConstant: 40)
        let candidateBarBottomSpacingConstraint = candidateBar.bottomAnchor.constraint(
            equalTo: symbolPanel.topAnchor
        )
        let keyRowsHeightConstraint = keyRows.heightAnchor.constraint(equalToConstant: 288)
        let keyRowsBottomConstraint = keyRows.bottomAnchor.constraint(
            equalTo: view.bottomAnchor,
            constant: -8
        )
        let keyboardHeightConstraint = view.heightAnchor.constraint(equalToConstant: 352)
        let symbolPanelHeightConstraint = symbolPanel.heightAnchor.constraint(equalToConstant: 0)
        let symbolPanelBottomSpacingConstraint = symbolPanel.bottomAnchor.constraint(
            equalTo: keyRows.topAnchor,
            constant: -8
        )
        self.candidateBarHeightConstraint = candidateBarHeightConstraint
        self.candidateBarBottomSpacingConstraint = candidateBarBottomSpacingConstraint
        self.keyRowsHeightConstraint = keyRowsHeightConstraint
        self.keyRowsBottomConstraint = keyRowsBottomConstraint
        self.keyboardHeightConstraint = keyboardHeightConstraint
        self.symbolPanelHeightConstraint = symbolPanelHeightConstraint
        self.symbolPanelBottomSpacingConstraint = symbolPanelBottomSpacingConstraint
        NSLayoutConstraint.activate([
            candidateBarHeightConstraint,
            candidateBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 6),
            candidateBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -6),
            candidateBarBottomSpacingConstraint,
            symbolPanel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 6),
            symbolPanel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -6),
            symbolPanelBottomSpacingConstraint,
            keyRows.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 6),
            keyRows.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -6),
            keyRowsHeightConstraint,
            keyRowsBottomConstraint,
            keyboardHeightConstraint,
            symbolPanelHeightConstraint,
        ])
        updateKeyboardHeight()
        showCandidateMessage("ローマ字を入力して変換")
    }

    private func updateKeyboardHeight() {
        let isLandscape = (view.window?.windowScene?.interfaceOrientation.isLandscape)
            ?? (traitCollection.verticalSizeClass == .compact)
        view.layer.cornerRadius = isLandscape ? 12 : 16
        let normalHeight: CGFloat = isLandscape ? 216 : 352
        let sectionSpacing: CGFloat = isLandscape ? 4 : 8
        let expandedPanelHeight: CGFloat = isLandscape ? 84 : 112
        let expandedExtraHeight = expandedPanelHeight + sectionSpacing
        keyboardHeightConstraint?.constant = normalHeight
            + ((isSymbolPanelExpanded || isCollapsingSymbolPanel) ? expandedExtraHeight : 0)
        symbolPanelHeightConstraint?.constant = isSymbolPanelExpanded
            ? expandedPanelHeight
            : 0
        candidateBarHeightConstraint?.constant = isLandscape ? 32 : 40
        candidateBarBottomSpacingConstraint?.constant = isSymbolPanelExpanded
            ? -sectionSpacing
            : 0
        keyRowsHeightConstraint?.constant = isLandscape ? 172 : 288
        keyRowsBottomConstraint?.constant = isLandscape ? -4 : -8
        symbolPanelBottomSpacingConstraint?.constant = -sectionSpacing
        keyRowsStack?.spacing = isLandscape ? 4 : 8
        numberDividerCenterYConstraint?.constant = isLandscape ? 2 : 4
        symbolPanel?.spacing = isLandscape ? 4 : 6
    }

    private func addNumberDivider(to keyRows: UIStackView, below numberRow: UIView) {
        let divider = UIView()
        divider.backgroundColor = UIColor { traits in
            traits.userInterfaceStyle == .dark ? .systemGray2 : .systemGray
        }
        divider.isUserInteractionEnabled = false
        divider.isAccessibilityElement = false
        divider.translatesAutoresizingMaskIntoConstraints = false
        keyRows.addSubview(divider)

        let centerYConstraint = divider.centerYAnchor.constraint(
            equalTo: numberRow.bottomAnchor,
            constant: 4
        )
        numberDividerCenterYConstraint = centerYConstraint
        NSLayoutConstraint.activate([
            divider.leadingAnchor.constraint(equalTo: keyRows.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: keyRows.trailingAnchor),
            divider.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),
            centerYConstraint,
        ])
    }

    private func makeCandidateBar() -> UIView {
        let container = UIView()
        container.backgroundColor = .secondarySystemBackground
        container.layer.cornerRadius = 12
        container.layer.cornerCurve = .continuous
        container.layer.masksToBounds = true

        let icon = UIImage(named: "KeyboardIcon")?.withRenderingMode(.alwaysTemplate)
        let iconView = UIImageView(image: icon)
        iconView.contentMode = .scaleAspectFit
        iconView.tintColor = .label
        iconView.isAccessibilityElement = false
        iconView.translatesAutoresizingMaskIntoConstraints = false

        let scrollView = UIScrollView()
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        candidateStack.axis = .horizontal
        candidateStack.spacing = 8
        candidateStack.alignment = .center
        candidateStack.translatesAutoresizingMaskIntoConstraints = false

        let handleButton = UIButton(type: .system)
        handleButton.setTitle("━", for: .normal)
        handleButton.setTitleColor(.secondaryLabel, for: .normal)
        handleButton.titleLabel?.font = .systemFont(ofSize: 18, weight: .bold)
        handleButton.accessibilityLabel = "記号一覧ハンドル"
        handleButton.accessibilityHint = "上へスワイプして開き、下へスワイプして閉じます"
        handleButton.addTarget(self, action: #selector(symbolHandleTapped), for: .touchUpInside)
        let panGesture = UIPanGestureRecognizer(
            target: self,
            action: #selector(symbolHandlePanned)
        )
        handleButton.addGestureRecognizer(panGesture)
        handleButton.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(iconView)
        container.addSubview(scrollView)
        container.addSubview(handleButton)
        scrollView.addSubview(candidateStack)
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 6),
            iconView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 28),
            iconView.heightAnchor.constraint(equalTo: iconView.widthAnchor),
            scrollView.topAnchor.constraint(equalTo: container.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            candidateStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            candidateStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            candidateStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            candidateStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            candidateStack.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
            handleButton.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            handleButton.topAnchor.constraint(equalTo: container.topAnchor, constant: -2),
            handleButton.widthAnchor.constraint(equalToConstant: 44),
            handleButton.heightAnchor.constraint(equalToConstant: 16),
        ])
        return container
    }

    private func makeExpandedSymbolPanel() -> UIStackView {
        let rows = [
            ["@", "#", "$", "%", "&", "*", "(", ")"],
            ["_", "+", "=", "[", "]", "{", "}", "\\"],
            ["|", ":", ";", "\"", "'", "<", ">"],
        ].map { symbols in
            makeRow(symbols.map(makeSymbolButton))
        }
        let panel = UIStackView(arrangedSubviews: rows)
        panel.axis = .vertical
        panel.spacing = 6
        panel.distribution = .fillEqually
        panel.accessibilityIdentifier = "expanded-symbol-panel"
        return panel
    }

    private func makeLetterRow(_ letters: [String]) -> UIStackView {
        let buttons = letters.map(makeLetterButton)
        return makeRow(buttons)
    }

    private func makeNumberRow() -> UIStackView {
        makeRow(["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"].map(makeNumberButton))
    }

    private func makeSecondRow() -> UIStackView {
        let letters = ["a", "s", "d", "f", "g", "h", "j", "k", "l"].map(makeLetterButton)
        return makeRow(letters + [makeSymbolButton("-")])
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
        registerKeyRepeat(for: deleteButton, kind: .delete)
        let letters = ["z", "x", "c", "v", "b", "n", "m"].map(makeLetterButton)
        let row = makeRow([shiftButton] + letters + [deleteButton])
        row.distribution = .fill

        guard let referenceLetter = letters.first else {
            return row
        }
        shiftButton.widthAnchor.constraint(equalTo: referenceLetter.widthAnchor).isActive = true
        for letterButton in letters.dropFirst() {
            letterButton.widthAnchor.constraint(equalTo: referenceLetter.widthAnchor).isActive = true
        }
        deleteButton.widthAnchor.constraint(
            equalTo: referenceLetter.widthAnchor,
            multiplier: 2
        ).isActive = true
        return row
    }

    private func makeSymbolRow() -> UIStackView {
        makeRow([",", ".", "/", "?", "!"].map(makeSymbolButton))
    }

    private func makeBottomRow() -> UIStackView {
        let symbolButton = makeSpecialButton(
            title: "記号",
            accessibilityLabel: "記号一覧",
            action: #selector(symbolToggleTapped)
        )
        symbolButton.accessibilityIdentifier = "symbol-toggle"
        symbolButton.accessibilityValue = "非表示"
        if needsInputModeSwitchKey {
            symbolButton.accessibilityHint = "長押しで次のキーボードへ切り替えます"
            let longPressGesture = UILongPressGestureRecognizer(
                target: self,
                action: #selector(symbolButtonLongPressed)
            )
            symbolButton.addGestureRecognizer(longPressGesture)
        } else {
            symbolButton.accessibilityHint = "タップで記号一覧を開きます"
        }
        symbolToggleButton = symbolButton

        let spaceButton = makeSpecialButton(
            title: "空白",
            accessibilityLabel: "空白",
            action: #selector(spaceTapped)
        )
        registerKeyRepeat(for: spaceButton, kind: .space)
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

        let row = makeRow([symbolButton, spaceButton, convertButton, returnButton])
        row.distribution = .fill
        spaceButton.widthAnchor.constraint(
            equalTo: symbolButton.widthAnchor,
            multiplier: 3
        ).isActive = true
        convertButton.widthAnchor.constraint(equalTo: symbolButton.widthAnchor).isActive = true
        returnButton.widthAnchor.constraint(equalTo: symbolButton.widthAnchor).isActive = true
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
        registerKeyRepeat(for: button, kind: .letter)
        letterButtons.append(button)
        return button
    }

    private func makeSymbolButton(_ symbol: String) -> UIButton {
        let button = makeKeyButton(
            title: symbol,
            accessibilityLabel: symbolAccessibilityLabel(symbol)
        )
        button.accessibilityIdentifier = symbol
        button.addTarget(self, action: #selector(symbolTapped), for: .touchUpInside)
        registerKeyRepeat(for: button, kind: .symbol)
        return button
    }

    private func makeNumberButton(_ number: String) -> UIButton {
        let button = makeKeyButton(
            title: number,
            accessibilityLabel: "数字 \(number)"
        )
        button.accessibilityIdentifier = number
        button.addTarget(self, action: #selector(numberTapped), for: .touchUpInside)
        registerKeyRepeat(for: button, kind: .number)
        return button
    }

    private func registerKeyRepeat(for button: UIButton, kind: RepeatableKeyKind) {
        repeatableKeyKinds[ObjectIdentifier(button)] = kind
        let gesture = UILongPressGestureRecognizer(
            target: self,
            action: #selector(repeatableKeyLongPressed)
        )
        gesture.minimumPressDuration = 0.85
        gesture.allowableMovement = 20
        button.addGestureRecognizer(gesture)
    }

    private func performRepeatAction(for button: UIButton) {
        guard let kind = repeatableKeyKinds[ObjectIdentifier(button)] else {
            stopKeyRepeat()
            return
        }
        playKeyClick()
        switch kind {
        case .letter:
            letterTapped(button)
        case .symbol:
            symbolTapped(button)
        case .number:
            numberTapped(button)
        case .delete:
            deleteTapped()
        case .space:
            spaceTapped()
        }
    }

    private func startKeyRepeat(for button: UIButton) {
        stopKeyRepeat()
        repeatingButton = button
        performRepeatAction(for: button)

        let timer = Timer(
            timeInterval: 0.085,
            target: self,
            selector: #selector(keyRepeatTimerFired),
            userInfo: nil,
            repeats: true
        )
        keyRepeatTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopKeyRepeat() {
        keyRepeatTimer?.invalidate()
        keyRepeatTimer = nil
        repeatingButton = nil
    }

    @objc private func keyRepeatTimerFired() {
        guard let repeatingButton else {
            stopKeyRepeat()
            return
        }
        performRepeatAction(for: repeatingButton)
    }

    @objc private func repeatableKeyLongPressed(_ gesture: UILongPressGestureRecognizer) {
        guard let button = gesture.view as? UIButton else {
            stopKeyRepeat()
            return
        }
        switch gesture.state {
        case .began:
            startKeyRepeat(for: button)
        case .ended, .cancelled, .failed:
            stopKeyRepeat()
        default:
            break
        }
    }

    private func symbolAccessibilityLabel(_ symbol: String) -> String {
        switch symbol {
        case "!":
            "感嘆符"
        case "-":
            "ハイフン"
        default:
            "記号 \(symbol)"
        }
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
        button.addTarget(self, action: #selector(keyTouchDown), for: .touchDown)
        return button
    }

    @objc private func keyTouchDown() {
        playKeyClick()
        if sharedSettings?.loadHapticFeedbackEnabled() ?? true {
            hapticFeedbackGenerator.prepare()
            hapticFeedbackGenerator.impactOccurred(intensity: 0.7)
        }
    }

    private func playKeyClick() {
        guard sharedSettings?.loadKeyClickSoundEnabled() ?? true else {
            return
        }
        UIDevice.current.playInputClick()
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

    private func addCandidateAction(
        title: String,
        accessibilityLabel: String,
        action: Selector
    ) {
        var configuration = UIButton.Configuration.gray()
        configuration.title = title
        configuration.baseForegroundColor = .label
        configuration.cornerStyle = .capsule

        let button = UIButton(configuration: configuration)
        button.accessibilityLabel = accessibilityLabel
        button.addTarget(self, action: action, for: .touchUpInside)
        candidateStack.addArrangedSubview(button)
    }

    private func showConverting() {
        showCandidateMessage("変換中…", showsProgress: true)
        addCandidateAction(
            title: "キャンセル",
            accessibilityLabel: "変換をキャンセル",
            action: #selector(cancelTapped)
        )
    }

    private func showError(_ message: String, retryable: Bool) {
        showCandidateMessage(message)
        if retryable {
            addCandidateAction(
                title: "再試行",
                accessibilityLabel: "変換を再試行",
                action: #selector(retryTapped)
            )
        }
    }

    private func showCandidates() {
        guard let session = candidateSession else {
            showCandidateMessage("候補がありません")
            return
        }

        clearCandidateBar()
        if undoRecord != nil {
            addCandidateAction(
                title: "↶ Undo",
                accessibilityLabel: "変換を元に戻す",
                action: #selector(undoTapped)
            )
        }
        if let additionalCandidateErrorMessage {
            let label = UILabel()
            label.text = additionalCandidateErrorMessage
            label.textColor = .secondaryLabel
            label.font = .systemFont(ofSize: 13)
            candidateStack.addArrangedSubview(label)
        }
        if !session.hasRequestedAdditionalCandidates {
            addCandidateAction(
                title: "さらに変換候補を取得",
                accessibilityLabel: "さらに変換候補を取得",
                action: #selector(additionalCandidatesTapped)
            )
        }
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
        undoRecord = nil
        retrySnapshot = nil
        additionalCandidateErrorMessage = nil
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
        let snapshot = compositionTracker.snapshot()
        let isEnabled = snapshot != nil && activeRequestID == nil
        convertButton?.isEnabled = isEnabled
        convertButton?.alpha = isEnabled ? 1 : 0.45
        convertButton?.accessibilityValue = isEnabled
            ? "変換対象\(snapshot?.source.count ?? 0)文字"
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
        surroundingContext: String,
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
                .prefix(ConversionCandidateMode.primary.candidateCount)
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

        replaceHostText(snapshot.textToReplace, with: firstCandidate)
        var options = candidates
        if !options.contains(snapshot.source) {
            options.append(snapshot.source)
        }
        candidateSession = CandidateSession(
            original: snapshot.source,
            undoOriginal: snapshot.textToReplace,
            surroundingContext: surroundingContext,
            options: options,
            current: firstCandidate,
            hasRequestedAdditionalCandidates: false
        )
        undoRecord = firstCandidate == snapshot.textToReplace
            ? nil
            : UndoRecord(original: snapshot.textToReplace, replacement: firstCandidate)
        retrySnapshot = nil
        additionalCandidateErrorMessage = nil
        pendingConversion = nil
        compositionTracker.reset()
        showCandidates()
        refreshConvertButton()
    }

    private func failConversion(
        _ error: Error,
        snapshot: ConversionSnapshot,
        requestID: UUID
    ) {
        guard activeRequestID == requestID else {
            return
        }
        activeRequestID = nil
        conversionTask = nil
        pendingConversion = nil
        let presentation = errorPresentation(for: error)
        retrySnapshot = presentation.retryable ? snapshot : nil
        showError(presentation.message, retryable: presentation.retryable)
        refreshConvertButton()
    }

    private func errorPresentation(for error: Error) -> (message: String, retryable: Bool) {
        if let error = error as? OpenAICompatibleClientError {
            switch error {
            case .invalidEndpoint:
                return ("APIのURLが無効です", false)
            case .invalidResponse, .emptyResponse:
                return ("APIから有効な候補を取得できませんでした", true)
            case .invalidCredentials:
                return ("APIキーを確認してください", false)
            case .rateLimited:
                return ("利用回数の上限に達しました", true)
            case .serverError:
                return ("APIサーバーでエラーが発生しました", true)
            case .httpError:
                return ("APIリクエストに失敗しました", false)
            }
        }

        if let error = error as? URLError {
            switch error.code {
            case .timedOut:
                return ("変換がタイムアウトしました", true)
            case .notConnectedToInternet, .networkConnectionLost:
                return ("ネットワークに接続できません", true)
            case .cancelled:
                return ("変換をキャンセルしました", false)
            default:
                return ("通信エラーが発生しました", true)
            }
        }
        return ("変換に失敗しました", true)
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

    private func setSymbolPanelExpanded(_ expanded: Bool, animated: Bool) {
        guard expanded != isSymbolPanelExpanded, let symbolPanel else {
            return
        }

        view.layoutIfNeeded()
        isCollapsingSymbolPanel = animated && !expanded
        isSymbolPanelExpanded = expanded
        symbolPanel.isUserInteractionEnabled = expanded
        symbolPanel.accessibilityElementsHidden = !expanded
        symbolToggleButton?.configuration?.title = expanded ? "戻る" : "記号"
        symbolToggleButton?.accessibilityLabel = expanded
            ? "通常キーボードに戻る"
            : "記号一覧"
        symbolToggleButton?.accessibilityValue = expanded ? "表示中" : "非表示"
        symbolToggleButton?.accessibilityHint = needsInputModeSwitchKey
            ? "タップで\(expanded ? "閉じます" : "開きます")。長押しで次のキーボードへ切り替えます"
            : "タップで\(expanded ? "閉じます" : "開きます")"
        updateKeyboardHeight()

        let updates = {
            symbolPanel.alpha = expanded ? 1 : 0
            self.view.layoutIfNeeded()
        }
        if animated {
            UIView.animate(
                withDuration: 0.2,
                delay: 0,
                options: [.beginFromCurrentState, .curveEaseInOut],
                animations: updates
            ) { [weak self] _ in
                guard let self, self.isSymbolPanelExpanded == expanded else {
                    return
                }
                if !expanded {
                    self.isCollapsingSymbolPanel = false
                    self.updateKeyboardHeight()
                    UIView.performWithoutAnimation {
                        self.view.layoutIfNeeded()
                    }
                }
                UIAccessibility.post(
                    notification: .layoutChanged,
                    argument: expanded ? symbolPanel : self.symbolToggleButton
                )
            }
        } else {
            isCollapsingSymbolPanel = false
            updates()
            UIAccessibility.post(
                notification: .layoutChanged,
                argument: expanded ? symbolPanel : symbolToggleButton
            )
        }
    }

    @objc private func symbolToggleTapped() {
        setSymbolPanelExpanded(!isSymbolPanelExpanded, animated: true)
    }

    @objc private func symbolHandleTapped() {
        symbolToggleTapped()
    }

    @objc private func symbolHandlePanned(_ gesture: UIPanGestureRecognizer) {
        guard gesture.state == .ended else {
            return
        }
        let verticalMovement = gesture.translation(in: gesture.view).y
        if verticalMovement <= -20 {
            setSymbolPanelExpanded(true, animated: true)
        } else if verticalMovement >= 20 {
            setSymbolPanelExpanded(false, animated: true)
        }
    }

    @objc private func symbolButtonLongPressed(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began, needsInputModeSwitchKey else {
            return
        }
        advanceToNextInputMode()
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

    @objc private func symbolTapped(_ sender: UIButton) {
        guard let symbol = sender.accessibilityIdentifier else {
            return
        }
        insertTrackedText(symbol)
    }

    @objc private func numberTapped(_ sender: UIButton) {
        guard let number = sender.accessibilityIdentifier else {
            return
        }
        insertTrackedText(number)
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

        startConversion(snapshot)
    }

    private func startConversion(_ snapshot: ConversionSnapshot) {
        pendingConversion = snapshot
        retrySnapshot = nil
        additionalCandidateErrorMessage = nil
        undoRecord = nil
        guard let conversionClient = makeConversionClient() else {
            pendingConversion = nil
            refreshConvertButton()
            return
        }
        let requestID = UUID()
        activeRequestID = requestID
        showConverting()
        refreshConvertButton()

        let contextBeforeInput = textDocumentProxy.documentContextBeforeInput ?? ""
        let surroundingContext = contextBeforeInput.hasSuffix(snapshot.textToReplace)
            ? String(contextBeforeInput.dropLast(snapshot.textToReplace.count))
            : ""
        let request = ConversionRequest(
            source: snapshot.source,
            surroundingContext: surroundingContext
        )
        conversionTask = Task { [weak self, conversionClient] in
            do {
                let response = try await conversionClient.convert(request)
                guard let self else {
                    return
                }
                self.finishConversion(
                    response,
                    snapshot: snapshot,
                    surroundingContext: surroundingContext,
                    requestID: requestID
                )
            } catch is CancellationError {
                return
            } catch {
                self?.failConversion(error, snapshot: snapshot, requestID: requestID)
            }
        }
    }

    @objc private func additionalCandidatesTapped() {
        guard
            activeRequestID == nil,
            var session = candidateSession,
            !session.hasRequestedAdditionalCandidates
        else {
            return
        }

        let expectedSuffix = String(session.current.suffix(32))
        guard
            !expectedSuffix.isEmpty,
            textDocumentProxy.documentContextBeforeInput?.hasSuffix(expectedSuffix) == true
        else {
            candidateSession = nil
            undoRecord = nil
            showCandidateMessage("入力内容が変更されたため追加候補を取得できません")
            return
        }
        guard let conversionClient = makeConversionClient() else {
            return
        }

        session.hasRequestedAdditionalCandidates = true
        candidateSession = session
        additionalCandidateErrorMessage = nil
        let requestID = UUID()
        activeRequestID = requestID
        showCandidateMessage("追加候補を取得中…", showsProgress: true)
        refreshConvertButton()

        let request = ConversionRequest(
            source: session.original,
            surroundingContext: session.surroundingContext,
            mode: .additional,
            currentConversion: session.current
        )
        conversionTask = Task { [weak self, conversionClient] in
            do {
                let response = try await conversionClient.convert(request)
                self?.finishAdditionalCandidates(response, requestID: requestID)
            } catch is CancellationError {
                return
            } catch {
                self?.failAdditionalCandidates(error, requestID: requestID)
            }
        }
    }

    private func finishAdditionalCandidates(
        _ response: ConversionResponse,
        requestID: UUID
    ) {
        guard activeRequestID == requestID else {
            return
        }
        activeRequestID = nil
        conversionTask = nil

        guard var session = candidateSession else {
            refreshConvertButton()
            return
        }
        let expectedSuffix = String(session.current.suffix(32))
        guard
            !expectedSuffix.isEmpty,
            textDocumentProxy.documentContextBeforeInput?.hasSuffix(expectedSuffix) == true
        else {
            candidateSession = nil
            undoRecord = nil
            showCandidateMessage("入力内容が変更されたため追加候補を表示しません")
            refreshConvertButton()
            return
        }

        let responseCandidates = response.candidates
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var options = session.options.filter { $0 != session.original }
        if !options.contains(session.current) {
            options.insert(session.current, at: 0)
        }
        for candidate in responseCandidates where !options.contains(candidate) {
            guard options.count < ConversionCandidateMode.additional.candidateCount else {
                break
            }
            options.append(candidate)
        }
        guard options.count > 1 else {
            additionalCandidateErrorMessage = "追加候補を取得できませんでした"
            showCandidates()
            refreshConvertButton()
            return
        }

        if !options.contains(session.original) {
            options.append(session.original)
        }
        session.options = options
        candidateSession = session
        additionalCandidateErrorMessage = nil
        showCandidates()
        refreshConvertButton()
    }

    private func failAdditionalCandidates(_ error: Error, requestID: UUID) {
        guard activeRequestID == requestID else {
            return
        }
        activeRequestID = nil
        conversionTask = nil
        let presentation = errorPresentation(for: error)
        additionalCandidateErrorMessage = presentation.message
        showCandidates()
        refreshConvertButton()
    }

    @objc private func cancelTapped() {
        guard activeRequestID != nil else {
            return
        }
        conversionTask?.cancel()
        conversionTask = nil
        activeRequestID = nil
        pendingConversion = nil
        retrySnapshot = nil
        showCandidateMessage("変換をキャンセルしました")
        refreshConvertButton()
    }

    @objc private func retryTapped() {
        guard
            let snapshot = retrySnapshot,
            compositionTracker.revision == snapshot.revision,
            compositionTracker.matches(
                documentContextBeforeInput: textDocumentProxy.documentContextBeforeInput
            )
        else {
            retrySnapshot = nil
            showCandidateMessage("入力内容が変更されたため再試行できません")
            return
        }
        startConversion(snapshot)
    }

    @objc private func undoTapped() {
        guard let undoRecord else {
            return
        }
        let expectedSuffix = String(undoRecord.replacement.suffix(32))
        guard
            !expectedSuffix.isEmpty,
            textDocumentProxy.documentContextBeforeInput?.hasSuffix(expectedSuffix) == true
        else {
            self.undoRecord = nil
            candidateSession = nil
            showCandidateMessage("入力内容が変更されたため元に戻せません")
            return
        }

        replaceHostText(undoRecord.replacement, with: undoRecord.original)
        compositionTracker.reset()
        compositionTracker.append(undoRecord.original)
        self.undoRecord = nil
        candidateSession = nil
        showCandidateMessage("原文を復元しました")
        refreshConvertButton()
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
            undoRecord = nil
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
        undoRecord = replacement == session.undoOriginal
            ? nil
            : UndoRecord(original: session.undoOriginal, replacement: replacement)
        showCandidates()
    }

    @objc private func returnTapped() {
        cancelConversionForEditing()
        textDocumentProxy.insertText("\n")
        compositionTracker.reset()
        refreshConvertButton()
    }
}
