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
    var captchaDetected: Bool = false

    // MARK: - Dependencies

    private let detailParser: any DetailParserProtocol
    private(set) var webView: WKWebView?

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

    /// Replaces the pending queue with a fresh list.
    /// If the loader is already running, the current apartment finishes normally;
    /// only the waiting queue is replaced. Progress counters are updated accordingly.
    func loadDetailPages(for apartments: [Apartment]) {
        let toAdd = apartments.filter { !$0.isDetailedParsed }
        if isLoading {
            // Replace only the pending part of the queue, preserving current progress.
            apartmentsQueue = toAdd
            totalPages = currentProgress + toAdd.count
        } else {
            apartmentsQueue = toAdd
            totalPages = toAdd.count
            currentProgress = 0
            guard !toAdd.isEmpty else { return }
            isLoading = true
            statusMessage = "🔍 Детальный парсинг: \(totalPages) квартир..."
            loadNextApartment()
        }
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

    nonisolated func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        Task { @MainActor in
            // Reset captcha state on every new navigation (user may have solved it)
            captchaDetected = false
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            // Check for captcha before attempting any extraction
            let jsCaptchaCheck = """
            (function() {
                const hasCaptchaElement = document.querySelector('[data-name="Captcha"]') !== null;
                const hasCaptchaIframe  = document.querySelector('iframe[src*="captcha"]') !== null;
                const hasCaptchaTitle   = document.title.toLowerCase().includes('проверка');
                const hasRecaptcha      = document.querySelector('.g-recaptcha') !== null;
                return hasCaptchaElement || hasCaptchaIframe || hasCaptchaTitle || hasRecaptcha;
            })();
            """

            let captchaResult = (try? await webView.evaluateJavaScript(jsCaptchaCheck) as? Bool) ?? false

            if captchaResult {
                captchaDetected = true
                statusMessage = "⚠️ Капча! Решите её в браузере — парсинг продолжится автоматически"
                // Don't proceed — wait for next didFinish after user solves captcha
                return
            }

            captchaDetected = false

            // Check if the listing has been removed from Cian
            let jsRemovedCheck = """
            (function() {
                const is404        = document.title.includes('404');
                const isRemoved    = document.querySelector('[data-name="OfferRemoved"]') !== null;
                const isNotFound   = document.title.toLowerCase().includes('не найден')
                                  || document.title.toLowerCase().includes('снято');
                const isErrorPage  = document.querySelector('.error-page') !== null;
                return is404 || isRemoved || isNotFound || isErrorPage;
            })();
            """

            let removedResult = (try? await webView.evaluateJavaScript(jsRemovedCheck) as? Bool) ?? false

            if removedResult, let apartment = currentApartment {
                print("🗑️ Объявление снято с продажи: \(apartment.title)")
                apartment.status = .ban
                if apartment.notes.isEmpty {
                    apartment.notes = "Объявление снято с продажи (\(Date().formatted(date: .abbreviated, time: .omitted)))"
                } else {
                    apartment.notes += "\nОбъявление снято с продажи (\(Date().formatted(date: .abbreviated, time: .omitted)))"
                }
                await scheduleNextApartment()
                return
            }

            // Wait for Next.js hydration AND stats XHR to complete
            // Stats are loaded via a separate API call after SSR — need extra time
            try? await Task.sleep(nanoseconds: 4_000_000_000) // 4 seconds

            let jsExtractJSON = """
            (function() {
                // Helper: extract views string from DOM text (e.g. "1507 просмотров, 7 за сегодня")
                function extractViewsFromDOM() {
                    try {
                        var allText = document.body ? document.body.innerText : '';
                        var match = allText.match(/(\\d[\\d\\s\\u00A0]*\\d|\\d)\\s*просмотр[^,·\\n]*[,·]\\s*(\\d+)\\s*за сегодня/i);
                        if (match) return { totalViews: match[1].replace(/\\D/g,''), todayViews: match[2] };
                    } catch(e) {}
                    return null;
                }

                // Helper: inject DOM views into a parsed JSON object
                function injectDOMViews(jsonObj) {
                    var domViews = extractViewsFromDOM();
                    if (!domViews) return jsonObj;
                    try {
                        var obj = JSON.parse(jsonObj);
                        // Walk into offer stats and inject
                        var ps = obj && obj.props && obj.props.pageProps && obj.props.pageProps.initialState;
                        var offerData = ps && (ps.offerCard && ps.offerCard.offerData || ps.offer && ps.offer.offerData);
                        if (!offerData) {
                            // Store DOM views in a top-level sentinel for the Swift parser
                            obj.__domViewsTotal = parseInt(domViews.totalViews);
                            obj.__domViewsToday = parseInt(domViews.todayViews);
                            return JSON.stringify(obj);
                        }
                        var offer = offerData.offer || offerData;
                        if (!offer.stats) offer.stats = {};
                        if (!offer.stats.total) offer.stats.total = parseInt(domViews.totalViews);
                        if (!offer.stats.daily) offer.stats.daily = parseInt(domViews.todayViews);
                        offer.stats.totalViewsFormattedString = domViews.totalViews + ' просмотров · ' + domViews.todayViews + ' за сегодня';
                        return JSON.stringify(obj);
                    } catch(e) { return jsonObj; }
                }

                try {
                    if (window.__NEXT_DATA__) return injectDOMViews(JSON.stringify(window.__NEXT_DATA__));
                } catch(e) {}
                try {
                    if (window._cianConfig) return injectDOMViews(JSON.stringify(window._cianConfig));
                } catch(e) {}
                try {
                    var scripts = Array.from(document.querySelectorAll('script'));
                    for (var s of scripts) {
                        var t = s.textContent || '';
                        if (t.length > 500 && t.indexOf('"offerData"') >= 0) {
                            var start = t.indexOf('{');
                            if (start >= 0) return injectDOMViews(t.substring(start));
                        }
                    }
                } catch(e) {}

                // Last resort: return only DOM views as minimal JSON
                var domViews = extractViewsFromDOM();
                if (domViews) {
                    return JSON.stringify({
                        __domViewsTotal: parseInt(domViews.totalViews),
                        __domViewsToday: parseInt(domViews.todayViews)
                    });
                }
                return null;
            })();
            """

            let jsonResult = try? await webView.evaluateJavaScript(jsExtractJSON)
            if let jsonString = jsonResult as? String,
               !jsonString.isEmpty,
               let apartment = currentApartment {
                print("✅ JSON извлечён для: \(apartment.title)")
                detailParser.parseJSON(jsonString: jsonString, apartment: apartment)
                await scheduleNextApartment()
            } else {
                print("⚠️ JSON недоступен, извлекаю HTML fallback...")
                let htmlResult = try? await webView.evaluateJavaScript("document.documentElement.outerHTML")
                if let html = htmlResult as? String,
                   let apartment = currentApartment {
                    detailParser.parseHTML(html: html, apartment: apartment)
                } else {
                    print("❌ Ошибка извлечения HTML")
                }
                await scheduleNextApartment()
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
