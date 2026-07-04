//
//  ChianParserTests.swift
//  ChianParserTests
//

import Foundation
import Testing
import SwiftData
@testable import ChianParser

// MARK: - FlipAnalyzer: Scoring

@Suite("FlipAnalyzer — Scoring")
@MainActor
struct FlipAnalyzerScoringTests {

    let analyzer = FlipAnalyzer()
    let thresholds = DemandThresholds.default

    private func makeApartment(
        price: Int = 10_000_000,
        area: Double? = 50,
        floor: Int? = 5,
        totalFloors: Int? = 16,
        metro: String? = "Таганская",
        metroDistance: Int? = 7,
        metroTransportType: String? = "walk",
        address: String = "Москва, ЦАО"
    ) -> Apartment {
        let apt = Apartment(id: UUID().uuidString, title: "Test", price: price, url: "", address: address)
        apt.area = area
        apt.floor = floor
        apt.totalFloors = totalFloors
        apt.metro = metro
        apt.metroDistance = metroDistance
        apt.metroTransportType = metroTransportType
        return apt
    }

    // MARK: - Price Score

    @Test("Price 25%+ below benchmark → max 40 pts")
    func priceScore_deepDiscount() {
        let apt = makeApartment(price: 5_000_000, area: 50) // 100k/m²
        let benchmark = BenchmarkContext(
            byOkrug: ["ЦАО": OkrugBenchmark(medianPriceSqm: 200_000, sampleSize: 10, okrug: "ЦАО")],
            globalMedian: 200_000,
            globalSampleSize: 10
        )
        let result = analyzer.analyze(apartment: apt, benchmark: benchmark, thresholds: thresholds)
        #expect(result.priceScore == 40)
    }

    @Test("Price above benchmark → 0 pts")
    func priceScore_aboveMarket() {
        let apt = makeApartment(price: 20_000_000, area: 50) // 400k/m²
        let benchmark = BenchmarkContext(
            byOkrug: [:],
            globalMedian: 200_000,
            globalSampleSize: 10
        )
        let result = analyzer.analyze(apartment: apt, benchmark: benchmark, thresholds: thresholds)
        #expect(result.priceScore == 0)
    }

    @Test("No benchmark data → fallback score 6")
    func priceScore_noBenchmark() {
        let apt = makeApartment(price: 10_000_000, area: 50)
        let benchmark = BenchmarkContext(byOkrug: [:], globalMedian: nil, globalSampleSize: 0)
        let result = analyzer.analyze(apartment: apt, benchmark: benchmark, thresholds: thresholds)
        #expect(result.priceScore == 6)
    }

    // MARK: - Metro Score

    @Test("Walk ≤5 min → max 25 pts")
    func metroScore_walkClose() {
        let apt = makeApartment(metroDistance: 4, metroTransportType: "walk")
        let benchmark = BenchmarkContext(byOkrug: [:], globalMedian: nil, globalSampleSize: 0)
        let result = analyzer.analyze(apartment: apt, benchmark: benchmark, thresholds: thresholds)
        #expect(result.metroScore == 25)
    }

    @Test("Transport 10 min → 13 pts")
    func metroScore_transportMedium() {
        let apt = makeApartment(metroDistance: 10, metroTransportType: "transport")
        let benchmark = BenchmarkContext(byOkrug: [:], globalMedian: nil, globalSampleSize: 0)
        let result = analyzer.analyze(apartment: apt, benchmark: benchmark, thresholds: thresholds)
        #expect(result.metroScore == 13)
    }

    @Test("No metro data → 0 pts")
    func metroScore_noData() {
        let apt = makeApartment(metro: nil, metroDistance: nil, metroTransportType: nil)
        let benchmark = BenchmarkContext(byOkrug: [:], globalMedian: nil, globalSampleSize: 0)
        let result = analyzer.analyze(apartment: apt, benchmark: benchmark, thresholds: thresholds)
        #expect(result.metroScore == 0)
    }

    // MARK: - Location Score (floor mode, default)

    @Test("First floor → 0 pts")
    func floorScore_firstFloor() {
        let apt = makeApartment(floor: 1, totalFloors: 16)
        let benchmark = BenchmarkContext(byOkrug: [:], globalMedian: nil, globalSampleSize: 0)
        let result = analyzer.analyze(apartment: apt, benchmark: benchmark, thresholds: thresholds)
        #expect(result.locationScore == 0)
        #expect(result.isDistrictScore == false)
    }

    @Test("Last floor → 5 pts")
    func floorScore_lastFloor() {
        let apt = makeApartment(floor: 16, totalFloors: 16)
        let benchmark = BenchmarkContext(byOkrug: [:], globalMedian: nil, globalSampleSize: 0)
        let result = analyzer.analyze(apartment: apt, benchmark: benchmark, thresholds: thresholds)
        #expect(result.locationScore == 5)
    }

    @Test("Middle floor → max 20 pts")
    func floorScore_middleFloor() {
        let apt = makeApartment(floor: 8, totalFloors: 16)
        let benchmark = BenchmarkContext(byOkrug: [:], globalMedian: nil, globalSampleSize: 0)
        let result = analyzer.analyze(apartment: apt, benchmark: benchmark, thresholds: thresholds)
        #expect(result.locationScore == 20)
    }

