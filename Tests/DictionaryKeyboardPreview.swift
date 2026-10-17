// Appended to a temporary copy of KeyboardViewController.swift by the preview
// builder, so this test can exercise the real private candidate session.
// Never included in the production app/extension targets.
import UIKit
import SwiftUI

@MainActor
private final class DictionaryPreviewProxy: NSObject, UITextDocumentProxy {
    var before = ""
    var documentContextBeforeInput: String? { before }
    var documentContextAfterInput: String? { "" }
    var selectedText: String? { nil }
    var documentInputMode: UITextInputMode? { nil }
    let documentIdentifier = UUID()
    var hasText: Bool { !before.isEmpty }
    func insertText(_ text: String) { before += text }
    func deleteBackward() { if !before.isEmpty { before.removeLast() } }
    func adjustTextPosition(byCharacterOffset offset: Int) {}
    func setMarkedText(_ markedText: String, selectedRange: NSRange) {}
    func unmarkText() {}
}

@MainActor
private final class DictionaryPreviewKeyboard: KeyboardViewController {
    let proxy = DictionaryPreviewProxy()
    override var textDocumentProxy: any UITextDocumentProxy { proxy }
}

extension KeyboardViewController {
    fileprivate func validateDictionaryUI(proxy: DictionaryPreviewProxy, source: String) {
        let symbolTargets = ["hoshi": "★", "hosi": "★", "maru1": "①", "maruichi": "①",
                             "yajirushi": "→", "mugendai": "∞", "rokubousei": "✡"]
        let current = source == "hashi" ? "橋" : (symbolTargets[source] == nil ? "。" : "記号")
        proxy.before = "Meeting: " + current
        let request = UUID()
        activeRequestID = request
        candidateSession = CandidateSession(
            original: source, undoOriginal: source, surroundingContext: "Meeting: ",
            options: [current, source], current: current, hasRequestedAdditionalCandidates: true
        )
        finishAdditionalCandidates(ConversionResponse(
            candidates: source == "hashi" ? ["橋", "はし", "端"] : [current]
        ), requestID: request)
        view.layoutIfNeeded()
        let target = source == "hashi" ? "箸" : (symbolTargets[source] ?? "・")
        precondition(candidateSession!.dictionaryCandidates.contains(target))
        precondition(candidateSession!.options.filter { $0 == target }.count == 1)
        let candidates = candidateStack.arrangedSubviews.compactMap { $0 as? UIButton }.filter {
            ($0.accessibilityLabel ?? "").hasPrefix("変換候補、")
        }
        precondition(candidates.contains { $0.configuration?.subtitle == "LLM" })
        precondition(candidates.contains { $0.configuration?.subtitle == "辞書" })
        for button in candidates {
            precondition(button.intrinsicContentSize.height <= 40,
                         "Candidate must fit the existing bar: \(source) / \(button.configuration!.title ?? "") / \(button.intrinsicContentSize.height)")
            precondition(button.accessibilityLabel?.contains(button.configuration!.subtitle!) == true)
            let attributes = button.configuration!.subtitleTextAttributesTransformer!(AttributeContainer())
            precondition(attributes.font == .systemFont(ofSize: 14, weight: .medium),
                         "Source labels must use a readable, medium-weight font")
            precondition(attributes.foregroundColor == .secondaryLabel,
                         "Source labels must be visually secondary to candidate text")
        }
        let index = candidateSession!.options.firstIndex(of: target)!
        applyCandidateSelection(at: index)
        precondition(proxy.before == "Meeting: " + target, "Annotation must not be inserted")
        precondition(candidateSession!.dictionaryCandidates.contains(target))
        undoTapped()
        precondition(proxy.before == "Meeting: " + source, "Undo must preserve surrounding English")
        precondition(candidateSession == nil)
        // Stale-host protection still applies to dictionary candidates.
        activeRequestID = request
        candidateSession = CandidateSession(
            original: source, undoOriginal: source, surroundingContext: "",
            options: [current, source], current: current, hasRequestedAdditionalCandidates: true
        )
        proxy.before = current
        finishAdditionalCandidates(ConversionResponse(candidates: ["橋", "はし"]), requestID: request)
        let targetIndex = candidateSession!.options.firstIndex(of: target)!
        proxy.before = "changed host text"
        applyCandidateSelection(at: targetIndex)
        precondition(proxy.before == "changed host text" && candidateSession == nil)
    }

