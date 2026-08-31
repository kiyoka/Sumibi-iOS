import SumibiCore
import UIKit

private final class AudioFeedbackInputView: UIInputView, UIInputViewAudioFeedback {
    var enableInputClicksWhenVisible: Bool {
        true
    }
}

final class KeyboardViewController: UIInputViewController {
    private enum LayoutMetrics {
        static let keyHorizontalInset: CGFloat = 2
        static let keyHorizontalSpacing: CGFloat = 2
        static let portraitRowSpacing: CGFloat = 3
        static let landscapeRowSpacing: CGFloat = 2
        static let portraitSectionSpacing: CGFloat = 4
        static let landscapeSectionSpacing: CGFloat = 2
        static let portraitKeyRowsHeight: CGFloat = 296
        static let landscapeKeyRowsHeight: CGFloat = 176
        static let portraitBottomInset: CGFloat = 4
        static let landscapeBottomInset: CGFloat = 2
    }

    private enum KeyPressAnimationMetrics {
        static let normalLabelFontSize: CGFloat = 20
        static let pressedScale: CGFloat = 1.6
        static let pressDuration: TimeInterval = 0.06
        static let releaseApproachDuration: TimeInterval = 0.12
        static let releaseSettleDuration: TimeInterval = 0.06
        static let releaseSettleScale: CGFloat = 1.04
    }

    private enum KeyRepeatMetrics {
        static let initialDelay: TimeInterval = 0.5
        static let interval: TimeInterval = 0.075
    }

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

    private struct SelectedTextSnapshot {
        let source: String
        let contextBefore: String
        let contextAfter: String
        let documentIdentifier: UUID
    }