    @Test("District mode: explicit score 18 → 18 pts")
    func districtScore_explicit() {
        let apt = makeApartment()
        apt.district = "Арбат"
        let benchmark = BenchmarkContext(byOkrug: [:], globalMedian: nil, globalSampleSize: 0,
                                         districtScores: ["Арбат": 18], useDistrictScore: true)
        let result = analyzer.analyze(apartment: apt, benchmark: benchmark, thresholds: thresholds)
        #expect(result.locationScore == 18)
        #expect(result.isDistrictScore == true)
    }

    @Test("District mode: score capped at 20")
    func districtScore_cappedAt20() {
        let apt = makeApartment()
        apt.district = "Арбат"
        let benchmark = BenchmarkContext(byOkrug: [:], globalMedian: nil, globalSampleSize: 0,
                                         districtScores: ["Арбат": 25], useDistrictScore: true)
        let result = analyzer.analyze(apartment: apt, benchmark: benchmark, thresholds: thresholds)
        #expect(result.locationScore == 20)
    }

    @Test("District mode: no district data → neutral 7 pts")
    func districtScore_noData() {
        let apt = makeApartment()
        apt.district = nil
        let benchmark = BenchmarkContext(byOkrug: [:], globalMedian: nil, globalSampleSize: 0,
                                         districtScores: ["Арбат": 20], useDistrictScore: true)
        let result = analyzer.analyze(apartment: apt, benchmark: benchmark, thresholds: thresholds)
        #expect(result.locationScore == 7)
        #expect(result.isDistrictScore == true)
    }

    // MARK: - Area Score

    @Test("Area ≥60 m² → max 15 pts")
    func areaScore_large() {
        let apt = makeApartment(area: 70)
        let benchmark = BenchmarkContext(byOkrug: [:], globalMedian: nil, globalSampleSize: 0)
        let result = analyzer.analyze(apartment: apt, benchmark: benchmark, thresholds: thresholds)
        #expect(result.areaScore == 15)
    }

    @Test("Area <30 m² → 2 pts")
    func areaScore_tiny() {
        let apt = makeApartment(area: 20)
        let benchmark = BenchmarkContext(byOkrug: [:], globalMedian: nil, globalSampleSize: 0)
        let result = analyzer.analyze(apartment: apt, benchmark: benchmark, thresholds: thresholds)
        #expect(result.areaScore == 2)
    }
}

// MARK: - FlipAnalyzer: Benchmark

@Suite("FlipAnalyzer — Benchmark")
@MainActor
struct FlipAnalyzerBenchmarkTests {

    let analyzer = FlipAnalyzer()

    @Test("Benchmark uses okrug median when ≥5 samples")
    func benchmark_usesOkrugMedian() {
        var apartments: [Apartment] = []
        for i in 1...6 {
            let apt = Apartment(id: "\(i)", title: "T", price: i * 100_000 * 50, url: "", address: "Москва, ЦАО")
            apt.area = 50
            apartments.append(apt)
        }
        let ctx = analyzer.buildBenchmark(from: apartments, targetPercentile: 0.5)
        #expect(ctx.byOkrug["ЦАО"] != nil)
        #expect(ctx.globalSampleSize == 6)
    }

    @Test("Benchmark: okrug with <5 samples is excluded, global median still computed")
    func benchmark_fallsBackToGlobal() {
        // 4 apartments in ЦАО (< minSamples=5), plus 5 in other addresses → global has 9 samples
        var apartments: [Apartment] = []
        for i in 1...4 {
            let apt = Apartment(id: "cao\(i)", title: "T", price: i * 100_000 * 50, url: "", address: "Москва, ЦАО")
            apt.area = 50
            apartments.append(apt)
        }
        for i in 1...5 {
            let apt = Apartment(id: "sao\(i)", title: "T", price: i * 80_000 * 50, url: "", address: "Москва, САО")
            apt.area = 50
            apartments.append(apt)
        }
        let ctx = analyzer.buildBenchmark(from: apartments, targetPercentile: 0.5)
        // ЦАО has only 4 samples → should not appear in byOkrug
        #expect(ctx.byOkrug["ЦАО"] == nil)
        // СAО has 5 samples → should appear
        #expect(ctx.byOkrug["САО"] != nil)
        // Global median is computed from all 9 samples
        #expect(ctx.globalMedian != nil)
        #expect(ctx.globalSampleSize == 9)
    }

    @Test("priceDiscount is negative when apartment is below market")
    func priceDiscount_belowMarket() throws {
        let result = FlipScoreResult(
            totalScore: 80,
            priceScore: 40, metroScore: 20, locationScore: 20, isDistrictScore: false, areaScore: 0,
            sellerBonus: 0,
            priceSqm: 150_000, benchmarkSqm: 200_000,
            benchmarkOkrug: "ЦАО", benchmarkSampleSize: 10,
            demandLevel: .market, viewsPerDay: 120
        )
        let discount = try #require(result.priceDiscount)
        #expect(discount < 0)
        #expect(abs(discount - (-0.25)) < 0.001)
    }
}

