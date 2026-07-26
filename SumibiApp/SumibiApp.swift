import SumibiCore
import SwiftUI

@main
struct SumibiApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

private struct ContentView: View {
    private let isSharedSettingsAvailable = SharedSettingsStore() != nil

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "keyboard")
                .font(.system(size: 48))
                .foregroundStyle(.tint)

            Text("Sumibi")
                .font(.largeTitle.bold())

            Text("日本語入力キーボードの準備を進めています。")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Label(
                isSharedSettingsAvailable ? "共有設定を利用できます" : "共有設定を利用できません",
                systemImage: isSharedSettingsAvailable ? "checkmark.circle" : "exclamationmark.triangle"
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .padding()
    }
}
