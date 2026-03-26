import Foundation

enum TranslationService {
    /// JavaScript that extracts text nodes and sends them to Swift for translation
    static var extractionJavaScript: String {
        """
        (function() {
            // Show loading indicator
            const loader = document.createElement('div');
            loader.id = 'scouter-translate-loader';
            loader.style.cssText = 'position:fixed;top:0;left:0;right:0;z-index:999999;background:#4A90D9;color:white;text-align:center;padding:12px;font-size:14px;font-family:system-ui;';
            loader.textContent = '翻訳中...';
            document.body.prepend(loader);

            function getTextNodes(node) {
                const nodes = [];
                const walker = document.createTreeWalker(node, NodeFilter.SHOW_TEXT, {
                    acceptNode: function(n) {
                        if (!n.textContent.trim()) return NodeFilter.FILTER_REJECT;
                        const tag = n.parentElement?.tagName;
                        if (['SCRIPT','STYLE','NOSCRIPT','CODE','PRE','SVG'].includes(tag)) return NodeFilter.FILTER_REJECT;
                        if (n.textContent.trim().length < 3) return NodeFilter.FILTER_REJECT;
                        return NodeFilter.FILTER_ACCEPT;
                    }
                });
                let current;
                while (current = walker.nextNode()) {
                    nodes.push(current);
                }
                return nodes;
            }

            window.__scouterTextNodes = getTextNodes(document.body);
            const texts = window.__scouterTextNodes.map(n => n.textContent.trim());

            // Send to Swift in batches of 40
            const batchSize = 40;
            const batches = [];
            for (let i = 0; i < texts.length; i += batchSize) {
                batches.push(texts.slice(i, i + batchSize));
            }
            window.webkit.messageHandlers.translateBatch.postMessage(JSON.stringify(batches));
        })();
        """
    }

    /// JavaScript that applies translated texts back to DOM nodes
    static func applyTranslationsJavaScript(batchIndex: Int, translations: [String]) -> String {
        let escaped = translations.map { t in
            t.replacingOccurrences(of: "\\", with: "\\\\")
             .replacingOccurrences(of: "'", with: "\\'")
             .replacingOccurrences(of: "\n", with: "\\n")
        }
        let jsArray = "['" + escaped.joined(separator: "','") + "']"
        return """
        (function() {
            const nodes = window.__scouterTextNodes;
            const translations = \(jsArray);
            const offset = \(batchIndex) * 40;
            for (let i = 0; i < translations.length; i++) {
                if (nodes[offset + i]) {
                    nodes[offset + i].textContent = translations[i];
                }
            }
        })();
        """
    }

    static var removeLoaderJavaScript: String {
        "document.getElementById('scouter-translate-loader')?.remove();"
    }
}
