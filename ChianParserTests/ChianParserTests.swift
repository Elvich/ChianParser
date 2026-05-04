//
//  ChianParserTests.swift
//  ChianParserTests
//

import Foundation
import Testing
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
        let ctx = analyzer.buildBenchmark(from: apartments)
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
        let ctx = analyzer.buildBenchmark(from: apartments)
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
        let results = CianDataExtractor.extractData(from: html)
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
        let results = CianDataExtractor.extractData(from: html)
        let apt = try #require(results.first)
        #expect(apt.floor == 7)
        #expect(apt.totalFloors == 16)
        #expect(apt.area == 54.0)
    }

    @Test("Detects studio from title")
    func extractOffers_studio() throws {
        let html = "<html><body>\(makeArticleHTML(title: "Студия, 24,2 м², 3/12 этаж"))</body></html>"
        let results = CianDataExtractor.extractData(from: html)
        let apt = try #require(results.first)
        #expect(apt.roomsCount == 0)
    }

    @Test("Detects rooms count from title")
    func extractOffers_roomsCount() throws {
        let html = "<html><body>\(makeArticleHTML(title: "3-комн. квартира, 78 м², 5/9 этаж"))</body></html>"
        let results = CianDataExtractor.extractData(from: html)
        let apt = try #require(results.first)
        #expect(apt.roomsCount == 3)
    }

    @Test("Returns empty array for HTML with no articles")
    func extractOffers_noArticles() {
        let html = "<html><body><p>Ничего не найдено</p></body></html>"
        #expect(CianDataExtractor.extractData(from: html).isEmpty)
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
        #expect(CianDataExtractor.extractData(from: html).isEmpty)
    }

    @Test("Parses multiple articles")
    func extractOffers_multipleArticles() {
        let a1 = makeArticleHTML(id: "111", title: "1-комн. квартира, 35 м², 3/5 этаж", price: "5 000 000 \u{20BD}")
        let a2 = makeArticleHTML(id: "222", title: "2-комн. квартира, 54 м², 8/12 этаж", price: "8 500 000 \u{20BD}")
        let html = "<html><body>\(a1)\(a2)</body></html>"
        let results = CianDataExtractor.extractData(from: html)
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
        let results = CianDataExtractor.extractData(from: "<html><body>\(articleHTML)</body></html>")
        let apt = try #require(results.first)
        #expect(apt.url.hasPrefix("https://www.cian.ru"))
    }
}

// MARK: - CianDetailParser: Views Regex

@Suite("CianDetailParser — Views Regex")
@MainActor
struct CianDetailParserViewsTests {

    // Access the internal parsing via public API:
    // Create an apartment, build wrapped HTML, call parseDetailJSON.
    private func makeApartment() -> Apartment {
        Apartment(id: "test", title: "Тест", price: 5_000_000, url: "", address: "Москва")
    }

    /// Builds a minimal __NEXT_DATA__ JSON that includes a views-formatted string.
    private func makeJSON(viewsString: String) -> String {
        """
        {"props":{"pageProps":{"initialState":{"offerData":{"offer":{"stats":{"totalViewsFormattedString":"\(viewsString)"}}}}}}}
        """
    }

    @Test("Parses views with comma separator")
    func views_commaSeparator() throws {
        let apt = makeApartment()
        CianDetailParser.parseDetailJSON(jsonString: makeJSON(viewsString: "1 709 просмотров, 44 за сегодня"), apartment: apt)
        #expect(apt.viewsTotal == 1709)
        #expect(apt.viewsToday == 44)
    }

    @Test("Parses views with middle-dot separator")
    func views_dotSeparator() throws {
        let apt = makeApartment()
        CianDetailParser.parseDetailJSON(jsonString: makeJSON(viewsString: "446 просмотров · 513 за сегодня"), apartment: apt)
        #expect(apt.viewsTotal == 446)
        #expect(apt.viewsToday == 513)
    }

    @Test("Returns nil viewsToday when string absent")
    func views_absent() {
        let apt = makeApartment()
        let json = """
        {"props":{"pageProps":{"initialState":{"offerData":{"offer":{}}}}}}
        """
        CianDetailParser.parseDetailJSON(jsonString: json, apartment: apt)
        #expect(apt.viewsToday == nil)
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
        let benchmark = BenchmarkContext(byOkrug: [:], globalMedian: nil, globalSampleSize: 0)
        let result = analyzer.analyze(apartment: apt, benchmark: benchmark, thresholds: thresholds)
        #expect(result.demandLevel == .noData)
    }

    @Test("viewsToday = 30 → low")
    func demand_low() {
        let apt = makeApartment(viewsToday: 30)
        let benchmark = BenchmarkContext(byOkrug: [:], globalMedian: nil, globalSampleSize: 0)
        let result = analyzer.analyze(apartment: apt, benchmark: benchmark, thresholds: thresholds)
        #expect(result.demandLevel == .low)
    }

    @Test("viewsToday = 150 → market")
    func demand_market() {
        let apt = makeApartment(viewsToday: 150)
        let benchmark = BenchmarkContext(byOkrug: [:], globalMedian: nil, globalSampleSize: 0)
        let result = analyzer.analyze(apartment: apt, benchmark: benchmark, thresholds: thresholds)
        #expect(result.demandLevel == .market)
    }

    @Test("viewsToday = 250 → hot")
    func demand_hot() {
        let apt = makeApartment(viewsToday: 250)
        let benchmark = BenchmarkContext(byOkrug: [:], globalMedian: nil, globalSampleSize: 0)
        let result = analyzer.analyze(apartment: apt, benchmark: benchmark, thresholds: thresholds)
        #expect(result.demandLevel == .hot)
    }
}
