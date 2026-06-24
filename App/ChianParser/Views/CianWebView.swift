//
//  CianWebView.swift
//  ChianParser
//

import SwiftUI
import WebKit

struct CianWebView: NSViewRepresentable {
    let url: URL
    let onDataReceived: (String) -> Void
    let onCaptchaDetected: () -> Void
    
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "cianHandler")

        // atDocumentStart: intercept XHR/fetch before any page JS runs.
        // Cian is likely a CSR app — data comes from API calls, not embedded __NEXT_DATA__.
        // We override fetch/XHR prototypes and store any response containing "bargainTerms".
        let interceptScript = WKUserScript(
            source: """
            (function() {
                window.__cianApiResponses = [];
                function maybeSave(text) {
                    if (text && text.length > 200 && text.includes('"bargainTerms"')) {
                        window.__cianApiResponses.push(text);
                    }
                }
                var _fetch = window.fetch;
                window.fetch = function() {
                    var p = _fetch.apply(this, arguments);
                    p.then(function(r) {
                        r.clone().text().then(maybeSave).catch(function(){});
                    }).catch(function(){});
                    return p;
                };
                var _send = XMLHttpRequest.prototype.send;
                XMLHttpRequest.prototype.send = function() {
                    var xhr = this;
                    xhr.addEventListener('load', function() { maybeSave(xhr.responseText); });
                    _send.apply(this, arguments);
                };
            })();
            """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        contentController.addUserScript(interceptScript)

        // atDocumentEnd: capture __NEXT_DATA__ via PUSH (fallback for SSR pages).
        let captureScript = WKUserScript(
            source: """
            (function() {
                var data = null;
                var el = document.getElementById('__NEXT_DATA__');
                if (el && el.textContent.trim().length > 10) {
                    data = el.textContent;
                } else if (window.__NEXT_DATA__) {
                    try { data = JSON.stringify(window.__NEXT_DATA__); } catch(e) {}
                }
                if (data) {
                    window.__cianCaptured = data;
                    window.webkit.messageHandlers.cianHandler.postMessage('__NEXT_DATA__:' + data);
                }
            })();
            """,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        contentController.addUserScript(captureScript)
        config.userContentController = contentController

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator

        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

        webView.load(URLRequest(url: url))

        return webView
    }
    
    func updateNSView(_ nsView: WKWebView, context: Context) {
        // Проверяем, изменился ли URL - если да, загружаем новую страницу
        if nsView.url != url {
            nsView.load(URLRequest(url: url))
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: CianWebView
        var loadTimeout: DispatchWorkItem?
        /// True when UserScript already pushed __NEXT_DATA__ via message handler.
        /// In this case didFinish only needs to check for captcha, not extract data again.
        var dataReceivedViaScript = false

        init(_ parent: CianWebView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            dataReceivedViaScript = false  // Reset for new page load
            parent.onDataReceived("Status: Загрузка страницы... (\(webView.url?.absoluteString ?? "неизвестно"))")

            loadTimeout?.cancel()
            let timeout = DispatchWorkItem { [weak self, weak webView] in
                guard let self = self, let webView = webView else { return }
                self.parent.onDataReceived("Error: Превышено время ожидания загрузки страницы (60 сек)")
                webView.stopLoading()
            }
            loadTimeout = timeout
            DispatchQueue.main.asyncAfter(deadline: .now() + 60, execute: timeout)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            loadTimeout?.cancel()
            parent.onDataReceived("Status: Страница загружена, проверка капчи... (\(webView.url?.absoluteString ?? "неизвестно"))")

            if dataReceivedViaScript {
                // Data already delivered via UserScript — only check for captcha
                checkForCaptchaOnly(webView)
            } else {
                // UserScript didn't fire (anti-bot page, empty HTML, etc.) — use full pipeline
                checkForCaptcha(webView)
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            parent.onDataReceived("Error: Ошибка сети: \(error.localizedDescription)")
        }
        
        private func checkForCaptcha(_ webView: WKWebView) {
            let jsCheckCaptcha = """
            (function() {
                // Проверяем разные варианты капчи
                const hasCaptchaElement = document.querySelector('[data-name="Captcha"]') !== null;
                const hasCaptchaIframe = document.querySelector('iframe[src*="captcha"]') !== null;
                const hasCaptchaInTitle = document.title.toLowerCase().includes('проверка');
                const hasRecaptcha = document.querySelector('.g-recaptcha') !== null;
                
                return hasCaptchaElement || hasCaptchaIframe || hasCaptchaInTitle || hasRecaptcha;
            })();
            """
            
            webView.evaluateJavaScript(jsCheckCaptcha) { result, error in
                if let hasCaptcha = result as? Bool, hasCaptcha {
                    // Капча обнаружена!
                    self.parent.onDataReceived("Status: ⚠️ Обнаружена капча!")
                    self.parent.onCaptchaDetected()
                } else {
                    // Капчи нет → продолжаем парсинг
                    self.parent.onDataReceived("Status: Капча не обнаружена, извлекаю данные...")
                    self.extractDataAfterDelay(from: webView)
                }
            }
        }
        
        private func extractDataAfterDelay(from webView: WKWebView) {
            // Случайная задержка для имитации человека (3-6 секунд)
            let randomDelay = Double.random(in: 3.0...6.0)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + randomDelay) {
                self.extractData(from: webView)
            }
        }
        
        private func extractData(from webView: WKWebView) {
            // Check window.__cianCaptured first — it was saved at document-end before React
            // hydration could remove the script tag. If not present, try direct DOM access as
            // a last resort before falling back to full outerHTML.
            let jsExtract = """
            (function() {
                // 1. XHR/fetch intercepted API response (best for CSR apps like Cian)
                if (window.__cianApiResponses && window.__cianApiResponses.length > 0) {
                    return '__API__:' + window.__cianApiResponses[0];
                }
                // 2. Pre-captured __NEXT_DATA__ at document-end (SSR fallback)
                if (window.__cianCaptured && window.__cianCaptured.length > 10) {
                    return '__NEXT_DATA__:' + window.__cianCaptured;
                }
                // 3. window.__NEXT_DATA__ object persists even after DOM element cleared
                if (window.__NEXT_DATA__) {
                    try { return '__NEXT_DATA__:' + JSON.stringify(window.__NEXT_DATA__); } catch(e) {}
                }
                // 4. DOM element last chance
                var el = document.getElementById('__NEXT_DATA__');
                if (el && el.textContent.trim().length > 10) {
                    return '__NEXT_DATA__:' + el.textContent;
                }
                return null;
            })()
            """
            webView.evaluateJavaScript(jsExtract) { [weak self] result, error in
                guard let self else { return }
                if let tagged = result as? String, !tagged.isEmpty {
                    if tagged.hasPrefix("__API__:") {
                        print("✅ Данные получены через XHR/fetch перехват")
                    } else {
                        print("✅ Данные получены через __NEXT_DATA__")
                    }
                    self.parent.onDataReceived(tagged)
                } else {
                    print("⚠️ Ни API-ответ, ни __NEXT_DATA__ не найдены, пробуем outerHTML...")
                    self.extractFullHTML(from: webView)
                }
            }
        }

        private func extractFullHTML(from webView: WKWebView) {
            webView.evaluateJavaScript("document.documentElement.outerHTML") { [weak self] result, error in
                guard let self else { return }
                if let error = error {
                    self.parent.onDataReceived("Error: Ошибка JS: \(error.localizedDescription)")
                } else if let html = result as? String {
                    self.parent.onDataReceived(html)
                } else {
                    self.parent.onDataReceived("Error: JS вернул пустой результат")
                }
            }
        }
        
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? String else { return }
            if body.hasPrefix("__NEXT_DATA__:") || body.hasPrefix("__API__:") {
                dataReceivedViaScript = true
                print("✅ Данные получены через UserScript PUSH: \(body.prefix(20))...")
                parent.onDataReceived(body)
            }
        }

        /// Called when data was already delivered via UserScript — only need to check captcha.
        private func checkForCaptchaOnly(_ webView: WKWebView) {
            let jsCheckCaptcha = """
            (function() {
                const hasCaptchaElement = document.querySelector('[data-name="Captcha"]') !== null;
                const hasCaptchaIframe  = document.querySelector('iframe[src*="captcha"]') !== null;
                const hasCaptchaInTitle = document.title.toLowerCase().includes('проверка');
                const hasRecaptcha      = document.querySelector('.g-recaptcha') !== null;
                return hasCaptchaElement || hasCaptchaIframe || hasCaptchaInTitle || hasRecaptcha;
            })();
            """
            webView.evaluateJavaScript(jsCheckCaptcha) { result, _ in
                if let hasCaptcha = result as? Bool, hasCaptcha {
                    self.parent.onCaptchaDetected()
                }
                // If no captcha (or JS failed): data already delivered, nothing more to do.
            }
        }
    }
}