// MARK: - CianResponse: HTML Parser

@Suite("CianResponse — HTML Parser")
struct CianResponseHTMLParserTests {

    // Minimal Cian-like article HTML with data-name attributes.
    // Mirrors the real structure confirmed from the live page.
    private func makeArticleHTML(
        id: String = "123456789",
        title: String = "2-комн. квартира, 54 м², 7/16 этаж",
        price: String = "9 500 000 \u{20BD}",
        geoLabels: [String] = ["Москва", "ЮАО", "р-н Чертаново Северное", "м. Южная", "Балаклавский проспект", "5"],
        specialGeo: String = "Южная\n8 минут пешком"
    ) -> String {
        let geoHTML = geoLabels.map { "<span data-name=\"GeoLabel\">\($0)</span>" }.joined()
        return """
        <article data-name="CardComponent">
          <a href="https://www.cian.ru/sale/flat/\(id)/" target="_blank"></a>
          <div data-name="TitleComponent">\(title)</div>
          <div data-name="ContentRow">\(price)</div>
          <div data-name="SpecialGeo">\(specialGeo)</div>
          \(geoHTML)
        </article>
        """
    }

    @Test("Extracts basic apartment fields from HTML")
    func extractOffers_basicFields() throws {
        let html = "<html><body>\(makeArticleHTML())</body></html>"
        let extractor = CianDataExtractor(selectorsManager: SelectorsManager())
        let results = extractor.extractData(from: html)
        let apt = try #require(results.first)
        #expect(apt.id == "123456789")
        #expect(apt.price == 9_500_000)
        #expect(apt.title == "2-комн. квартира, 54 м², 7/16 этаж")
        #expect(apt.address == "Москва, ЮАО, р-н Чертаново Северное, м. Южная, Балаклавский проспект, 5")
        #expect(apt.metro == "Южная")
        #expect(apt.metroDistance == 8)
        #expect(apt.metroTransportType == "walk")
    }

    @Test("Extracts floor and area from title")
    func extractOffers_floorAndArea() throws {
        let html = "<html><body>\(makeArticleHTML())</body></html>"
        let extractor = CianDataExtractor(selectorsManager: SelectorsManager())
        let results = extractor.extractData(from: html)
        let apt = try #require(results.first)
        #expect(apt.floor == 7)
        #expect(apt.totalFloors == 16)
        #expect(apt.area == 54.0)
    }

    @Test("Detects studio from title")
    func extractOffers_studio() throws {
        let html = "<html><body>\(makeArticleHTML(title: "Студия, 24,2 м², 3/12 этаж"))</body></html>"
        let extractor = CianDataExtractor(selectorsManager: SelectorsManager())
        let results = extractor.extractData(from: html)
        let apt = try #require(results.first)
        #expect(apt.roomsCount == 0)
    }

    @Test("Detects rooms count from title")
    func extractOffers_roomsCount() throws {
        let html = "<html><body>\(makeArticleHTML(title: "3-комн. квартира, 78 м², 5/9 этаж"))</body></html>"
        let extractor = CianDataExtractor(selectorsManager: SelectorsManager())
        let results = extractor.extractData(from: html)
        let apt = try #require(results.first)
        #expect(apt.roomsCount == 3)
    }

    @Test("Returns empty array for HTML with no articles")
    func extractOffers_noArticles() {
        let html = "<html><body><p>Ничего не найдено</p></body></html>"
        let extractor = CianDataExtractor(selectorsManager: SelectorsManager())
        #expect(extractor.extractData(from: html).isEmpty)
    }

    @Test("Skips article if /flat/ URL is not present")
    func extractOffers_skipsNonFlatLink() {
        let html = """
        <html><body>
        <article data-name="CardComponent">
          <a href="https://www.cian.ru/sale/commercial/999/">не квартира</a>
          <div data-name="TitleComponent">Офис</div>
          <div data-name="ContentRow">5 000 000 \u{20BD}</div>
        </article>
        </body></html>
        """
        let extractor = CianDataExtractor(selectorsManager: SelectorsManager())
        #expect(extractor.extractData(from: html).isEmpty)
    }

    @Test("Parses multiple articles")
    func extractOffers_multipleArticles() {
        let a1 = makeArticleHTML(id: "111", title: "1-комн. квартира, 35 м², 3/5 этаж", price: "5 000 000 \u{20BD}")
        let a2 = makeArticleHTML(id: "222", title: "2-комн. квартира, 54 м², 8/12 этаж", price: "8 500 000 \u{20BD}")
        let html = "<html><body>\(a1)\(a2)</body></html>"
        let extractor = CianDataExtractor(selectorsManager: SelectorsManager())
        let results = extractor.extractData(from: html)
        #expect(results.count == 2)
        #expect(results.map(\.id).contains("111"))
        #expect(results.map(\.id).contains("222"))
    }

