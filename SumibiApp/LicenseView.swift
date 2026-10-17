import SwiftUI

enum AppLicenseDocument: String, CaseIterable, Identifiable {
    case sumibi, attribution, apache, legal, mozcAttribution, mozcLicense
    var id: Self { self }
    var title: String {
        switch self {
        case .sumibi: "Sumibi — MIT License"
        case .attribution: "SudachiDict — 出典・加工内容・著作権"
        case .apache: "Apache License 2.0"
        case .legal: "SudachiDict — LEGAL（UniDic・NEologdの表示を含む）"
        case .mozcAttribution: "Mozc — 記号辞書の出典・加工内容・著作権"
        case .mozcLicense: "Mozc — BSD 3-Clause License"
        }
    }
    var filename: String {
        switch self {
        case .sumibi: "LICENSE"
        case .attribution: "ATTRIBUTION.txt"
        case .apache: "LICENSE-2.0.txt"
        case .legal: "LEGAL"
        case .mozcAttribution: "ATTRIBUTION.txt"
        case .mozcLicense: "LICENSE"
        }
    }
    private var subdirectory: String? {
        switch self {
        case .sumibi: nil
        case .mozcAttribution, .mozcLicense: "ThirdParty/Mozc"
        default: "ThirdParty/SudachiDict"
        }
    }
    func contents(from bundle: Bundle = .main) -> String {
        guard let url = bundle.url(
            forResource: filename, withExtension: nil,
            subdirectory: subdirectory
        ), let text = try? String(contentsOf: url, encoding: .utf8) else {
            return "ライセンス文書を読み込めませんでした。"
        }
        return text
    }
}

struct LicenseView: View {
    var body: some View {
        List {
            Section {
                Text("Sumibiの独自コードはMITライセンスです。同梱するSudachiDict・Mozc由来の辞書データには、それぞれ別のライセンス条件が適用されます。")
                Text("SudachiDict Core 20260723から抽出した候補索引と、Mozcの記号データから作成した記号索引を使用しています。これらと中黒用の内蔵辞書は端末内で検索し、AIへ送信しません。")
                    .foregroundStyle(.secondary)
            }
            Section("ライセンス原文・第三者表示") {
                ForEach(AppLicenseDocument.allCases) { document in
                    NavigationLink(document.title) {
                        ScrollView {
                            Text(document.contents())
                                .font(.system(.footnote, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                        }
                        .navigationTitle(document.title)
                        .navigationBarTitleDisplayMode(.inline)
                    }
                }
            }
        }
        .navigationTitle("ライセンス")
        .navigationBarTitleDisplayMode(.inline)
    }

}
