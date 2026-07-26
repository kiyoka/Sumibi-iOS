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
        }
        .padding()
    }
}

