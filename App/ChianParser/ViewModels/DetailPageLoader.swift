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
import UserNotifications

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
    private let powerManager: any PowerManagementServiceProtocol
    private(set) var webView: WKWebView?

    // MARK: - Queue

    private var apartmentsQueue: [Apartment] = []
    private var currentApartment: Apartment?

    // Callback invoked whenever the queue drains to empty.
    // Set once by ContentViewModel after creation.
    var onBatchComplete: (() -> Void)?

    // MARK: - Init

    init(detailParser: any DetailParserProtocol, powerManager: any PowerManagementServiceProtocol) {
        self.detailParser = detailParser
        self.powerManager = powerManager
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

        powerManager.startActivity(reason: "Parsing Cian apartment details")
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
            powerManager.startActivity(reason: "Parsing Cian apartment details")
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
        powerManager.endActivity()
    }

    /// Prioritizes a specific apartment, stopping the current load if necessary
    /// to load this one immediately without waiting in queue.
    func prioritize(_ apartment: Apartment) {
        guard !apartment.isDetailedParsed else { return }
        
        // Remove it from the queue if it's already there to avoid duplicates
        apartmentsQueue.removeAll(where: { $0.id == apartment.id })
        
        // Put it at the very front
        apartmentsQueue.insert(apartment, at: 0)
        
        if isLoading {
            // Preempt the current load
            webView?.stopLoading()
            
            // Re-enqueue the interrupted apartment so it isn't lost
            if let current = currentApartment, current.id != apartment.id {
                apartmentsQueue.insert(current, at: 1)
                // Adjust progress since we didn't finish this one
                if currentProgress > 0 { currentProgress -= 1 }
            }
            
            currentApartment = nil
            statusMessage = "⚡️ Приоритетная загрузка..."
            loadNextApartment()
        } else {
            totalPages += 1
            isLoading = true
            statusMessage = "⚡️ Приоритетная загрузка..."
            loadNextApartment()
        }
    }

    // MARK: - Internal Processing

    private func loadNextApartment() {
        guard !apartmentsQueue.isEmpty else {
            isLoading = false
            statusMessage = "✅ Детальный парсинг завершён! Обработано: \(currentProgress)"
            powerManager.endActivity()
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
                
                // Trigger a macOS system notification for Captcha detection
                let content = UNMutableNotificationContent()
                content.title = "⚠️ Cian Captcha Detected"
                content.body = "A captcha has been encountered during detailed parsing. Please open ChianParser and solve the captcha in the browser."
                content.sound = .default
                
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
                let request = UNNotificationRequest(
                    identifier: "CianCaptchaNotification-\(Date().timeIntervalSince1970)",
                    content: content,
                    trigger: trigger
                )
                
                do {
                    try await UNUserNotificationCenter.current().add(request)
                    print("✅ Captcha desktop notification sent successfully.")
                } catch {
                    print("❌ Failed to send captcha notification: \(error.localizedDescription)")
                }
                
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

            let jsWaitForHydration = """
            (async function() {
                return await new Promise((resolve) => {
                    if (window.__NEXT_DATA__) {
                        resolve(true);
                        return;
                    }
                    const startTime = Date.now();
                    const interval = setInterval(() => {
                        if (window.__NEXT_DATA__) {
                            clearInterval(interval);
                            resolve(true);
                        } else if (Date.now() - startTime > 5000) {
                            clearInterval(interval);
                            resolve(false);
                        }
                    }, 200);
                });
            })();
            """
            _ = try? await webView.evaluateJavaScript(jsWaitForHydration)

            let jsExtractJSON = """
            (async function() {
                // 1. Извлекаем offerId из URL
                var offerId = "";
                var urlMatch = window.location.href.match(/\\/(\\d+)\\/?/);
                if (urlMatch && urlMatch[1]) {
                    offerId = urlMatch[1];
                }

                // Helper to find a key recursively in an object
                function findVal(obj, key) {
                    if (!obj || typeof obj !== 'object') return null;
                    if (obj[key] !== undefined) return obj[key];
                    for (var k in obj) {
                        if (obj.hasOwnProperty(k)) {
                            var res = findVal(obj[k], key);
                            if (res !== null) return res;
                        }
                    }
                    return null;
                }

                // 2. Извлекаем publishedDate
                var publishedDate = "";
                
                var timeElem = document.querySelector('time[datetime]');
                if (timeElem) {
                    var dt = timeElem.getAttribute('datetime') || "";
                    if (dt) publishedDate = dt.slice(0, 10);
                }
                
                if (!publishedDate) {
                    try {
                        var rawDate = findVal(window.__NEXT_DATA__, 'publishedDate');
                        if (rawDate && typeof rawDate === 'string') {
                            publishedDate = rawDate.slice(0, 10);
                        } else {
                            var ts = findVal(window.__NEXT_DATA__, 'addedTimestamp');
                            if (ts) {
                                var dateObj = new Date(ts * 1000);
                                var y = dateObj.getFullYear();
                                var m = String(dateObj.getMonth() + 1).padStart(2, '0');
                                var d = String(dateObj.getDate()).padStart(2, '0');
                                publishedDate = y + '-' + m + '-' + d;
                            }
                        }
                    } catch(e) {}
                }
                
                if (!publishedDate) {
                    try {
                        var offerAddedElem = document.querySelector('[data-name="OfferAdded"]') || document.querySelector('[class*="added"]');
                        if (offerAddedElem) {
                            var text = offerAddedElem.textContent || "";
                            var match = text.match(/(\\d{2})\\.(\\d{2})\\.(\\d{4})/);
                            if (match) {
                                publishedDate = match[3] + '-' + match[2] + '-' + match[1];
                            } else {
                                var today = new Date();
                                if (text.indexOf('сегодня') !== -1) {
                                    publishedDate = today.getFullYear() + '-' + String(today.getMonth() + 1).padStart(2, '0') + '-' + String(today.getDate()).padStart(2, '0');
                                } else if (text.indexOf('вчера') !== -1) {
                                    var yesterday = new Date(today.getTime() - 86400000);
                                    publishedDate = yesterday.getFullYear() + '-' + String(yesterday.getMonth() + 1).padStart(2, '0') + '-' + String(yesterday.getDate()).padStart(2, '0');
                                }
                            }
                        }
                    } catch(e) {}
                }

                 // 3. Выполняем fetch детальной статистики
                 var viewsHistory = null;
                 if (offerId && publishedDate) {
                     try {
                         var statsUrl = 'https://api.cian.ru/offer-card/v1/get-offer-card-statistic/?offerCreationDate=' + encodeURIComponent(publishedDate) + '&offerId=' + offerId;
                         var response = await fetch(statsUrl, { credentials: 'include' });
                         if (response.ok) {
                             viewsHistory = await response.text();
                         } else {
                             viewsHistory = JSON.stringify({ error: "HTTP " + response.status });
                         }
                     } catch(e) {
                         viewsHistory = JSON.stringify({ error: e.message || String(e) });
                     }
                 }

                // Helper: extract views string from DOM text (e.g. "1507 просмотров, 7 за сегодня")
                function extractViewsFromDOM() {
                    try {
                        var allText = document.body ? document.body.innerText : '';
                        var totalMatch = allText.match(/(\\d[\\d\\s\\u00A0]*\\d|\\d)\\s*просмотр/i);
                        var todayMatch = allText.match(/(\\d+)\\s*за сегодня/i);
                        var noTodayMatch = allText.match(/нет\\s*за сегодня/i);
                        
                        var totalViews = totalMatch ? totalMatch[1].replace(/\\D/g,'') : null;
                        var todayViews = null;
                        if (todayMatch) {
                            todayViews = todayMatch[1];
                        } else if (noTodayMatch) {
                            todayViews = "0";
                        }
                        
                        if (totalViews !== null || todayViews !== null) {
                            return { totalViews: totalViews, todayViews: todayViews };
                        }
                    } catch(e) {}
                    return null;
                }

                // Helper: inject DOM views and viewsHistory into a parsed JSON object
                function injectDOMViewsAndHistory(jsonObj) {
                    var domViews = extractViewsFromDOM();
                    try {
                        var obj = JSON.parse(jsonObj);
                        
                        // Внедряем viewsHistory
                        if (viewsHistory !== null) {
                            obj.__viewsHistory = viewsHistory;
                        }
                        
                        if (domViews) {
                            var ps = obj && obj.props && obj.props.pageProps && obj.props.pageProps.initialState;
                            var offerData = ps && (ps.offerCard && ps.offerCard.offerData || ps.offer && ps.offer.offerData);
                            if (!offerData) {
                                // Store DOM views in a top-level sentinel for the Swift parser
                                if (domViews.totalViews !== null) obj.__domViewsTotal = parseInt(domViews.totalViews);
                                if (domViews.todayViews !== null) obj.__domViewsToday = parseInt(domViews.todayViews);
                            } else {
                                var offer = offerData.offer || offerData;
                                if (!offer.stats) offer.stats = {};
                                if (domViews.totalViews !== null) offer.stats.total = parseInt(domViews.totalViews);
                                if (domViews.todayViews !== null) offer.stats.daily = parseInt(domViews.todayViews);
                                
                                var totalStr = domViews.totalViews !== null ? domViews.totalViews + ' просмотров' : '';
                                var todayStr = domViews.todayViews !== null ? (domViews.todayViews === '0' ? 'нет за сегодня' : domViews.todayViews + ' за сегодня') : '';
                                if (totalStr && todayStr) {
                                    offer.stats.totalViewsFormattedString = totalStr + ' · ' + todayStr;
                                } else {
                                    offer.stats.totalViewsFormattedString = totalStr || todayStr;
                                }
                            }
                        }
                        return JSON.stringify(obj);
                    } catch(e) { 
                        try {
                            var fallbackObj = { original: jsonObj };
                            if (viewsHistory !== null) fallbackObj.__viewsHistory = viewsHistory;
                            if (domViews) {
                                if (domViews.totalViews !== null) fallbackObj.__domViewsTotal = parseInt(domViews.totalViews);
                                if (domViews.todayViews !== null) fallbackObj.__domViewsToday = parseInt(domViews.todayViews);
                            }
                            return JSON.stringify(fallbackObj);
                        } catch(e2) {
                            return jsonObj;
                        }
                    }
                }

                var rawResult = null;
                try {
                    if (window.__NEXT_DATA__) rawResult = JSON.stringify(window.__NEXT_DATA__);
                } catch(e) {}
                if (!rawResult) {
                    try {
                        if (window._cianConfig) rawResult = JSON.stringify(window._cianConfig);
                    } catch(e) {}
                }
                if (!rawResult) {
                    try {
                        var scripts = Array.from(document.querySelectorAll('script'));
                        for (var s of scripts) {
                            var t = s.textContent || '';
                            if (t.length > 500 && t.indexOf('"offerData"') >= 0) {
                                var start = t.indexOf('{');
                                if (start >= 0) {
                                    rawResult = t.substring(start);
                                    break;
                                }
                            }
                        }
                    } catch(e) {}
                }

                if (rawResult) {
                    return injectDOMViewsAndHistory(rawResult);
                }

                // Last resort: return only DOM views and history as minimal JSON
                var domViews = extractViewsFromDOM();
                var minimalObj = {};
                if (viewsHistory !== null) {
                    minimalObj.__viewsHistory = viewsHistory;
                }
                if (domViews) {
                    if (domViews.totalViews !== null) minimalObj.__domViewsTotal = parseInt(domViews.totalViews);
                    if (domViews.todayViews !== null) minimalObj.__domViewsToday = parseInt(domViews.todayViews);
                }
                return JSON.stringify(minimalObj);
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