    @Test("URL is absolute — relative href gets prefixed")
    func extractOffers_relativeURL() throws {
        let articleHTML = """
        <article data-name="CardComponent">
          <a href="/sale/flat/777777/"></a>
          <div data-name="TitleComponent">Студия, 20 м², 2/5 этаж</div>
          <div data-name="ContentRow">3 000 000 \u{20BD}</div>
        </article>
        """
        let extractor = CianDataExtractor(selectorsManager: SelectorsManager())
        let results = extractor.extractData(from: "<html><body>\(articleHTML)</body></html>")
        let apt = try #require(results.first)
        #expect(apt.url.hasPrefix("https://www.cian.ru"))
    }
}

// MARK: - CianDetailParser: Views Regex

@Suite("CianDetailParser — Views Regex")
@MainActor
struct CianDetailParserViewsTests {

    // Доступ к внутреннему парсингу через публичный API:
    // Создаем объект квартиры, конструируем обертку JSON и вызываем parseDetailJSON.
    private func makeApartment() -> Apartment {
        Apartment(id: "test", title: "Тест", price: 5_000_000, url: "", address: "Москва")
    }

    /// Строит минимальный JSON __NEXT_DATA__, содержащий строку с форматированными просмотрами.
    private func makeJSON(viewsString: String) -> String {
        """
        {"props":{"pageProps":{"initialState":{"offerData":{"offer":{"stats":{"totalViewsFormattedString":"\(viewsString)"}}}}}}}
        """
    }

    @Test("Парсит просмотры с разделителем-запятой")
    func views_commaSeparator() throws {
        let apt = makeApartment()
        let parser = CianDetailParser(selectorsManager: SelectorsManager())
        parser.parseDetailJSON(jsonString: makeJSON(viewsString: "1 709 просмотров, 44 за сегодня"), apartment: apt)
        #expect(apt.viewsTotal == 1709)
        #expect(apt.viewsToday == 44)
    }

    @Test("Парсит просмотры с разделителем-точкой")
    func views_dotSeparator() throws {
        let apt = makeApartment()
        let parser = CianDetailParser(selectorsManager: SelectorsManager())
        parser.parseDetailJSON(jsonString: makeJSON(viewsString: "446 просмотров · 513 за сегодня"), apartment: apt)
        #expect(apt.viewsTotal == 446)
        #expect(apt.viewsToday == 513)
    }

    @Test("Возвращает nil для viewsToday, если строка отсутствует")
    func views_absent() {
        let apt = makeApartment()
        let json = """
        {"props":{"pageProps":{"initialState":{"offerData":{"offer":{}}}}}}
        """
        let parser = CianDetailParser(selectorsManager: SelectorsManager())
        parser.parseDetailJSON(jsonString: json, apartment: apt)
        #expect(apt.viewsToday == nil)
    }

    @Test("Парсит просмотры с фразой 'нет за сегодня'")
    func views_noViewsToday() throws {
        let apt = makeApartment()
        let parser = CianDetailParser(selectorsManager: SelectorsManager())
        parser.parseDetailJSON(jsonString: makeJSON(viewsString: "1 254 просмотра, нет за сегодня"), apartment: apt)
        #expect(apt.viewsTotal == 1254)
        #expect(apt.viewsToday == 0)
    }

    @Test("Парсит общее количество просмотров при отсутствии просмотров за сегодня")
    func views_onlyTotalViews() throws {
        let apt = makeApartment()
        let parser = CianDetailParser(selectorsManager: SelectorsManager())
        parser.parseDetailJSON(jsonString: makeJSON(viewsString: "847 просмотров"), apartment: apt)
        #expect(apt.viewsTotal == 847)
        #expect(apt.viewsToday == nil)
    }

    @Test("Извлекает __viewsHistory и сохраняет в viewsHistoryJSON")
    func views_viewsHistoryExtraction() throws {
        let apt = makeApartment()
        let parser = CianDetailParser(selectorsManager: SelectorsManager())
        let json = """
        {"__viewsHistory":"{\\"days\\":[{\\"date\\":\\"2026-07-01\\",\\"views\\":10}]}"}
        """
        parser.parseDetailJSON(jsonString: json, apartment: apt)
        #expect(apt.viewsHistoryJSON == "{\"days\":[{\"date\":\"2026-07-01\",\"views\":10}]}")
    }

    @Test("Парсит просмотры из DOM Fallback с использованием селектора data-name")
    func views_domFallbackDataName() throws {
        let apt = makeApartment()
        let parser = CianDetailParser(selectorsManager: SelectorsManager())
        let html = """
        <html>
        <body>
          <div data-name="OfferStats">1 890 просмотров · 12 за сегодня</div>
        </body>
        </html>
        """
        parser.parseDetailPage(html: html, apartment: apt)
        #expect(apt.viewsTotal == 1890)
        #expect(apt.viewsToday == 12)
    }

