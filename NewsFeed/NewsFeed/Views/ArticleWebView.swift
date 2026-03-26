import SwiftUI
import WebKit
import Translation

struct ArticleWebView: View {
    let url: URL
    @State private var translationConfig: TranslationSession.Configuration?
    @StateObject private var bridge = WebViewBridge()

    var body: some View {
        InnerWebView(url: url, bridge: bridge)
            .translationTask(translationConfig) { session in
                await bridge.performTranslation(with: session)
            }
            .onChange(of: bridge.readyToTranslate) { _, ready in
                if ready {
                    translationConfig = .init(
                        source: Locale.Language(identifier: "en"),
                        target: Locale.Language(identifier: "ja")
                    )
                }
            }
    }
}

@MainActor
class WebViewBridge: ObservableObject {
    @Published var readyToTranslate = false
    var pendingBatches: [[String]] = []
    weak var webView: WKWebView?

    func performTranslation(with session: TranslationSession) async {
        for (batchIndex, batch) in pendingBatches.enumerated() {
            do {
                let requests = batch.enumerated().map { idx, text in
                    TranslationSession.Request(sourceText: text, clientIdentifier: "\(idx)")
                }
                let responses = try await session.translations(from: requests)
                // Sort by clientIdentifier to maintain order
                let sorted = responses.sorted {
                    Int($0.clientIdentifier ?? "0") ?? 0 < Int($1.clientIdentifier ?? "0") ?? 0
                }
                let translated = sorted.map(\.targetText)

                let applyJS = TranslationService.applyTranslationsJavaScript(
                    batchIndex: batchIndex,
                    translations: translated
                )
                webView?.evaluateJavaScript(applyJS) { _, _ in }
            } catch {
                print("Translation error: \(error)")
            }
        }
        webView?.evaluateJavaScript(TranslationService.removeLoaderJavaScript) { _, _ in }
    }
}

struct InnerWebView: UIViewRepresentable {
    let url: URL
    let bridge: WebViewBridge

    func makeCoordinator() -> Coordinator {
        Coordinator(bridge: bridge)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let ucc = WKUserContentController()
        ucc.add(context.coordinator, name: "translateBatch")
        config.userContentController = ucc

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        bridge.webView = webView
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "translateBatch")
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let bridge: WebViewBridge

        init(bridge: WebViewBridge) {
            self.bridge = bridge
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript(TranslationService.extractionJavaScript) { _, error in
                if let error = error {
                    print("Extraction JS error: \(error)")
                }
            }
        }

        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard message.name == "translateBatch",
                  let jsonString = message.body as? String,
                  let data = jsonString.data(using: .utf8),
                  let batches = try? JSONDecoder().decode([[String]].self, from: data) else {
                return
            }

            Task { @MainActor in
                bridge.pendingBatches = batches
                bridge.readyToTranslate = true
            }
        }
    }
}
