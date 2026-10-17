// Copyright (c) 2026 Kiyoka Nishiyama
// SPDX-License-Identifier: MIT
// Developer-only simulator harness. Assemble test access in a temporary source,
// leaving the production KeyboardViewController final and its members private.
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let output = URL(fileURLWithPath: "/private/tmp/sumibi-issue132-preview")
let app = output.appendingPathComponent("DictionaryPreview.app")
try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
func read(_ path: String) throws -> String {
    try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
}
let source = try read("SumibiKeyboard/KeyboardViewController.swift")
    .replacingOccurrences(of: "final class KeyboardViewController:", with: "class KeyboardViewController:")
    + "\n" + read("Tests/DictionaryKeyboardPreview.swift")
let generated = output.appendingPathComponent("Preview.swift")
try source.write(to: generated, atomically: true, encoding: .utf8)
let info: [String: Any] = [
    "CFBundleIdentifier": "org.sumibi.DictionaryPreview", "CFBundleName": "DictionaryPreview",
    "CFBundleExecutable": "DictionaryPreview", "CFBundlePackageType": "APPL",
    "CFBundleVersion": "1", "CFBundleShortVersionString": "1.0",
    "LSRequiresIPhoneOS": true, "UIDeviceFamily": [1], "UILaunchScreen": [:],
    "UIApplicationSceneManifest": ["UIApplicationSupportsMultipleScenes": false],
]
try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
    .write(to: app.appendingPathComponent("Info.plist"))
let products = URL(fileURLWithPath: CommandLine.arguments[1])
for item in try FileManager.default.contentsOfDirectory(at: products.appendingPathComponent("Sumibi.app/PlugIns/SumibiKeyboard.appex"),
                                                       includingPropertiesForKeys: nil) {
    if ["png", "tsv"].contains(item.pathExtension) || ["ConversionDictionary", "Sounds", "ThirdParty", "LICENSE"].contains(item.lastPathComponent) {
        let destination = app.appendingPathComponent(item.lastPathComponent)
        if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
        try FileManager.default.copyItem(at: item, to: destination)
    }
}
let sdkProcess = Process()
sdkProcess.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
sdkProcess.arguments = ["--sdk", "iphonesimulator", "--show-sdk-path"]
let pipe = Pipe()
sdkProcess.standardOutput = pipe
try sdkProcess.run()
let sdk = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    .trimmingCharacters(in: .whitespacesAndNewlines)
sdkProcess.waitUntilExit()
let compiler = Process()
compiler.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
compiler.arguments = ["swiftc", "-sdk", sdk, "-target", "arm64-apple-ios17.0-simulator",
    "-module-cache-path", output.appendingPathComponent("cache").path,
    "-F", products.path, "-I", products.path, "-framework", "SumibiCore",
    "-o", app.appendingPathComponent("DictionaryPreview").path, generated.path,
    root.appendingPathComponent("SumibiApp/LicenseView.swift").path]
    + ["KeyClickSound.swift", "DragonGameEffectView.swift", "SpaceLaserEffectView.swift",
       "CatHuntEffectView.swift", "FantasyGameEffectView.swift"].map {
        root.appendingPathComponent("SumibiKeyboard/" + $0).path
    }
try compiler.run()
compiler.waitUntilExit()
guard compiler.terminationStatus == 0 else { exit(compiler.terminationStatus) }
print(app.path)
