import SwiftUI
import WebKit

struct ArticleWebView: UIViewRepresentable {
    let url: URL
    var needsTranslation: Bool = true

    private var loadURL: URL {
        guard needsTranslation else { return url }
        let encoded = url.absoluteString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? url.absoluteString
        return URL(string: "https://translate.google.com/translate?sl=auto&tl=ja&u=\(encoded)")!
    }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.load(URLRequest(url: loadURL))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
