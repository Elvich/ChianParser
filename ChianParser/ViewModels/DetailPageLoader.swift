//
//  DetailPageLoader.swift
//  ChianParser
//
//  Загрузчик детальных страниц объявлений
//

import Foundation
import WebKit
import Observation

/// Менеджер для последовательной загрузки детальных страниц объявлений
@MainActor
@Observable
final class DetailPageLoader: NSObject {
    var currentProgress: Int = 0
    var totalPages: Int = 0
    var isLoading: Bool = false
    var statusMessage: String = ""

    private let detailParser: any DetailParserProtocol
    private var webView: WKWebView?
    private var apartmentsQueue: [Apartment] = []
    private var onComplete: (() -> Void)?
    private var currentApartment: Apartment?

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
    
    /// Запускает детальный парсинг для списка квартир
    func loadDetailPages(for apartments: [Apartment], onComplete: @escaping () -> Void) {
        // Фильтруем только те квартиры, которые ещё не были детально распарсены
        self.apartmentsQueue = apartments.filter { !$0.isDetailedParsed }
        self.totalPages = apartmentsQueue.count
        self.currentProgress = 0
        self.onComplete = onComplete
        self.isLoading = true
        
        if apartmentsQueue.isEmpty {
            statusMessage = "Все квартиры уже обработаны"
            isLoading = false
            onComplete()
            return
        }
        
        statusMessage = "Начинаю детальный парсинг \(totalPages) квартир..."
        loadNextApartment()
    }
    
    private func loadNextApartment() {
        guard !apartmentsQueue.isEmpty else {
            // Завершили все квартиры
            isLoading = false
            statusMessage = "✅ Детальный парсинг завершён! Обработано: \(totalPages)"
            onComplete?()
            return
        }
        
        currentApartment = apartmentsQueue.removeFirst()
        guard let apartment = currentApartment,
              let url = URL(string: apartment.url) else {
            // Переходим к следующей
            loadNextApartment()
            return
        }
        
        currentProgress += 1
        statusMessage = "Загрузка \(currentProgress)/\(totalPages): \(apartment.title)"
        
        print("🔍 Загрузка детальной страницы: \(url.absoluteString)")
        webView?.load(URLRequest(url: url))
    }
    
    /// Останавливает процесс загрузки
    func stopLoading() {
        apartmentsQueue.removeAll()
        isLoading = false
        webView?.stopLoading()
        statusMessage = "Остановлено пользователем"
    }
}

// MARK: - WKNavigationDelegate

extension DetailPageLoader: WKNavigationDelegate {
    
    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            // Ждём чуть дольше — микрофронтенды Циан требуют времени на гидратацию
            try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 секунды
            
            // Пробуем несколько источников данных: __NEXT_DATA__, _cianConfig, inline script
            let jsExtractJSON = """
            (function() {
                try {
                    // Вариант А: Next.js SSR данные
                    if (window.__NEXT_DATA__) return JSON.stringify(window.__NEXT_DATA__);
                } catch(e) {}
                try {
                    // Вариант Б: Конфиг микрофронтенда
                    if (window._cianConfig) return JSON.stringify(window._cianConfig);
                } catch(e) {}
                try {
                    // Вариант В: Ищем script-теги содержащие offerData
                    var scripts = Array.from(document.querySelectorAll('script'));
                    for (var s of scripts) {
                        var t = s.textContent || '';
                        if (t.length > 500 && t.indexOf('"offerData"') >= 0) {
                            // Находим позицию первой { и возвращаем весь JSON
                            var start = t.indexOf('{');
                            if (start >= 0) return t.substring(start);
                        }
                    }
                } catch(e) {}
                return null;
            })();
            """
            
            webView.evaluateJavaScript(jsExtractJSON) { [weak self] result, error in
                guard let self = self else { return }
                
                Task { @MainActor in
                    if let jsonString = result as? String,
                       !jsonString.isEmpty,
                       let apartment = self.currentApartment {
                        // JSON успешно получен — парсим напрямую
                        print("✅ JSON извлечён напрямую для: \(apartment.title)")
                        self.detailParser.parseJSON(jsonString: jsonString, apartment: apartment)
                        await self.scheduleNextApartment()
                    } else {
                        // Fallback: забираем весь HTML
                        print("⚠️ JSON недоступен, извлекаю HTML fallback...")
                        webView.evaluateJavaScript("document.documentElement.outerHTML") { [weak self] htmlResult, htmlError in
                            guard let self = self else { return }
                            Task { @MainActor in
                                if let html = htmlResult as? String, let apartment = self.currentApartment {
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
    
    @MainActor
    private func scheduleNextApartment() async {
        let delay = Double.random(in: 3.0...7.0)
        statusMessage = "⏳ Ожидание \(String(format: "%.1f", delay)) сек..."
        let nanoseconds = UInt64(delay * 1_000_000_000)
        try? await Task.sleep(nanoseconds: nanoseconds)
        loadNextApartment()
    }

    
    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            print("❌ Ошибка загрузки: \(error.localizedDescription)")
            statusMessage = "Ошибка загрузки, пропускаю..."
            
            // Переходим к следующей
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 секунды
            loadNextApartment()
        }
    }
}
