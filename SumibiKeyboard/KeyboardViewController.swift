import SumibiCore
import UIKit

final class KeyboardViewController: UIInputViewController {
    private lazy var sharedSettings = SharedSettingsStore()
    private var letterButtons: [UIButton] = []
    private var isShifted = false

    override func viewDidLoad() {
        super.viewDidLoad()
        _ = sharedSettings?.loadProviderConfiguration()
        configureKeyboard()
    }

    private func configureKeyboard() {
        view.backgroundColor = .systemGray5

        let keyboardStack = UIStackView(arrangedSubviews: [
            makeLetterRow(["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"]),
            makeLetterRow(["a", "s", "d", "f", "g", "h", "j", "k", "l"]),
            makeThirdRow(),
            makeBottomRow(),
        ])
        keyboardStack.axis = .vertical
        keyboardStack.spacing = 8
        keyboardStack.distribution = .fillEqually
        keyboardStack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(keyboardStack)
        NSLayoutConstraint.activate([
            keyboardStack.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            keyboardStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 6),
            keyboardStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -6),
            keyboardStack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8),
            view.heightAnchor.constraint(greaterThanOrEqualToConstant: 216),
        ])
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
        let returnButton = makeSpecialButton(
            title: "改行",
            accessibilityLabel: "改行",
            action: #selector(returnTapped)
        )

        let row = makeRow([nextKeyboardButton, spaceButton, returnButton])
        row.distribution = .fill
        spaceButton.widthAnchor.constraint(
            equalTo: nextKeyboardButton.widthAnchor,
            multiplier: 4
        ).isActive = true
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

    @objc private func letterTapped(_ sender: UIButton) {
        guard let letter = sender.accessibilityIdentifier else {
            return
        }
        textDocumentProxy.insertText(displayedLetter(letter))

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
        textDocumentProxy.deleteBackward()
    }

    @objc private func spaceTapped() {
        textDocumentProxy.insertText(" ")
    }

    @objc private func returnTapped() {
        textDocumentProxy.insertText("\n")
    }
}
