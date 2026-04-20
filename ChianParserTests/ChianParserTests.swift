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

    // MARK: - Floor Score

    @Test("First floor → 0 pts")
    func floorScore_firstFloor() {
        let apt = makeApartment(floor: 1, totalFloors: 16)
        let benchmark = BenchmarkContext(byOkrug: [:], globalMedian: nil, globalSampleSize: 0)
        let result = analyzer.analyze(apartment: apt, benchmark: benchmark, thresholds: thresholds)
        #expect(result.floorScore == 0)
    }

    @Test("Last floor → 5 pts")
    func floorScore_lastFloor() {
        let apt = makeApartment(floor: 16, totalFloors: 16)
        let benchmark = BenchmarkContext(byOkrug: [:], globalMedian: nil, globalSampleSize: 0)
        let result = analyzer.analyze(apartment: apt, benchmark: benchmark, thresholds: thresholds)
        #expect(result.floorScore == 5)
    }

    @Test("Middle floor → max 20 pts")
    func floorScore_middleFloor() {
        let apt = makeApartment(floor: 8, totalFloors: 16)
        let benchmark = BenchmarkContext(byOkrug: [:], globalMedian: nil, globalSampleSize: 0)
        let result = analyzer.analyze(apartment: apt, benchmark: benchmark, thresholds: thresholds)
        #expect(result.floorScore == 20)
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
            priceScore: 40, metroScore: 20, floorScore: 20, areaScore: 0,
            priceSqm: 150_000, benchmarkSqm: 200_000,
            benchmarkOkrug: "ЦАО", benchmarkSampleSize: 10,
            demandLevel: .market, viewsPerDay: 120
        )
        let discount = try #require(result.priceDiscount)
        #expect(discount < 0)
        #expect(abs(discount - (-0.25)) < 0.001)
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
