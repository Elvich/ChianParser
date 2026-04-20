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
        config.userContentController = contentController
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        
        // Используем свежий User-Agent Safari
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
        
        init(_ parent: CianWebView) {
            self.parent = parent
        }
        
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            parent.onDataReceived("Status: Загрузка страницы... (\(webView.url?.absoluteString ?? "неизвестно"))")
            
            // Отменяем предыдущий таймаут
            loadTimeout?.cancel()
            
            // Создаем новый таймаут (60 секунд)
            let timeout = DispatchWorkItem { [weak self, weak webView] in
                guard let self = self, let webView = webView else { return }
                self.parent.onDataReceived("Error: Превышено время ожидания загрузки страницы (60 сек)")
                webView.stopLoading()
            }
            loadTimeout = timeout
            DispatchQueue.main.asyncAfter(deadline: .now() + 60, execute: timeout)
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Отменяем таймаут
            loadTimeout?.cancel()
            
            parent.onDataReceived("Status: Страница загружена, проверка капчи... (\(webView.url?.absoluteString ?? "неизвестно"))")
            
            // Проверяем наличие капчи
            checkForCaptcha(webView)
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
            let js = "document.documentElement.outerHTML"
            
            webView.evaluateJavaScript(js) { (result, error) in
                if let error = error {
                    self.parent.onDataReceived("Error: Ошибка JS: \(error.localizedDescription)")
                } else if let html = result as? String {
                    self.parent.onDataReceived(html)
                }
            }
        }
        
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {}
    }
}