    @Test("Парсит просмотры из DOM Fallback с использованием сырого текста страницы")
    func views_domFallbackRawText() throws {
        let apt = makeApartment()
        let parser = CianDetailParser(selectorsManager: SelectorsManager())
        let html = """
        <html>
        <body>
          <p>Некий текст на странице. Всего 789 просмотров, нет за сегодня.</p>
        </body>
        </html>
        """
        parser.parseDetailPage(html: html, apartment: apt)
        #expect(apt.viewsTotal == 789)
        #expect(apt.viewsToday == 0)
    }
}

// MARK: - FlipAnalyzer: Demand

@Suite("FlipAnalyzer — Demand")
@MainActor
struct FlipAnalyzerDemandTests {

    let analyzer = FlipAnalyzer()
    let thresholds = DemandThresholds(moderate: 50, market: 100, hot: 200)

    private func makeApartment(viewsToday: Int?) -> Apartment {
        let apt = Apartment(id: UUID().uuidString, title: "T", price: 5_000_000, url: "", address: "Москва")
        apt.viewsToday = viewsToday
        return apt
    }

    @Test("viewsToday = nil → noData")
    func demand_noData() {
        let apt = makeApartment(viewsToday: nil)
        let benchmark = BenchmarkContext(byOkrug: [:], globalMedian: nil, globalSampleSize: 0, extrapolateMorningViews: false)
        let result = analyzer.analyze(apartment: apt, benchmark: benchmark, thresholds: thresholds)
        #expect(result.demandLevel == .noData)
    }

    @Test("viewsToday = 30 → low")
    func demand_low() {
        let apt = makeApartment(viewsToday: 30)
        let benchmark = BenchmarkContext(byOkrug: [:], globalMedian: nil, globalSampleSize: 0, extrapolateMorningViews: false)
        let result = analyzer.analyze(apartment: apt, benchmark: benchmark, thresholds: thresholds)
        #expect(result.demandLevel == .low)
    }

    @Test("viewsToday = 150 → market")
    func demand_market() {
        let apt = makeApartment(viewsToday: 150)
        let benchmark = BenchmarkContext(byOkrug: [:], globalMedian: nil, globalSampleSize: 0, extrapolateMorningViews: false)
        let result = analyzer.analyze(apartment: apt, benchmark: benchmark, thresholds: thresholds)
        #expect(result.demandLevel == .market)
    }

    @Test("viewsToday = 250 → hot")
    func demand_hot() {
        let apt = makeApartment(viewsToday: 250)
        let benchmark = BenchmarkContext(byOkrug: [:], globalMedian: nil, globalSampleSize: 0, extrapolateMorningViews: false)
        let result = analyzer.analyze(apartment: apt, benchmark: benchmark, thresholds: thresholds)
        #expect(result.demandLevel == .hot)
    }

    @Test("Использует точные просмотры за вчера из истории")
    func demand_yesterdayViewsFromHistory() {
        let apt = Apartment(id: UUID().uuidString, title: "T", price: 5_000_000, url: "", address: "Москва")
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let yesterdayStr = formatter.string(from: yesterday)
        
        apt.viewsHistoryJSON = """
        {"daily":{"dailyViews":[{"date":"\(yesterdayStr)","views":150}]}}
        """
        let benchmark = BenchmarkContext(byOkrug: [:], globalMedian: nil, globalSampleSize: 0, extrapolateMorningViews: false)
        let result = analyzer.analyze(apartment: apt, benchmark: benchmark, thresholds: thresholds)
        #expect(result.demandLevel == .market)
        #expect(result.viewsPerDay == 150.0)
    }

    @Test("Использует скользящее среднее за последние 3 завершенных дня, если вчерашний день отсутствует")
    func demand_averageLast3CompletedDays() {
        let apt = Apartment(id: UUID().uuidString, title: "T", price: 5_000_000, url: "", address: "Москва")
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let todayStr = formatter.string(from: Date())
        
        // Вчерашнего дня нет, но есть позавчерашние 3 дня: 80, 100, 120 (среднее = 100)
        apt.viewsHistoryJSON = """
        {"daily":{"dailyViews":[
            {"date":"2026-06-28","views":80},
            {"date":"2026-06-29","views":100},
            {"date":"2026-06-30","views":120},
            {"date":"\(todayStr)","views":300}
        ]}}
        """
        let benchmark = BenchmarkContext(byOkrug: [:], globalMedian: nil, globalSampleSize: 0, extrapolateMorningViews: false)
        // Задаем referenceDate в будущем, чтобы сегодняшнее число из JSON соответствовало сегодняшнему дню
        let result = analyzer.analyze(apartment: apt, benchmark: benchmark, thresholds: thresholds)
        #expect(result.demandLevel == .market)
        #expect(result.viewsPerDay == 100.0)
    }
}

// MARK: - FilterCoordinator Tests

@Suite("FilterCoordinator Tests")
struct FilterCoordinatorTests {