    fileprivate func showDictionaryPreview(proxy: DictionaryPreviewProxy) {
        let request = UUID()
        activeRequestID = request
        let symbols = CommandLine.arguments.contains("--symbols")
        let source = symbols ? "hoshi" : "hashi"
        let current = symbols ? "星" : "橋"
        proxy.before = current
        candidateSession = CandidateSession(
            original: source, undoOriginal: source, surroundingContext: "",
            options: [current, source], current: current, hasRequestedAdditionalCandidates: true
        )
        finishAdditionalCandidates(ConversionResponse(candidates: symbols ? ["星"] : ["橋", "はし", "端"]), requestID: request)
    }
}

@main
@MainActor
private final class DictionaryPreviewApp: UIResponder, UIApplicationDelegate {
    static func main() {
        UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, nil,
                          NSStringFromClass(DictionaryPreviewApp.self))
    }

    func application(_ application: UIApplication,
                     configurationForConnecting session: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: "Default Configuration", sessionRole: session.role)
        configuration.sceneClass = UIWindowScene.self
        configuration.delegateClass = DictionaryPreviewScene.self
        return configuration
    }
}

@MainActor
private final class DictionaryPreviewScene: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    var keyboard: DictionaryPreviewKeyboard?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
               options: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: scene)
        precondition(AppLicenseDocument.sumibi.contents().contains("MIT License"))
        precondition(AppLicenseDocument.apache.contents().contains("Redistribution"))
        precondition(AppLicenseDocument.legal.contents().contains("The UniDic Consortium"))
        precondition(AppLicenseDocument.legal.contents().contains("NEologd"))
        precondition(AppLicenseDocument.attribution.contents().contains("20260723"))
        precondition(AppLicenseDocument.mozcAttribution.contents().contains("0136c35782536cb43d710575c311cd4185982738"))
        precondition(AppLicenseDocument.mozcLicense.contents().contains("Copyright 2010-2018, Google Inc."))
        precondition(AppLicenseDocument.mozcLicense.contents().contains("Redistribution and use in source and binary forms"))
        for document in AppLicenseDocument.allCases {
            precondition(!document.contents().contains("読み込めませんでした"))
        }
        if CommandLine.arguments.contains("--licenses") {
            window.rootViewController = UIHostingController(rootView: NavigationStack { LicenseView() })
            window.makeKeyAndVisible()
            self.window = window
            return
        }
        let host = UIViewController()
        host.view.backgroundColor = .systemBackground
        let label = UILabel(frame: CGRect(x: 24, y: 100, width: 340, height: 100))
        label.text = "辞書候補の画面テスト\n実API通信なし"
        label.numberOfLines = 0
        label.textColor = .label
        host.view.addSubview(label)
        window.rootViewController = host
        window.makeKeyAndVisible()
        self.window = window
        DispatchQueue.main.async { self.runChecks(host) }
    }

    private func runChecks(_ host: UIViewController) {
        UIView.setAnimationsEnabled(false)
        for style in [UIUserInterfaceStyle.light, .dark] {
            for width: CGFloat in [320, 375, 390, 430] {
                let keyboard = installKeyboard(host, width: width, style: style)
                for source in ["hashi", "ten", "nakaguro", ".", "hoshi", "hosi", "maru1", "maruichi", "yajirushi", "mugendai", "rokubousei"] {
                    keyboard.validateDictionaryUI(proxy: keyboard.proxy, source: source)
                }
                keyboard.willMove(toParent: nil)
                keyboard.view.removeFromSuperview()
                keyboard.removeFromParent()
            }
        }
        let keyboard = installKeyboard(host, width: host.view.bounds.width,
                                       style: CommandLine.arguments.contains("--dark") ? .dark : .light)
        keyboard.showDictionaryPreview(proxy: keyboard.proxy)
        self.keyboard = keyboard
        let result = "PASS: real KeyboardViewController, 4 widths, Light/Dark, source labels, symbol selection, middle dot, Undo, stale-host protection, Mozc license documents\n"
        try! result.write(to: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DictionaryPreview-result.txt"), atomically: true, encoding: .utf8)
    }

    private func installKeyboard(_ host: UIViewController, width: CGFloat,
                                 style: UIUserInterfaceStyle) -> DictionaryPreviewKeyboard {
        host.overrideUserInterfaceStyle = style
        let keyboard = DictionaryPreviewKeyboard()
        host.addChild(keyboard)
        keyboard.loadViewIfNeeded()
        keyboard.overrideUserInterfaceStyle = style
        keyboard.view.frame = CGRect(x: 0, y: host.view.bounds.height - 370, width: width, height: 352)
        host.view.addSubview(keyboard.view)
        keyboard.didMove(toParent: host)
        keyboard.view.layoutIfNeeded()
        return keyboard
    }
}
