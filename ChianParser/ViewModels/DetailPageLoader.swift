//
//  DetailPageLoader.swift
//  ChianParser
//
//  Sequential detail page loader backed by a persistent queue.
//  New apartments can be enqueued at any time — the loader starts automatically
//  if idle and continues until the queue is empty.
//

import Foundation
import WebKit
import Observation

@MainActor
@Observable
final class DetailPageLoader: NSObject {

    // MARK: - Public State

    var currentProgress: Int = 0
    var totalPages: Int = 0
    var isLoading: Bool = false
    var statusMessage: String = ""

    // MARK: - Dependencies

    private let detailParser: any DetailParserProtocol
    private var webView: WKWebView?

    // MARK: - Queue

    private var apartmentsQueue: [Apartment] = []
    private var currentApartment: Apartment?

    // Callback invoked whenever the queue drains to empty.
    // Set once by ContentViewModel after creation.
    var onBatchComplete: (() -> Void)?

    // MARK: - Init

    init(detailParser: any DetailParserProtocol) {
        self.detailParser = detailParser
        super.init()
        setupWebView()
    }

    private func setupWebView() {
        let config = WKWebViewConfiguration()
        webView = WKWebView(frame: .zero, configuration: config)
        webView?.navigationDelegate = self
        webView?.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
    }

    // MARK: - Queue Management

    /// Appends apartments to the processing queue, skipping already-parsed ones.
    /// Automatically starts processing if the loader is currently idle.
    func enqueue(_ apartments: [Apartment]) {
        let toAdd = apartments.filter { !$0.isDetailedParsed }
        guard !toAdd.isEmpty else { return }

        apartmentsQueue.append(contentsOf: toAdd)
        totalPages += toAdd.count

        guard !isLoading else {
            statusMessage = "⏳ В очереди: \(apartmentsQueue.count) квартир"
            return
        }

        isLoading = true
        statusMessage = "🔍 Авто-парсинг запущен: \(totalPages) квартир..."
        loadNextApartment()
    }

    /// Replaces the queue with a fresh list (used by the manual "Детальный парсинг" button).
    func loadDetailPages(for apartments: [Apartment]) {
        apartmentsQueue.removeAll()
        totalPages = 0
        currentProgress = 0
        enqueue(apartments)
    }

    /// Stops loading and clears the queue.
    func stopLoading() {
        apartmentsQueue.removeAll()
        isLoading = false
        webView?.stopLoading()
        statusMessage = "Остановлено пользователем"
    }

    // MARK: - Internal Processing

    private func loadNextApartment() {
        guard !apartmentsQueue.isEmpty else {
            isLoading = false
            statusMessage = "✅ Детальный парсинг завершён! Обработано: \(currentProgress)"
            onBatchComplete?()
            return
        }

        currentApartment = apartmentsQueue.removeFirst()
        guard let apartment = currentApartment,
              let url = URL(string: apartment.url) else {
            loadNextApartment()
            return
        }

        currentProgress += 1
        statusMessage = "Загрузка \(currentProgress)/\(totalPages): \(apartment.title)"
        print("🔍 Загрузка детальной страницы: \(url.absoluteString)")
        webView?.load(URLRequest(url: url))
    }

    @MainActor
    private func scheduleNextApartment() async {
        let delay = Double.random(in: 3.0...7.0)
        statusMessage = "⏳ Ожидание \(String(format: "%.1f", delay)) сек... (в очереди: \(apartmentsQueue.count))"
        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        loadNextApartment()
    }
}

// MARK: - WKNavigationDelegate

extension DetailPageLoader: WKNavigationDelegate {

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            // Wait for Next.js hydration before extracting data
            try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds

            let jsExtractJSON = """
            (function() {
                try {
                    if (window.__NEXT_DATA__) return JSON.stringify(window.__NEXT_DATA__);
                } catch(e) {}
                try {
                    if (window._cianConfig) return JSON.stringify(window._cianConfig);
                } catch(e) {}
                try {
                    var scripts = Array.from(document.querySelectorAll('script'));
                    for (var s of scripts) {
                        var t = s.textContent || '';
                        if (t.length > 500 && t.indexOf('"offerData"') >= 0) {
                            var start = t.indexOf('{');
                            if (start >= 0) return t.substring(start);
                        }
                    }
                } catch(e) {}
                return null;
            })();
            """

            webView.evaluateJavaScript(jsExtractJSON) { [weak self] result, _ in
                guard let self else { return }
                Task { @MainActor in
                    if let jsonString = result as? String,
                       !jsonString.isEmpty,
                       let apartment = self.currentApartment {
                        print("✅ JSON извлечён для: \(apartment.title)")
                        self.detailParser.parseJSON(jsonString: jsonString, apartment: apartment)
                        await self.scheduleNextApartment()
                    } else {
                        print("⚠️ JSON недоступен, извлекаю HTML fallback...")
                        webView.evaluateJavaScript("document.documentElement.outerHTML") { [weak self] htmlResult, htmlError in
                            guard let self else { return }
                            Task { @MainActor in
                                if let html = htmlResult as? String,
                                   let apartment = self.currentApartment {
                                    self.detailParser.parseHTML(html: html, apartment: apartment)
                                } else {
                                    print("❌ Ошибка извлечения HTML: \(htmlError?.localizedDescription ?? "unknown")")
                                }
                                await self.scheduleNextApartment()
                            }
                        }
                    }
                }
            }
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            print("❌ Ошибка загрузки: \(error.localizedDescription)")
            statusMessage = "Ошибка загрузки, пропускаю..."
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            loadNextApartment()
        }
    }
}