    private func makeApartment(
        id: String = UUID().uuidString,
        status: ApartmentStatus = .new,
        isDetailedParsed: Bool = true,
        isStudio: Bool = false,
        isApartments: Bool = false,
        isAuction: Bool = false,
        isDepositPaid: Bool = false,
        metro: String? = nil,
        metroDistance: Int? = nil,
        metroTransportType: String? = nil,
        totalFloors: Int? = nil,
        district: String? = nil,
        okrug: String? = nil,
        roomsCount: Int? = nil
    ) -> Apartment {
        let apt = Apartment(id: id, title: "Test", price: 10_000_000, url: "", address: "Moscow")
        apt.status = status
        apt.isDetailedParsed = isDetailedParsed
        apt.isStudioFlag = isStudio
        apt.isApartmentsFlag = isApartments
        apt.isAuction = isAuction
        apt.isDepositPaid = isDepositPaid
        apt.metro = metro
        apt.metroDistance = metroDistance
        apt.metroTransportType = metroTransportType
        apt.totalFloors = totalFloors
        apt.district = district
        apt.okrug = okrug
        apt.roomsCount = roomsCount
        return apt
    }

    @Test("Status filter: filters active/ignored/ban correctly")
    func testStatusFilter() {
        let coordinator = FilterCoordinator()
        let activeApt = makeApartment(status: .new)
        let banApt = makeApartment(status: .ban)
        
        // Active should be kept, ban should be dropped (by default defaultVisible does not contain ban)
        #expect(coordinator.shouldKeep(apartment: activeApt, metroBanlist: [], districtScores: [:], useDistrictScore: false) == true)
        #expect(coordinator.shouldKeep(apartment: banApt, metroBanlist: [], districtScores: [:], useDistrictScore: false) == false)
        
        coordinator.toggleStatusFilter(.ban)
        #expect(coordinator.shouldKeep(apartment: banApt, metroBanlist: [], districtScores: [:], useDistrictScore: false) == true)
    }

    @Test("Require detail parsed option")
    func testRequireDetailParsed() {
        let coordinator = FilterCoordinator()
        let parsed = makeApartment(isDetailedParsed: true)
        let unparsed = makeApartment(isDetailedParsed: false)
        
        coordinator.requireDetailParsed = true
        #expect(coordinator.shouldKeep(apartment: parsed, metroBanlist: [], districtScores: [:], useDistrictScore: false) == true)
        #expect(coordinator.shouldKeep(apartment: unparsed, metroBanlist: [], districtScores: [:], useDistrictScore: false) == false)
    }

    @Test("Hide studios and apartments option")
    func testHideStudiosAndApartments() {
        let coordinator = FilterCoordinator()
        let studio = makeApartment(isStudio: true)
        let apartment = makeApartment(isApartments: true)
        
        coordinator.hideStudios = true
        #expect(coordinator.shouldKeep(apartment: studio, metroBanlist: [], districtScores: [:], useDistrictScore: false) == false)
        #expect(coordinator.shouldKeep(apartment: apartment, metroBanlist: [], districtScores: [:], useDistrictScore: false) == true)
        
        coordinator.hideStudios = false
        coordinator.hideApartments = true
        #expect(coordinator.shouldKeep(apartment: studio, metroBanlist: [], districtScores: [:], useDistrictScore: false) == true)
        #expect(coordinator.shouldKeep(apartment: apartment, metroBanlist: [], districtScores: [:], useDistrictScore: false) == false)
    }

    @Test("Auctions and deposits filter")
    func testAuctionsAndDeposits() {
        let coordinator = FilterCoordinator()
        let auction = makeApartment(isAuction: true)
        let deposit = makeApartment(isDepositPaid: true)
        
        // Default is showAuctions = false, showDeposits = false
        #expect(coordinator.shouldKeep(apartment: auction, metroBanlist: [], districtScores: [:], useDistrictScore: false) == false)
        #expect(coordinator.shouldKeep(apartment: deposit, metroBanlist: [], districtScores: [:], useDistrictScore: false) == false)
        
        coordinator.showAuctions = true
        coordinator.showDeposits = true
        #expect(coordinator.shouldKeep(apartment: auction, metroBanlist: [], districtScores: [:], useDistrictScore: false) == true)
        #expect(coordinator.shouldKeep(apartment: deposit, metroBanlist: [], districtScores: [:], useDistrictScore: false) == true)
    }

    @Test("Metro distance and walking only filter")
    func testMetroDistanceAndTransport() {
        let coordinator = FilterCoordinator()
        let farWalk = makeApartment(metroDistance: 15, metroTransportType: "walk")
        let closeTransport = makeApartment(metroDistance: 5, metroTransportType: "transport")
        
        coordinator.maxMetroDistance = 10
        #expect(coordinator.shouldKeep(apartment: farWalk, metroBanlist: [], districtScores: [:], useDistrictScore: false) == false)
        #expect(coordinator.shouldKeep(apartment: closeTransport, metroBanlist: [], districtScores: [:], useDistrictScore: false) == true)
        
        coordinator.metroWalkOnly = true
        #expect(coordinator.shouldKeep(apartment: closeTransport, metroBanlist: [], districtScores: [:], useDistrictScore: false) == false)
    }