    private lazy var sharedSettings = SharedSettingsStore()
    private let hapticFeedbackGenerator = UIImpactFeedbackGenerator(style: .light)
    private let conversionCompletionFeedbackGenerator = UIImpactFeedbackGenerator(style: .medium)
    private let candidateStack = UIStackView()
    private var letterButtons: [UIButton] = []
    private var compositionTracker = CompositionTracker()
    private var pendingConversion: ConversionSnapshot?
    private var candidateSession: CandidateSession?
    private var undoRecord: UndoRecord?
    private var retrySnapshot: ConversionSnapshot?
    private var retrySelectedTextSnapshot: SelectedTextSnapshot?
    private var additionalCandidateErrorMessage: String?
    private var conversionTask: Task<Void, Never>?
    private var activeRequestID: UUID?
    private var convertButton: UIButton?
    private var normalSpaceWidthConstraint: NSLayoutConstraint?
    private var selectedSpaceWidthConstraint: NSLayoutConstraint?
    private var normalConvertWidthConstraint: NSLayoutConstraint?
    private var selectedConvertWidthConstraint: NSLayoutConstraint?
    private var isShowingSelectedTextControls = false
    private var convertButtonEmberLevel = -1
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
    private var pressedLabelOverlays: [ObjectIdentifier: UILabel] = [:]
    private var keyAnimationGenerations: [ObjectIdentifier: UInt] = [:]
    private var keyPressStartTimes: [ObjectIdentifier: CFTimeInterval] = [:]
    private var keyRepeatTimer: Timer?
    private weak var repeatingButton: UIButton?
    private var isCandidateSelectionAnimating = false
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
        retrySelectedTextSnapshot = nil
        additionalCandidateErrorMessage = nil
        refreshConvertButton()
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        refreshConvertButton()
    }

    override func selectionDidChange(_ textInput: UITextInput?) {
        super.selectionDidChange(textInput)
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
        keyRows.spacing = LayoutMetrics.portraitRowSpacing
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
        let keyRowsHeightConstraint = keyRows.heightAnchor.constraint(
            equalToConstant: LayoutMetrics.portraitKeyRowsHeight
        )
        let keyRowsBottomConstraint = keyRows.bottomAnchor.constraint(
            equalTo: view.bottomAnchor,
            constant: -LayoutMetrics.portraitBottomInset
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
            symbolPanel.leadingAnchor.constraint(
                equalTo: view.leadingAnchor,
                constant: LayoutMetrics.keyHorizontalInset
            ),
            symbolPanel.trailingAnchor.constraint(
                equalTo: view.trailingAnchor,
                constant: -LayoutMetrics.keyHorizontalInset
            ),
            symbolPanelBottomSpacingConstraint,
            keyRows.leadingAnchor.constraint(
                equalTo: view.leadingAnchor,
                constant: LayoutMetrics.keyHorizontalInset
            ),
            keyRows.trailingAnchor.constraint(
                equalTo: view.trailingAnchor,
                constant: -LayoutMetrics.keyHorizontalInset
            ),
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
        let sectionSpacing = isLandscape
            ? LayoutMetrics.landscapeSectionSpacing
            : LayoutMetrics.portraitSectionSpacing
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
        keyRowsHeightConstraint?.constant = isLandscape
            ? LayoutMetrics.landscapeKeyRowsHeight
            : LayoutMetrics.portraitKeyRowsHeight
        keyRowsBottomConstraint?.constant = isLandscape
            ? -LayoutMetrics.landscapeBottomInset
            : -LayoutMetrics.portraitBottomInset
        symbolPanelBottomSpacingConstraint?.constant = -sectionSpacing
        keyRowsStack?.spacing = isLandscape
            ? LayoutMetrics.landscapeRowSpacing
            : LayoutMetrics.portraitRowSpacing
        numberDividerCenterYConstraint?.constant = (keyRowsStack?.spacing ?? 0) / 2
        symbolPanel?.spacing = LayoutMetrics.keyHorizontalSpacing
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
            constant: LayoutMetrics.portraitRowSpacing / 2
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

        container.addSubview(iconView)
        container.addSubview(scrollView)
        scrollView.addSubview(candidateStack)
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 6),
            iconView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 28),
            iconView.heightAnchor.constraint(equalTo: iconView.widthAnchor),
            scrollView.topAnchor.constraint(equalTo: container.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 6),
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
        panel.spacing = LayoutMetrics.keyHorizontalSpacing
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
        configureDeleteButton(deleteButton)
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
        symbolButton.accessibilityHint = "タップで記号一覧を開きます"
        symbolButton.titleLabel?.numberOfLines = 1
        symbolButton.titleLabel?.adjustsFontSizeToFitWidth = true
        symbolButton.titleLabel?.minimumScaleFactor = 0.65
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

        let nextKeyboardButton = makeSpecialButton(
            title: "",
            accessibilityLabel: "次のキーボード",
            action: #selector(nextKeyboardTapped)
        )
        nextKeyboardButton.configuration?.image = UIImage(systemName: "globe")
        nextKeyboardButton.accessibilityHint = "次のキーボードへ切り替えます"
        let buttons = [symbolButton, nextKeyboardButton, spaceButton, convertButton, returnButton]

        let row = makeRow(buttons)
        row.distribution = .fill
        nextKeyboardButton.widthAnchor.constraint(
            equalTo: returnButton.widthAnchor
        ).isActive = true
        symbolButton.widthAnchor.constraint(
            equalTo: returnButton.widthAnchor,
            multiplier: 1.35
        ).isActive = true
        normalSpaceWidthConstraint = spaceButton.widthAnchor.constraint(
            equalTo: returnButton.widthAnchor,
            multiplier: 2.65
        )
        selectedSpaceWidthConstraint = spaceButton.widthAnchor.constraint(
            equalTo: returnButton.widthAnchor,
            multiplier: 2.20
        )
        normalConvertWidthConstraint = convertButton.widthAnchor.constraint(
            equalTo: returnButton.widthAnchor
        )
        selectedConvertWidthConstraint = convertButton.widthAnchor.constraint(
            equalTo: returnButton.widthAnchor,
            multiplier: 1.45
        )
        normalSpaceWidthConstraint?.isActive = true
        normalConvertWidthConstraint?.isActive = true
        refreshConvertButton()
        return row
    }

    private func makeRow(_ buttons: [UIButton]) -> UIStackView {
        let row = UIStackView(arrangedSubviews: buttons)
        row.axis = .horizontal
        row.spacing = LayoutMetrics.keyHorizontalSpacing
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
        gesture.minimumPressDuration = KeyRepeatMetrics.initialDelay
        gesture.allowableMovement = 20
        button.addGestureRecognizer(gesture)
    }

    private func configureDeleteButton(_ button: UIButton) {
        button.removeTarget(nil, action: nil, for: .allEvents)
        repeatableKeyKinds[ObjectIdentifier(button)] = .delete
        let gesture = UILongPressGestureRecognizer(
            target: self,
            action: #selector(deleteKeyPressed)
        )
        gesture.minimumPressDuration = 0
        gesture.allowableMovement = 20
        button.addGestureRecognizer(gesture)
    }

    @objc private func deleteKeyPressed(_ gesture: UILongPressGestureRecognizer) {
        guard let button = gesture.view as? UIButton else {
            stopKeyRepeat()
            return
        }
        switch gesture.state {
        case .began:
            stopKeyRepeat()
            repeatingButton = button
            animateKeyPress(button)
            playKeyClick()
            if sharedSettings?.loadHapticFeedbackEnabled() ?? true {
                hapticFeedbackGenerator.prepare()
                hapticFeedbackGenerator.impactOccurred(intensity: 0.7)
            }
            deleteTapped()

            let timer = Timer(
                timeInterval: KeyRepeatMetrics.initialDelay,
                target: self,
                selector: #selector(deleteRepeatDelayElapsed),
                userInfo: nil,
                repeats: false
            )
            keyRepeatTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        case .ended, .cancelled, .failed:
            stopKeyRepeat()
        default:
            break
        }
    }

    @objc private func deleteRepeatDelayElapsed() {
        guard let repeatingButton else {
            stopKeyRepeat()
            return
        }
        performRepeatAction(for: repeatingButton)
        let timer = Timer(
            timeInterval: KeyRepeatMetrics.interval,
            target: self,
            selector: #selector(keyRepeatTimerFired),
            userInfo: nil,
            repeats: true
        )
        keyRepeatTimer = timer
        RunLoop.main.add(timer, forMode: .common)
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
            timeInterval: KeyRepeatMetrics.interval,
            target: self,
            selector: #selector(keyRepeatTimerFired),
            userInfo: nil,
            repeats: true
        )
        keyRepeatTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopKeyRepeat() {
        let buttonToRelease = repeatingButton
        keyRepeatTimer?.invalidate()
        keyRepeatTimer = nil
        repeatingButton = nil
        if let buttonToRelease {
            animateKeyRelease(buttonToRelease)
        }
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
            animateKeyPress(button)
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
        button.titleLabel?.font = .systemFont(ofSize: KeyPressAnimationMetrics.normalLabelFontSize)
        button.clipsToBounds = false
        button.accessibilityLabel = accessibilityLabel
        button.addTarget(self, action: #selector(keyTouchDown), for: .touchDown)
        button.addTarget(self, action: #selector(keyTouchEntered), for: .touchDragEnter)
        button.addTarget(
            self,
            action: #selector(keyTouchEnded),
            for: [.touchUpInside, .touchUpOutside, .touchDragExit]
        )
        button.addTarget(self, action: #selector(keyTouchCancelled), for: .touchCancel)
        return button
    }

    @objc private func keyTouchDown(_ sender: UIButton) {
        animateKeyPress(sender)
        playKeyClick()
        if sharedSettings?.loadHapticFeedbackEnabled() ?? true {
            hapticFeedbackGenerator.prepare()
            hapticFeedbackGenerator.impactOccurred(intensity: 0.7)
        }
    }

    @objc private func keyTouchEntered(_ sender: UIButton) {
        animateKeyPress(sender)
    }

    @objc private func keyTouchEnded(_ sender: UIButton) {
        animateKeyRelease(sender)
    }

    @objc private func keyTouchCancelled(_ sender: UIButton) {
        guard repeatingButton !== sender else {
            return
        }
        animateKeyRelease(sender)
    }

    private func animateKeyPress(_ button: UIButton) {
        _ = advanceKeyAnimationGeneration(for: button)
        keyPressStartTimes[ObjectIdentifier(button)] = CACurrentMediaTime()
        button.layer.zPosition = 1
        let pressedLabel = showPressedLabel(for: button)
        let pressedTransform = keyTransform(
            for: button,
            scale: KeyPressAnimationMetrics.pressedScale
        )
        guard !UIAccessibility.isReduceMotionEnabled else {
            button.layer.removeAllAnimations()
            button.transform = pressedTransform
            pressedLabel.transform = .identity
            return
        }
        UIView.animate(
            withDuration: KeyPressAnimationMetrics.pressDuration,
            delay: 0,
            options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseOut]
        ) {
            button.transform = pressedTransform
            pressedLabel.transform = .identity
        }
    }

    private func animateKeyRelease(_ button: UIButton) {
        let animationGeneration = advanceKeyAnimationGeneration(for: button)
        let buttonIdentifier = ObjectIdentifier(button)
        let elapsed = CACurrentMediaTime() - (keyPressStartTimes[buttonIdentifier] ?? 0)
        let remainingPressDuration = max(0, KeyPressAnimationMetrics.pressDuration - elapsed)
        if remainingPressDuration > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + remainingPressDuration) { [weak self, weak button] in
                guard let self, let button,
                      self.keyAnimationGenerations[buttonIdentifier] == animationGeneration else {
                    return
                }
                self.performKeyRelease(
                    button,
                    animationGeneration: animationGeneration,
                    buttonIdentifier: buttonIdentifier
                )
            }
            return
        }
        performKeyRelease(
            button,
            animationGeneration: animationGeneration,
            buttonIdentifier: buttonIdentifier
        )
    }

    private func performKeyRelease(
        _ button: UIButton,
        animationGeneration: UInt,
        buttonIdentifier: ObjectIdentifier
    ) {
        keyPressStartTimes[buttonIdentifier] = nil
        let pressedLabel = pressedLabelOverlays[ObjectIdentifier(button)]
        let restingLabelTransform = pressedLabel.map { restingTransform(for: $0) } ?? .identity
        guard !UIAccessibility.isReduceMotionEnabled else {
            button.layer.removeAllAnimations()
            button.transform = .identity
            pressedLabel?.transform = restingLabelTransform
            hidePressedLabel(for: button)
            button.layer.zPosition = 0
            return
        }
        let settleTransform = keyTransform(
            for: button,
            scale: KeyPressAnimationMetrics.releaseSettleScale
        )
        let settleLabelTransform = restingLabelTransform.scaledBy(
            x: KeyPressAnimationMetrics.releaseSettleScale,
            y: KeyPressAnimationMetrics.releaseSettleScale
        )
        let releaseDuration = KeyPressAnimationMetrics.releaseApproachDuration
            + KeyPressAnimationMetrics.releaseSettleDuration
        let approachRatio = KeyPressAnimationMetrics.releaseApproachDuration / releaseDuration
        UIView.animateKeyframes(
            withDuration: releaseDuration,
            delay: 0,
            options: [.beginFromCurrentState, .allowUserInteraction, .calculationModeCubic]
        ) {
            UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: approachRatio) {
                button.transform = settleTransform
                pressedLabel?.transform = settleLabelTransform
            }
            UIView.addKeyframe(
                withRelativeStartTime: approachRatio,
                relativeDuration: 1 - approachRatio
            ) {
                button.transform = .identity
                pressedLabel?.transform = restingLabelTransform
            }
        } completion: { _ in
            guard self.keyAnimationGenerations[buttonIdentifier] == animationGeneration else {
                return
            }
            button.transform = .identity
            pressedLabel?.transform = restingLabelTransform
            self.hidePressedLabel(for: button)
            button.layer.zPosition = 0
        }
    }

    private func keyTransform(for button: UIButton, scale: CGFloat) -> CGAffineTransform {
        guard let superview = button.superview else {
            return CGAffineTransform(scaleX: scale, y: scale)
        }

        let centerInKeyboard = superview.convert(button.center, to: view)
        let expandedHalfWidth = button.bounds.width * scale / 2
        let leftOverflow = max(0, expandedHalfWidth - centerInKeyboard.x)
        let rightOverflow = max(0, centerInKeyboard.x + expandedHalfWidth - view.bounds.width)
        let horizontalOffset = leftOverflow - rightOverflow

        return CGAffineTransform(translationX: horizontalOffset, y: 0)
            .scaledBy(x: scale, y: scale)
    }

    @discardableResult
    private func advanceKeyAnimationGeneration(for button: UIButton) -> UInt {
        let identifier = ObjectIdentifier(button)
        let generation = (keyAnimationGenerations[identifier] ?? 0) &+ 1
        keyAnimationGenerations[identifier] = generation
        return generation
    }

    private func showPressedLabel(for button: UIButton) -> UILabel {
        let identifier = ObjectIdentifier(button)
        let label: UILabel
        if let existingLabel = pressedLabelOverlays[identifier] {
            label = existingLabel
        } else {
            label = UILabel()
            label.isUserInteractionEnabled = false
            label.textAlignment = .center
            label.textColor = .label
            label.adjustsFontSizeToFitWidth = false
            label.clipsToBounds = false
            label.alpha = 0
            label.layer.zPosition = 2
            button.addSubview(label)
            pressedLabelOverlays[identifier] = label
        }

        let title = button.configuration?.title ?? button.currentTitle ?? ""
        label.text = title
        let fontSize = pressedLabelFontSize(for: title)
        label.font = .systemFont(ofSize: fontSize)
        label.bounds = CGRect(
            x: 0,
            y: 0,
            width: max(button.bounds.width * 3, 180),
            height: max(button.bounds.height * 2, 100)
        )
        label.center = CGPoint(x: button.bounds.midX, y: button.bounds.midY)
        if label.alpha == 0 {
            label.transform = CGAffineTransform(
                scaleX: KeyPressAnimationMetrics.normalLabelFontSize / fontSize,
                y: KeyPressAnimationMetrics.normalLabelFontSize / fontSize
            )
            label.alpha = 1
        }
        button.titleLabel?.alpha = 0
        return label
    }

    private func hidePressedLabel(for button: UIButton) {
        pressedLabelOverlays[ObjectIdentifier(button)]?.alpha = 0
        button.titleLabel?.alpha = 1
    }

    private func restingTransform(for label: UILabel) -> CGAffineTransform {
        let fontSize = label.font.pointSize
        let scale = KeyPressAnimationMetrics.normalLabelFontSize / fontSize
        return CGAffineTransform(scaleX: scale, y: scale)
    }

    private func pressedLabelFontSize(for title: String) -> CGFloat {
        switch title.count {
        case 0...1:
            40
        case 2:
            34
        case 3...4:
            26
        default:
            22
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
        configureCandidateButtonSizing(button)
        button.accessibilityLabel = accessibilityLabel
        button.addTarget(self, action: action, for: .touchUpInside)
        candidateStack.addArrangedSubview(button)
    }

    private func configureCandidateButtonSizing(_ button: UIButton) {
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
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
            configureCandidateButtonSizing(button)
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
        retrySelectedTextSnapshot = nil
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
        let selectedText = textDocumentProxy.selectedText ?? ""
        let hasSelectedText = !selectedText.isEmpty
        let snapshot = compositionTracker.snapshot()
        let selectionIsValid = hasSelectedText && selectedText.count <= 512
        let isEnabled = (selectionIsValid || snapshot != nil) && activeRequestID == nil
        updateSelectedTextControls(isSelected: hasSelectedText)
        convertButton?.isEnabled = isEnabled
        convertButton?.alpha = isEnabled ? 1 : 0.45
        updateConvertButtonAppearance(
            hasSelectedText: hasSelectedText,
            compositionLength: isEnabled ? (snapshot?.source.count ?? 0) : 0
        )
        if hasSelectedText {
            convertButton?.accessibilityValue = selectionIsValid
                ? "選択中の\(selectedText.count)文字を変換"
                : "選択範囲は512文字以内にしてください"
        } else {
            convertButton?.accessibilityValue = isEnabled
                ? "変換対象\(snapshot?.source.count ?? 0)文字"
                : "変換対象なし"
        }
    }

    private func updateSelectedTextControls(isSelected: Bool) {
        guard isShowingSelectedTextControls != isSelected else {
            return
        }
        isShowingSelectedTextControls = isSelected
        normalSpaceWidthConstraint?.isActive = !isSelected
        normalConvertWidthConstraint?.isActive = !isSelected
        selectedSpaceWidthConstraint?.isActive = isSelected
        selectedConvertWidthConstraint?.isActive = isSelected
        convertButton?.configuration?.title = isSelected ? "範囲を変換" : "変換"
        convertButton?.accessibilityLabel = isSelected ? "範囲を変換" : "変換"
    }

    private func updateConvertButtonAppearance(
        hasSelectedText: Bool,
        compositionLength: Int
    ) {
        let emberLevel: Int
        if hasSelectedText {
            emberLevel = -2
        } else {
            switch compositionLength {
            case 1...2:
                emberLevel = 1
            case 3...5:
                emberLevel = 2
            case 6...11:
                emberLevel = 3
            case 12...:
                emberLevel = 4
            default:
                emberLevel = 0
            }
        }
        guard convertButtonEmberLevel != emberLevel else {
            return
        }
        convertButtonEmberLevel = emberLevel

        let backgroundColor: UIColor
        let foregroundColor: UIColor
        switch emberLevel {
        case -2:
            backgroundColor = .systemBlue
            foregroundColor = .white
        case 1:
            backgroundColor = UIColor(red: 0.76, green: 0.29, blue: 0.02, alpha: 1)
            foregroundColor = .black
        case 2:
            backgroundColor = UIColor(red: 0.87, green: 0.37, blue: 0.01, alpha: 1)
            foregroundColor = .black
        case 3:
            backgroundColor = UIColor(red: 0.95, green: 0.43, blue: 0.00, alpha: 1)
            foregroundColor = .black
        case 4:
            backgroundColor = .systemOrange
            foregroundColor = .black
        default:
            backgroundColor = .systemGray3
            foregroundColor = .label
        }

        convertButton?.configuration?.baseBackgroundColor = backgroundColor
        convertButton?.configuration?.baseForegroundColor = foregroundColor
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
        recordUsage(from: response)
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
        playConversionCompletionFeedback()
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

    private func recordUsage(from response: ConversionResponse) {
        guard let usage = response.usage else {
            return
        }
        let model = response.model
            ?? sharedSettings?.loadProviderConfiguration().model
            ?? ProviderConfiguration.defaultModel
        sharedSettings?.recordUsage(usage, model: model)
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
        guard sharedSettings?.hasAIDataSharingConsent(for: configuration.endpoint) == true else {
            showCandidateMessage("SumibiアプリでAIへのデータ送信に同意してください")
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
        symbolToggleButton?.configuration?.title = expanded ? "記号[閉]" : "記号"
        symbolToggleButton?.titleLabel?.font = .systemFont(ofSize: expanded ? 14 : 20)
        symbolToggleButton?.accessibilityLabel = expanded
            ? "通常キーボードに戻る"
            : "記号一覧"
        symbolToggleButton?.accessibilityValue = expanded ? "表示中" : "非表示"
        symbolToggleButton?.accessibilityHint = "タップで\(expanded ? "閉じます" : "開きます")"
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

    @objc private func nextKeyboardTapped() {
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
        if let selectedSnapshot = selectedTextSnapshot() {
            guard selectedSnapshot.source.count <= 512 else {
                showCandidateMessage("選択範囲は512文字以内にしてください")
                refreshConvertButton()
                return
            }
            startSelectedTextConversion(selectedSnapshot)
            return
        }

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

    private func selectedTextSnapshot() -> SelectedTextSnapshot? {
        guard let selectedText = textDocumentProxy.selectedText, !selectedText.isEmpty else {
            return nil
        }
        return SelectedTextSnapshot(
            source: selectedText,
            contextBefore: textDocumentProxy.documentContextBeforeInput ?? "",
            contextAfter: textDocumentProxy.documentContextAfterInput ?? "",
            documentIdentifier: textDocumentProxy.documentIdentifier
        )
    }

    private func selectedTextMatches(_ snapshot: SelectedTextSnapshot) -> Bool {
        textDocumentProxy.documentIdentifier == snapshot.documentIdentifier
            && textDocumentProxy.selectedText == snapshot.source
            && (textDocumentProxy.documentContextBeforeInput ?? "") == snapshot.contextBefore
            && (textDocumentProxy.documentContextAfterInput ?? "") == snapshot.contextAfter
    }

    private func startSelectedTextConversion(_ snapshot: SelectedTextSnapshot) {
        pendingConversion = nil
        retrySnapshot = nil
        retrySelectedTextSnapshot = nil
        additionalCandidateErrorMessage = nil
        undoRecord = nil
        guard let conversionClient = makeConversionClient() else {
            refreshConvertButton()
            return
        }
        let requestID = UUID()
        activeRequestID = requestID
        showConverting()
        refreshConvertButton()

        let request = ConversionRequest(
            source: snapshot.source,
            surroundingContext: snapshot.contextBefore,
            userDictionary: sharedSettings?.loadUserDictionary() ?? ""
        )
        conversionTask = Task { [weak self, conversionClient] in
            do {
                let response = try await conversionClient.convert(request)
                self?.finishSelectedTextConversion(
                    response,
                    snapshot: snapshot,
                    requestID: requestID
                )
            } catch is CancellationError {
                return
            } catch {
                self?.failSelectedTextConversion(
                    error,
                    snapshot: snapshot,
                    requestID: requestID
                )
            }
        }
    }

    private func finishSelectedTextConversion(
        _ response: ConversionResponse,
        snapshot: SelectedTextSnapshot,
        requestID: UUID
    ) {
        guard activeRequestID == requestID else {
            return
        }
        recordUsage(from: response)
        activeRequestID = nil
        conversionTask = nil

        let candidates = Array(
            response.candidates
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .reduce(into: [String]()) { unique, candidate in
                    if !unique.contains(candidate) {
                        unique.append(candidate)
                    }
                }
                .prefix(ConversionCandidateMode.primary.candidateCount)
        )
        guard let firstCandidate = candidates.first else {
            showCandidateMessage("変換候補がありません")
            refreshConvertButton()
            return
        }
        guard selectedTextMatches(snapshot) else {
            showCandidateMessage("選択範囲が変更されたため置換しません")
            refreshConvertButton()
            return
        }

        textDocumentProxy.insertText(firstCandidate)
        var options = candidates
        if !options.contains(snapshot.source) {
            options.append(snapshot.source)
        }
        candidateSession = CandidateSession(
            original: snapshot.source,
            undoOriginal: snapshot.source,
            surroundingContext: snapshot.contextBefore,
            options: options,
            current: firstCandidate,
            hasRequestedAdditionalCandidates: false
        )
        undoRecord = firstCandidate == snapshot.source
            ? nil
            : UndoRecord(original: snapshot.source, replacement: firstCandidate)
        retrySelectedTextSnapshot = nil
        compositionTracker.reset()
        showCandidates()
        refreshConvertButton()
        playConversionCompletionFeedback()
    }

    private func failSelectedTextConversion(
        _ error: Error,
        snapshot: SelectedTextSnapshot,
        requestID: UUID
    ) {
        guard activeRequestID == requestID else {
            return
        }
        activeRequestID = nil
        conversionTask = nil
        let presentation = errorPresentation(for: error)
        retrySelectedTextSnapshot = presentation.retryable ? snapshot : nil
        showError(presentation.message, retryable: presentation.retryable)
        refreshConvertButton()
    }

    private func startConversion(_ snapshot: ConversionSnapshot) {
        pendingConversion = snapshot
        retrySnapshot = nil
        retrySelectedTextSnapshot = nil
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
            surroundingContext: surroundingContext,
            userDictionary: sharedSettings?.loadUserDictionary() ?? ""
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
            currentConversion: session.current,
            userDictionary: sharedSettings?.loadUserDictionary() ?? ""
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
        recordUsage(from: response)
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
        playConversionCompletionFeedback()
    }

    private func playConversionCompletionFeedback() {
        guard sharedSettings?.loadConversionCompletionHapticEnabled() ?? true else {
            return
        }
        conversionCompletionFeedbackGenerator.prepare()
        conversionCompletionFeedbackGenerator.impactOccurred(intensity: 0.75)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            guard
                let self,
                self.sharedSettings?.loadConversionCompletionHapticEnabled() ?? true
            else {
                return
            }
            self.conversionCompletionFeedbackGenerator.prepare()
            self.conversionCompletionFeedbackGenerator.impactOccurred(intensity: 0.75)
        }
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
        retrySelectedTextSnapshot = nil
        showCandidateMessage("変換をキャンセルしました")
        refreshConvertButton()
    }

    @objc private func retryTapped() {
        if let snapshot = retrySelectedTextSnapshot {
            guard selectedTextMatches(snapshot) else {
                retrySelectedTextSnapshot = nil
                showCandidateMessage("選択範囲が変更されたため再試行できません")
                return
            }
            startSelectedTextConversion(snapshot)
            return
        }
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
        guard !isCandidateSelectionAnimating else {
            return
        }
        guard
            let session = candidateSession,
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

        let selectedIndex = sender.tag
        guard !UIAccessibility.isReduceMotionEnabled else {
            applyCandidateSelection(at: selectedIndex)
            return
        }

        isCandidateSelectionAnimating = true
        sender.isUserInteractionEnabled = false
        sender.layer.zPosition = 1
        UIView.animateKeyframes(
            withDuration: 0.28,
            delay: 0,
            options: [.allowUserInteraction, .calculationModeCubic]
        ) {
            UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 0.40) {
                sender.transform = CGAffineTransform(translationX: 0, y: -4)
                    .scaledBy(x: 1.22, y: 1.22)
            }
            UIView.addKeyframe(withRelativeStartTime: 0.40, relativeDuration: 0.25) {
                sender.transform = CGAffineTransform(translationX: 0, y: 1)
                    .scaledBy(x: 0.94, y: 0.94)
            }
            UIView.addKeyframe(withRelativeStartTime: 0.65, relativeDuration: 0.20) {
                sender.transform = CGAffineTransform(translationX: 0, y: -1)
                    .scaledBy(x: 1.04, y: 1.04)
            }
            UIView.addKeyframe(withRelativeStartTime: 0.85, relativeDuration: 0.15) {
                sender.transform = .identity
            }
        } completion: { _ in
            sender.transform = .identity
            sender.layer.zPosition = 0
            sender.isUserInteractionEnabled = true
            self.isCandidateSelectionAnimating = false
            self.applyCandidateSelection(at: selectedIndex)
        }
    }

    private func applyCandidateSelection(at index: Int) {
        guard
            var session = candidateSession,
            session.options.indices.contains(index)
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

        let replacement = session.options[index]
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
