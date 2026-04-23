//
//  ContentViewModel.swift
//  ChianParser
//
//  ViewModel for ContentView. Owns all scraping, parsing, export, and data management logic.
//

import SwiftUI
import SwiftData

@MainActor
@Observable
final class ContentViewModel {

    // MARK: - Sort Order

    enum SortOrder: String, CaseIterable, Identifiable {
        case flipScore   = "FlipScore"
        case price       = "Цена"
        case viewsPerDay = "Просмотры/день"
        case dateAdded   = "Дата добавления"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .flipScore:   return "star.fill"
            case .price:       return "tag"
            case .viewsPerDay: return "eye"
            case .dateAdded:   return "calendar"
            }
        }
    }

    // MARK: - Dependencies

    private let modelContext: ModelContext
    private let searchParser: any SearchParserProtocol
    private let exportService: any ExportServiceProtocol
    private let flipAnalyzer: any FlipAnalyzerProtocol
    let detailLoader: DetailPageLoader

    // MARK: - State

    var urlString: String = "https://www.cian.ru/cat.php?deal_type=sale&electronic_trading=2&engine_version=2&flat_share=2&floornl=1&foot_min=7&is_first_floor=0&minfloorn=5&offer_type=flat&only_foot=2&region=1&sort=price_object_order"
    var isScraping: Bool = false
    var currentURL: URL?
    var log: String = "Готов к работе"
    var showCaptchaAlert: Bool = false
    var webViewHeight: CGFloat = 300
    var maxPages: Int = 1
    var currentPage: Int = 1
    var enablePagination: Bool = false
    var showClearDataConfirmation: Bool = false
    var sortOrder: SortOrder = .flipScore

    /// Statuses shown in the list. Defaults to everything except .ban.
    var activeStatusFilters: Set<ApartmentStatus> = ApartmentStatus.defaultVisible

    /// When enabled, newly found apartments are automatically queued for detail parsing.
    var autoDetailParsing: Bool = false

    // MARK: - Init

    init(
        modelContext: ModelContext,
        searchParser: any SearchParserProtocol,
        exportService: any ExportServiceProtocol,
        flipAnalyzer: any FlipAnalyzerProtocol,
        detailLoader: DetailPageLoader
    ) {
        self.modelContext = modelContext
        self.searchParser = searchParser
        self.exportService = exportService
        self.flipAnalyzer = flipAnalyzer
        self.detailLoader = detailLoader

        // Wire up the detail loader callback — called whenever its queue drains
        detailLoader.onBatchComplete = { [weak self] in
            self?.onDetailParsingComplete()
        }
    }

    // MARK: - Scoring

    /// Cached scored apartments — rebuilt only when data or sort order changes.
    private(set) var cachedScores: [(Apartment, FlipScoreResult)] = []

    private var refreshTask: Task<Void, Never>?

    /// Debounced entry point — coalesces rapid calls (e.g. during scraping) into a single rebuild.
    /// During active scraping the delay is longer since the user isn't inspecting the list.
    func scheduleRefresh(from apartments: [Apartment], thresholds: DemandThresholds) {
        refreshTask?.cancel()
        let delay: Duration = isScraping ? .seconds(1) : .milliseconds(250)
        refreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard let self, !Task.isCancelled else { return }
            self.refreshScores(from: apartments, thresholds: thresholds)
        }
    }

    /// Rebuild the score cache synchronously. Prefer scheduleRefresh for UI-triggered calls.
    func refreshScores(from apartments: [Apartment], thresholds: DemandThresholds) {
        // Build benchmark from ALL apartments (not just visible ones) for accurate pricing
        let benchmark = flipAnalyzer.buildBenchmark(from: apartments)

        // Check waiting conditions — may update apartment.status (MainActor-safe)
        checkWaitingConditions(apartments: apartments, benchmark: benchmark, thresholds: thresholds)

        // Score and filter
        let pairs = apartments.compactMap { apt -> (Apartment, FlipScoreResult)? in
            guard activeStatusFilters.contains(apt.status) else { return nil }
            return (apt, flipAnalyzer.analyze(apartment: apt, benchmark: benchmark, thresholds: thresholds))
        }

        cachedScores = pairs.sorted { lhs, rhs in
            switch sortOrder {
            case .flipScore:   return lhs.1.totalScore > rhs.1.totalScore
            case .price:       return lhs.0.price < rhs.0.price
            case .viewsPerDay: return (lhs.1.viewsPerDay ?? -1) > (rhs.1.viewsPerDay ?? -1)
            case .dateAdded:   return lhs.0.dateAdded > rhs.0.dateAdded
            }
        }
    }

    /// Toggle a status in the active filter set.
    func toggleStatusFilter(_ status: ApartmentStatus) {
        if activeStatusFilters.contains(status) {
            activeStatusFilters.remove(status)
        } else {
            activeStatusFilters.insert(status)
        }
    }

    // MARK: - Waiting Condition Checker

    /// Checks all apartments with .waiting status and moves them to .study if their condition is met.
    private func checkWaitingConditions(
        apartments: [Apartment],
        benchmark: BenchmarkContext,
        thresholds: DemandThresholds
    ) {
        for apt in apartments where apt.status == .waiting {
            guard let condition = apt.waitingCondition else { continue }
            let score = flipAnalyzer.analyze(apartment: apt, benchmark: benchmark, thresholds: thresholds)
            if condition.isMet(currentPrice: apt.price, currentScore: score.totalScore) {
                apt.status = .study
                apt.waitingConditionJSON = nil
                let note = condition.note.isEmpty ? condition.summary : condition.note
                if !apt.notes.isEmpty { apt.notes += "\n" }
                apt.notes += "[Авто] Условие выполнено: \(note)"
            }
        }
    }

    // MARK: - Scraping Control

    func startScraping() {
        currentPage = 1
        loadNextPage()
    }

    func stopScraping() {
        isScraping = false
        currentURL = nil
        currentPage = 1
    }

    private func loadNextPage() {
        let baseURL = URLBuilder.extractBaseURL(from: urlString)
        guard let url = URLBuilder.buildSearchURL(baseURL: baseURL, page: currentPage) else {
            log = "❌ Некорректный URL"
            return
        }

        currentURL = url
        isScraping = true

        if enablePagination {
            log = "📄 Загрузка страницы \(currentPage) из \(maxPages)... (\(url.absoluteString))"
        } else {
            log = "📄 Загрузка страницы... (\(url.absoluteString))"
        }

        print("🔗 Загрузка URL: \(url.absoluteString)")
    }

    private func onPageCompleted() {
        if enablePagination && currentPage < maxPages {
            currentPage += 1
            let delay = Double.random(in: 5.0...10.0)
            log = "⏳ Ожидание \(String(format: "%.1f", delay)) сек перед загрузкой страницы \(currentPage) из \(maxPages)..."

            Task {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                loadNextPage()
            }
        } else {
            isScraping = false
            currentURL = nil
            log = enablePagination ? "✅ Парсинг завершён! Обработано страниц: \(currentPage)" : log
        }
    }

    // MARK: - Data Processing

    func parseReceivedData(_ receivedString: String) {
        if receivedString.hasPrefix("Status: ") {
            log = receivedString.replacingOccurrences(of: "Status: ", with: "")
            return
        }

        if receivedString.hasPrefix("Error: ") {
            log = "❌ " + receivedString.replacingOccurrences(of: "Error: ", with: "")
            return
        }

        log = "🔍 Анализ данных (JSON → HTML fallback)..."

        let foundApartments = searchParser.extractData(from: receivedString)

        if !foundApartments.isEmpty {
            var newCount = 0
            var updatedCount = 0
            var newlyInserted: [Apartment] = []

            for apartment in foundApartments {
                let id = apartment.id
                let fetchDescriptor = FetchDescriptor<Apartment>(predicate: #Predicate { $0.id == id })

                if let existing = try? modelContext.fetch(fetchDescriptor).first {
                    if updateExistingApartment(existing, with: apartment) {
                        updatedCount += 1
                    }
                } else {
                    modelContext.insert(apartment)
                    newlyInserted.append(apartment)
                    newCount += 1
                }
            }

            // Auto-enqueue new apartments for detail parsing if enabled
            if autoDetailParsing && !newlyInserted.isEmpty {
                detailLoader.enqueue(newlyInserted)
            }

            log = "✅ Успешно! Новых: \(newCount) | Обновлено: \(updatedCount) | Всего на странице: \(foundApartments.count)"
            onPageCompleted()
        } else {
            log = "⚠️ Квартиры не найдены. Возможно, блокировка или капча."
        }
    }

    @discardableResult
    private func updateExistingApartment(_ existing: Apartment, with new: Apartment) -> Bool {
        var hasChanges = false

        if existing.price != new.price {
            existing.price = new.price
            existing.priceHistory.append(PricePoint(price: new.price, date: Date()))
            hasChanges = true
            print("💰 Цена изменилась для квартиры \(existing.id): \(existing.price) → \(new.price)")
        }

        if existing.title != new.title { existing.title = new.title; hasChanges = true }
        if existing.address != new.address { existing.address = new.address; hasChanges = true }
        if existing.area != new.area { existing.area = new.area; hasChanges = true }
        if existing.floor != new.floor { existing.floor = new.floor; hasChanges = true }
        if existing.totalFloors != new.totalFloors { existing.totalFloors = new.totalFloors; hasChanges = true }
        if existing.houseMaterial != new.houseMaterial { existing.houseMaterial = new.houseMaterial; hasChanges = true }
        if existing.metro != new.metro { existing.metro = new.metro; hasChanges = true }
        if existing.metroDistance != new.metroDistance { existing.metroDistance = new.metroDistance; hasChanges = true }
        if existing.metroTransportType != new.metroTransportType { existing.metroTransportType = new.metroTransportType; hasChanges = true }
        if existing.viewsToday != new.viewsToday { existing.viewsToday = new.viewsToday; hasChanges = true }
        if existing.viewsTotal != new.viewsTotal { existing.viewsTotal = new.viewsTotal; hasChanges = true }

        if hasChanges { existing.lastUpdate = Date() }

        return hasChanges
    }

    // MARK: - Captcha Handling

    func handleCaptchaDetected() {
        log = "⚠️ КАПЧА! Решите её в окне браузера и нажмите \"Продолжить\""
        showCaptchaAlert = true
        webViewHeight = 600
    }

    func dismissCaptcha() {
        showCaptchaAlert = false
        webViewHeight = 300
        log = "Продолжаю работу..."
    }

    // MARK: - Detail Parsing

    func startDetailParsing(apartments: [Apartment]) {
        log = "🔍 Запуск детального парсинга..."
        detailLoader.loadDetailPages(for: apartments)
    }

    private func onDetailParsingComplete() {
        log = "✅ Детальный парсинг завершён!"
        do {
            try modelContext.save()
            log = "💾 Данные сохранены"
            modelContext.processPendingChanges()
        } catch {
            log = "❌ Ошибка сохранения: \(error.localizedDescription)"
        }
    }

    // MARK: - Export

    enum ExportFormat { case csv, json }

    func exportData(format: ExportFormat, apartments: [Apartment]) {
        let fileURL: URL?
        switch format {
        case .csv:  fileURL = exportService.exportToCSV(apartments: apartments)
        case .json: fileURL = exportService.exportToJSON(apartments: apartments)
        }

        if let url = fileURL {
            log = "✅ Экспортировано в: \(url.lastPathComponent)"
            exportService.revealInFinder(url)
        } else {
            log = "❌ Ошибка экспорта"
        }
    }

    // MARK: - Data Management

    func clearAllData(apartments: [Apartment]) {
        let count = apartments.count
        for apartment in apartments {
            modelContext.delete(apartment)
        }
        do {
            try modelContext.save()
            log = "🗑️ Удалено квартир: \(count)"
        } catch {
            log = "❌ Ошибка при удалении: \(error.localizedDescription)"
        }
    }
}