    @Test("Active Okrug filters")
    func testActiveOkrugFilters() {
        let coordinator = FilterCoordinator()
        let caoApt = makeApartment(okrug: "ЦАО")
        let saoApt = makeApartment(okrug: "САО")
        
        coordinator.toggleOkrugFilter("ЦАО")
        #expect(coordinator.shouldKeep(apartment: caoApt, metroBanlist: [], districtScores: [:], useDistrictScore: false) == true)
        #expect(coordinator.shouldKeep(apartment: saoApt, metroBanlist: [], districtScores: [:], useDistrictScore: false) == false)
    }

    @Test("Active Room filters")
    func testActiveRoomFilters() {
        let coordinator = FilterCoordinator()
        let studio = makeApartment(isStudio: true)
        let room1 = makeApartment(roomsCount: 1)
        let room3 = makeApartment(roomsCount: 3)
        
        coordinator.toggleRoomFilter(1)
        #expect(coordinator.shouldKeep(apartment: studio, metroBanlist: [], districtScores: [:], useDistrictScore: false) == false)
        #expect(coordinator.shouldKeep(apartment: room1, metroBanlist: [], districtScores: [:], useDistrictScore: false) == true)
        #expect(coordinator.shouldKeep(apartment: room3, metroBanlist: [], districtScores: [:], useDistrictScore: false) == false)
    }
}

// MARK: - ScoringConfiguration Tests

@Suite("ScoringConfiguration & DB Exclusions")
@MainActor
struct ScoringConfigurationTests {
    
    private func createInMemoryContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Apartment.self, PricePoint.self, ScoringConfiguration.self, configurations: config)
        return ModelContext(container)
    }

    @Test("Default ScoringConfiguration is seeded correctly")
    func testDefaultConfigSeeding() throws {
        let context = try createInMemoryContext()
        let config = context.fetchOrCreateScoringConfiguration()
        
        #expect(config.priceScoreWeight == 40)
        #expect(config.metroProximityWeight == 25)
        #expect(config.locationFloorWeight == 20)
        #expect(config.areaScoreWeight == 15)
        #expect(config.excludeStudios == true)
        #expect(config.excludeApartments == true)
        
        // Secondary fetch returns the same instance
        let secondConfig = context.fetchOrCreateScoringConfiguration()
        #expect(config.id == secondConfig.id)
    }
}

// MARK: - FlipAnalyzer: Dynamic Weights Tests

@Suite("FlipAnalyzer — Dynamic Weights")
@MainActor
struct FlipAnalyzerWeightsTests {
    let analyzer = FlipAnalyzer()
    let thresholds = DemandThresholds.default

    @Test("Calculates price score using custom weights")
    func testCustomPriceWeight() {
        let apt = Apartment(id: "1", title: "Test", price: 5_000_000, url: "", address: "Москва, ЦАО")
        apt.area = 50 // 100k/m²
        
        // Case 1: weight is 50
        let benchmark1 = BenchmarkContext(
            byOkrug: ["ЦАО": OkrugBenchmark(medianPriceSqm: 200_000, sampleSize: 10, okrug: "ЦАО")],
            globalMedian: 200_000,
            globalSampleSize: 10,
            priceScoreWeight: 50
        )
        let result1 = analyzer.analyze(apartment: apt, benchmark: benchmark1, thresholds: thresholds)
        #expect(result1.priceScore == 50)
        #expect(result1.maxPriceScore == 50)

        // Case 2: weight is 20
        let benchmark2 = BenchmarkContext(
            byOkrug: ["ЦАО": OkrugBenchmark(medianPriceSqm: 200_000, sampleSize: 10, okrug: "ЦАО")],
            globalMedian: 200_000,
            globalSampleSize: 10,
            priceScoreWeight: 20
        )
        let result2 = analyzer.analyze(apartment: apt, benchmark: benchmark2, thresholds: thresholds)
        #expect(result2.priceScore == 20)
        #expect(result2.maxPriceScore == 20)
    }

    @Test("Calculates metro score using custom weights")
    func testCustomMetroWeight() {
        let apt = Apartment(id: "1", title: "Test", price: 10_000_000, url: "", address: "Москва")
        apt.metroDistance = 4
        apt.metroTransportType = "walk"
        
        let benchmark1 = BenchmarkContext(byOkrug: [:], globalMedian: nil, globalSampleSize: 0, metroProximityWeight: 30)
        let result1 = analyzer.analyze(apartment: apt, benchmark: benchmark1, thresholds: thresholds)
        #expect(result1.metroScore == 30)
        #expect(result1.maxMetroScore == 30)
    }
}

// MARK: - FlipAnalyzer: Demand Extrapolation Tests

@Suite("FlipAnalyzer — Demand Extrapolation")
@MainActor
struct FlipAnalyzerDemandExtrapolationTests {
    let analyzer = FlipAnalyzer()
    let thresholds = DemandThresholds(moderate: 10, market: 20, hot: 50)

    private func makeApartment(
        viewsToday: Int? = nil,
        viewsTotal: Int? = nil,
        publishedDate: Date? = nil
    ) -> Apartment {
        let apt = Apartment(id: UUID().uuidString, title: "T", price: 5_000_000, url: "", address: "Москва")
        apt.viewsToday = viewsToday
        apt.viewsTotal = viewsTotal
        apt.publishedDate = publishedDate
        return apt
    }

