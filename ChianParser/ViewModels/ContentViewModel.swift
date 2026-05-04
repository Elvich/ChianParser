//
//  ContentViewModel.swift
//  ChianParser
//
//  ViewModel for ContentView. Owns all scraping, parsing, export, and data management logic.
//

import SwiftUI
import SwiftData

// MARK: - Parsing Mode

enum ParsingMode: String, CaseIterable {
    case parallel   = "parallel"
    case sequential = "sequential"

    var label: String {
        switch self {
        case .parallel:   return "Параллельный"
        case .sequential: return "Последовательный"
        }
    }

    var description: String {
        switch self {
        case .parallel:
            return "Сначала парсит все ссылки, затем детально разбирает найденные квартиры."
        case .sequential:
            return "Парсит одну ссылку, полностью разбирает её квартиры, затем переходит к следующей."
        }
    }
}

@MainActor
@Observable
final class ContentViewModel {

    // MARK: - Sort Order

    enum SortOrder: String, CaseIterable, Identifiable {
        case flipScore   = "FlipScore"
        case price       = "Цена"
        case area        = "Площадь"
        case viewsPerDay = "Просмотры/день"
        case dateAdded   = "Дата добавления"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .flipScore:   return "star.fill"
            case .price:       return "tag"
            case .area:        return "square"
            case .viewsPerDay: return "eye"
            case .dateAdded:   return "calendar"
            }
        }

        /// Natural sort direction: true = ascending is natural (e.g. cheap first, small first)
        var naturalAscending: Bool {
            switch self {
            case .price, .area: return true
            default:            return false
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

    var isScraping: Bool = false
    var currentURL: URL?
    /// Ordered list of search URLs loaded at scraping start. Cycled infinitely.
    private(set) var searchURLs: [String] = []
    /// Index into searchURLs for the URL currently being fetched.
    private(set) var currentURLIndex: Int = 0
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

    /// When enabled, re-checks stale apartments for removal/price changes when the detail queue drains.
    var autoCheckActivity: Bool = false

    /// Apartments not seen in search for this many days are considered stale.
    var staleDaysThreshold: Int = 3

    /// Prevents immediate re-loop: true while a stale-check batch is in progress.
    private var staleCheckInProgress = false

    /// In sequential mode: set after a search page is processed and detail parsing started.
    /// onDetailParsingComplete will call onPageCompleted() when this is true.
    private var pendingPageCompletion = false

    /// Current parsing mode — synced from AppStorage via ContentView.
    var parsingMode: ParsingMode = .parallel

    /// When true, auto-detected auction listings are shown. Off by default.
    var showAuctions: Bool = false

    /// When true, listings with deposit-paid phrases in description are shown. Off by default.
    var showDeposits: Bool = false

    /// Окружа currently shown. Empty = show all.
    var activeOkrugFilters: Set<String> = []

    /// Sorted list of all okrugs present in the current apartment dataset.
    private(set) var availableOkrugs: [String] = []

    /// Room count buckets currently shown. Empty = show all.
    /// 0 = Студия, 1 = 1К, 2 = 2К, 3 = 3К, 4 = 4К+ (≥4 комнат).
    var activeRoomFilters: Set<Int> = []

    /// Sorted list of room count buckets present in the dataset (0…4).
    private(set) var availableRoomCounts: [Int] = []

    /// Sort direction: true = ascending, false = descending.
    var sortAscending: Bool = false

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
    func scheduleRefresh(from apartments: [Apartment], thresholds: DemandThresholds, metroBanlist: Set<String>) {
        refreshTask?.cancel()
        let delay: Duration = isScraping ? .seconds(1) : .milliseconds(250)
        refreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard let self, !Task.isCancelled else { return }
            self.refreshScores(from: apartments, thresholds: thresholds, metroBanlist: metroBanlist)
        }
    }

    /// Rebuild the score cache synchronously. Prefer scheduleRefresh for UI-triggered calls.
    func refreshScores(from apartments: [Apartment], thresholds: DemandThresholds, metroBanlist: Set<String>) {
        // Build benchmark from ALL apartments (not just visible ones) for accurate pricing
        let benchmark = flipAnalyzer.buildBenchmark(from: apartments)

        // Check waiting conditions — may update apartment.status (MainActor-safe)
        checkWaitingConditions(apartments: apartments, benchmark: benchmark, thresholds: thresholds)

        // Compute available okrugs — exclude "Москва" (it's a fallback, not a real filter target)
        availableOkrugs = Array(Set(apartments.compactMap { okrug -> String? in
            guard let o = okrug.okrug, o != "Москва" else { return nil }
            return o
        })).sorted()

        // Compute available room count buckets (0=Studio, 1-3=rooms, 4=4+)
        availableRoomCounts = Array(Set(apartments.compactMap { apt -> Int? in
            guard let r = apt.roomsCount else { return nil }
            return min(r, 4)
        })).sorted()

        // Score and filter
        let pairs = apartments.compactMap { apt -> (Apartment, FlipScoreResult)? in
            guard activeStatusFilters.contains(apt.status) else { return nil }
            // Skip auto-detected auctions and deposit-paid listings unless explicitly shown
            if apt.isAuction && !showAuctions { return nil }
            if apt.isDepositPaid && !showDeposits { return nil }
            // Skip apartments whose nearest metro is in the banlist
            if let metro = apt.metro, metroBanlist.contains(metro) { return nil }
            // Skip apartments not in the active okrug filter (empty set = show all)
            if !activeOkrugFilters.isEmpty {
                guard let okrug = apt.okrug, activeOkrugFilters.contains(okrug) else { return nil }
            }
            // Skip apartments not matching the active room filter (empty = show all).
            // Apartments with unknown roomsCount are always shown.
            if !activeRoomFilters.isEmpty, let rooms = apt.roomsCount {
                guard activeRoomFilters.contains(min(rooms, 4)) else { return nil }
            }
            return (apt, flipAnalyzer.analyze(apartment: apt, benchmark: benchmark, thresholds: thresholds))
        }

        let sorted = pairs.sorted { lhs, rhs in
            // ascending = natural for price/area, so invert for descending only on those
            let descending: Bool
            switch sortOrder {
            case .flipScore:   descending = lhs.1.totalScore > rhs.1.totalScore
            case .price:       descending = lhs.0.price < rhs.0.price
            case .area:        descending = (lhs.0.area ?? 0) > (rhs.0.area ?? 0)
            case .viewsPerDay: descending = (lhs.1.viewsPerDay ?? -1) > (rhs.1.viewsPerDay ?? -1)
            case .dateAdded:   descending = lhs.0.dateAdded > rhs.0.dateAdded
            }
            return sortAscending ? !descending : descending
        }
        cachedScores = sorted
    }

    /// Toggle a status in the active filter set.
    func toggleStatusFilter(_ status: ApartmentStatus) {
        if activeStatusFilters.contains(status) {
            activeStatusFilters.remove(status)
        } else {
            activeStatusFilters.insert(status)
        }
    }

    /// Toggle an okrug in the active okrug filter set.
    func toggleOkrugFilter(_ okrug: String) {
        if activeOkrugFilters.contains(okrug) {
            activeOkrugFilters.remove(okrug)
        } else {
            activeOkrugFilters.insert(okrug)
        }
    }

    /// Toggle a room count bucket in the active room filter set.
    func toggleRoomFilter(_ bucket: Int) {
        if activeRoomFilters.contains(bucket) {
            activeRoomFilters.remove(bucket)
        } else {
            activeRoomFilters.insert(bucket)
        }
    }

    // MARK: - URL Lookup

    /// Finds an apartment in the database by its Cian listing URL.
    /// Returns nil if the ID can't be parsed or the apartment isn't in the DB yet.
    func lookupApartment(byURL urlString: String) -> Apartment? {
        guard let id = Self.extractApartmentID(from: urlString) else { return nil }
        let descriptor = FetchDescriptor<Apartment>(predicate: #Predicate { $0.id == id })
        return try? modelContext.fetch(descriptor).first
    }

    private static func extractApartmentID(from urlString: String) -> String? {
        // Matches Cian flat URLs: /flat/123456/, /sale/flat/123456789/, etc.
        let pattern = "/flat[^/]*/([0-9]{5,12})(?:/|$)"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: urlString, range: NSRange(urlString.startIndex..., in: urlString)),
              let range = Range(match.range(at: 1), in: urlString) else { return nil }
        return String(urlString[range])
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

    func startScraping(urls: [String]) {
        guard !urls.isEmpty else {
            log = "❌ Список ссылок пуст — добавьте URL в Настройках"
            return
        }
        searchURLs = urls
        currentURLIndex = 0
        currentPage = 1
        loadNextPage()
    }

    func stopScraping() {
        isScraping = false
        currentURL = nil
        currentPage = 1
        currentURLIndex = 0
    }

    private func loadNextPage() {
        guard !searchURLs.isEmpty else { return }
        let urlStr = searchURLs[currentURLIndex]
        let baseURL = URLBuilder.extractBaseURL(from: urlStr)
        guard let url = URLBuilder.buildSearchURL(baseURL: baseURL, page: currentPage) else {
            log = "❌ Некорректный URL: \(urlStr)"
            return
        }

        currentURL = url
        isScraping = true

        let urlLabel = "\(currentURLIndex + 1)/\(searchURLs.count)"
        if enablePagination {
            log = "📄 Ссылка \(urlLabel), страница \(currentPage)/\(maxPages)..."
        } else {
            log = "📄 Ссылка \(urlLabel)..."
        }
        print("🔗 Загрузка URL: \(url.absoluteString)")
    }

    private func onPageCompleted() {
        if enablePagination && currentPage < maxPages {
            // More pages for the current URL
            currentPage += 1
            let delay = Double.random(in: 5.0...10.0)
            log = "⏳ Ожидание \(String(format: "%.1f", delay)) сек перед стр. \(currentPage)/\(maxPages)..."
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard let self, self.isScraping else { return }
                self.loadNextPage()
            }
        } else {
            // Advance to the next URL, wrapping around (infinite cycle)
            currentPage = 1
            currentURLIndex = (currentURLIndex + 1) % searchURLs.count
            let delay = Double.random(in: 5.0...10.0)
            let isNewCycle = currentURLIndex == 0
            log = "⏳ \(isNewCycle ? "Новый цикл" : "Следующая ссылка \(currentURLIndex + 1)/\(searchURLs.count)") через \(String(format: "%.1f", delay)) сек..."
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard let self, self.isScraping else { return }
                self.loadNextPage()
            }
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
                    // Populate okrug for apartments that were parsed before this field existed
                    if existing.okrug == nil {
                        existing.okrug = flipAnalyzer.extractOkrug(from: existing.address)
                    }
                } else if apartment.price > 0 {
                    // Don't insert apartments with price = 0 — parser failure, not a real listing
                    apartment.okrug = flipAnalyzer.extractOkrug(from: apartment.address)
                    modelContext.insert(apartment)
                    newlyInserted.append(apartment)
                    newCount += 1
                }
            }

            log = "✅ Успешно! Новых: \(newCount) | Обновлено: \(updatedCount) | Всего на странице: \(foundApartments.count)"

            // Auto-enqueue new apartments for detail parsing if enabled
            if autoDetailParsing && !newlyInserted.isEmpty {
                detailLoader.enqueue(newlyInserted)
                // In sequential mode: wait for this batch to finish before moving to next URL
                if parsingMode == .sequential {
                    pendingPageCompletion = true
                    log += " — ожидаю детального парсинга..."
                    return
                }
            }

            onPageCompleted()
        } else {
            log = "⚠️ Квартиры не найдены. Возможно, блокировка или капча."
        }
    }

    @discardableResult
    private func updateExistingApartment(_ existing: Apartment, with new: Apartment) -> Bool {
        var hasChanges = false

        // Always mark as seen in this search run
        existing.lastSeenInSearch = Date()

        // Only update price if the new value is valid (> 0).
        // HTML fallback parsers often return price = 0 when they can't extract the price —
        // we must never overwrite a real price with a parser failure.
        if new.price > 0 && existing.price != new.price {
            existing.price = new.price
            existing.priceHistory.append(PricePoint(price: new.price, date: Date()))
            // Price changed — detail data may be stale, allow re-parsing
            existing.isDetailedParsed = false
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
        staleCheckInProgress = false
        log = "🔍 Запуск детального парсинга..."
        detailLoader.loadDetailPages(for: apartments)
    }

    /// Queues apartments not seen in search for staleDaysThreshold+ days for re-check.
    /// Skips .ban and .deal — those are terminal statuses.
    func checkStaleApartments(from apartments: [Apartment]) {
        let cutoff = Calendar.current.date(byAdding: .day, value: -staleDaysThreshold, to: Date()) ?? Date()
        let stale = apartments.filter { apt in
            apt.lastSeenInSearch < cutoff && apt.status != .ban && apt.status != .deal
        }
        guard !stale.isEmpty else {
            log = "✅ Нет устаревших квартир (порог: \(staleDaysThreshold) дн.)"
            return
        }
        log = "🔍 Проверяю активность \(stale.count) кв. (не видели > \(staleDaysThreshold) дн.)..."
        staleCheckInProgress = true
        detailLoader.loadDetailPages(for: stale)
    }

    private func onDetailParsingComplete() {
        do {
            try modelContext.save()
            modelContext.processPendingChanges()
        } catch {
            log = "❌ Ошибка сохранения: \(error.localizedDescription)"
            staleCheckInProgress = false
            pendingPageCompletion = false
            return
        }

        // Sequential mode: detail batch for one URL finished — now advance to next URL
        if pendingPageCompletion {
            pendingPageCompletion = false
            log = "✅ Детальный парсинг блока завершён — переходим к следующей ссылке..."
            onPageCompleted()
            return
        }

        // If we just finished a stale check — don't immediately re-trigger.
        // If autoCheckActivity is on and this was a regular parsing batch — run stale check next.
        if staleCheckInProgress {
            staleCheckInProgress = false
            log = "✅ Проверка активности завершена"
        } else if autoCheckActivity {
            log = "✅ Детальный парсинг завершён — запускаю проверку активности..."
            let descriptor = FetchDescriptor<Apartment>()
            if let all = try? modelContext.fetch(descriptor) {
                checkStaleApartments(from: all)
            }
        } else {
            log = "✅ Детальный парсинг завершён"
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