    private func makeDate(hour: Int, minute: Int = 0) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 7
        components.day = 2
        components.hour = hour
        components.minute = minute
        components.second = 0
        return Calendar.current.date(from: components)!
    }

    // 1. По времени суток: раннее утро (с 00:00 до 08:00) -> экстраполяция отключена, безопасный фолбэк
    @Test("Early morning (03:00) -> extrapolation disabled, uses raw viewsToday")
    func earlyMorning_extrapolationDisabled() {
        let apt = makeApartment(viewsToday: 5)
        let refDate = makeDate(hour: 3) // 03:00 раннее утро
        let benchmark = BenchmarkContext(byOkrug: [:], globalMedian: nil, globalSampleSize: 0, extrapolateMorningViews: true)
        
        let result = analyzer.analyze(apartment: apt, benchmark: benchmark, thresholds: thresholds, referenceDate: refDate)
        // При viewsToday = 5 и отключенной экстраполяции: 5 просмотров в день (low demand, т.к. 5 < 10)
        #expect(result.viewsPerDay == 5.0)
        #expect(result.demandLevel == .low)
    }

    // 2. По времени суток: дневное время (12:00) -> экстраполяция включена
    @Test("Daytime (12:00) -> extrapolation enabled, scales viewsToday")
    func daytime_extrapolationEnabled() {
        let apt = makeApartment(viewsToday: 19) // 19 просмотров к 12:00
        let refDate = makeDate(hour: 12) // 12:00 день (cumulative percentage = 0.38)
        let benchmark = BenchmarkContext(byOkrug: [:], globalMedian: nil, globalSampleSize: 0, extrapolateMorningViews: true)
        
        let result = analyzer.analyze(apartment: apt, benchmark: benchmark, thresholds: thresholds, referenceDate: refDate)
        // 19 / 0.38 = 50.0 просмотров в день (hot demand, т.к. 50 >= 50)
        #expect(result.viewsPerDay == 50.0)
        #expect(result.demandLevel == .hot)
    }

    // 3. По новизне: квартира новая (опубликована 12 часов назад) -> экстраполяция новизны включена
    @Test("New apartment (12h old) -> extrapolation by age enabled")
    func newApartment_extrapolationByAge() {
        let refDate = makeDate(hour: 12) // 12:00
        let publishedDate = refDate.addingTimeInterval(-3600 * 12) // 12 часов назад
        let apt = makeApartment(viewsTotal: 10, publishedDate: publishedDate) // viewsToday = nil, сработает Фолбэк 2
        let benchmark = BenchmarkContext(byOkrug: [:], globalMedian: nil, globalSampleSize: 0)
        
        let result = analyzer.analyze(apartment: apt, benchmark: benchmark, thresholds: thresholds, referenceDate: refDate)
        // 12 часов = 0.5 дня. Экстраполировано: 10 / 0.5 = 20 просмотров в день (market demand, т.к. 20 >= 20)
        #expect(result.viewsPerDay == 20.0)
        #expect(result.demandLevel == .market)
    }

    // 4. По новизне: защита от нереалистичных выбросов для сверхновых объявлений (1 минута назад)
    @Test("Slightly new apartment (1m old) -> capped at 2 hours minimum")
    func ultraNewApartment_cappedByMinHours() {
        let refDate = makeDate(hour: 12)
        let publishedDate = refDate.addingTimeInterval(-60) // 1 минута назад
        let apt = makeApartment(viewsTotal: 1, publishedDate: publishedDate)
        let benchmark = BenchmarkContext(byOkrug: [:], globalMedian: nil, globalSampleSize: 0)
        
        let result = analyzer.analyze(apartment: apt, benchmark: benchmark, thresholds: thresholds, referenceDate: refDate)
        // Минимальное время жизни: 2 часа = 2.0 / 24.0 = 0.0833 дня.
        // Экстраполировано: 1 / 0.0833 = 12.0 просмотров в день. (moderate demand, т.к. 12 >= 10)
        #expect(abs((result.viewsPerDay ?? 0.0) - 12.0) < 0.001)
        #expect(result.demandLevel == .moderate)
    }

    // 5. По новизне: квартира старше 3 дней -> экстраполяция новизны отключена
    @Test("Old apartment (4 days old) -> extrapolation by age disabled, uses actual days")
    func oldApartment_extrapolationDisabled() {
        let refDate = makeDate(hour: 12)
        let publishedDate = refDate.addingTimeInterval(-3600 * 24 * 4) // 4 дня назад
        let apt = makeApartment(viewsTotal: 40, publishedDate: publishedDate)
        let benchmark = BenchmarkContext(byOkrug: [:], globalMedian: nil, globalSampleSize: 0)
        
        let result = analyzer.analyze(apartment: apt, benchmark: benchmark, thresholds: thresholds, referenceDate: refDate)
        // 40 / 4 дня = 10 просмотров в день (moderate demand, т.к. 10 >= 10)
        #expect(result.viewsPerDay == 10.0)
        #expect(result.demandLevel == .moderate)
    }
}

