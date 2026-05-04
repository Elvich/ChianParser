//
//  FlipAnalyzerProtocol.swift
//  ChianParser
//

import Foundation

protocol FlipAnalyzerProtocol {
    /// Analyze a single apartment given a pre-computed benchmark context.
    func analyze(apartment: Apartment, benchmark: BenchmarkContext, thresholds: DemandThresholds) -> FlipScoreResult

    /// Build a benchmark context from a collection of apartments (computes median price/m² per okrug).
    func buildBenchmark(from apartments: [Apartment]) -> BenchmarkContext

    /// Extract the Moscow okrug name from an address string (e.g. "ЮВАО", "ЦАО").
    func extractOkrug(from address: String) -> String

    /// Extract the Moscow district (район) name from an address string (e.g. "Арбат", "Чертаново Северное").
    /// Returns nil when the address does not contain a "р-н …" fragment.
    func extractDistrict(from address: String) -> String?
}

/// Pre-computed market benchmark derived from a DB snapshot.
struct BenchmarkContext {
    /// Median price/m² per okrug (city district).  Key is the okrug name.
    let byOkrug: [String: OkrugBenchmark]

    /// Global Moscow fallback when okrug data is unavailable.
    let globalMedian: Double?
    let globalSampleSize: Int

    /// Median price/m² per district (район). Same struct as okrug benchmark.
    let byDistrict: [String: OkrugBenchmark]

    /// Per-district/okrug scores. Score -1 = banned (handled upstream).
    let districtScores: [String: Int]

    /// When true, district score is used instead of floor position for location score.
    let useDistrictScore: Bool

    /// When true, district-level median is used for price benchmark instead of okrug-level.
    let useDistrictBenchmark: Bool

    init(
        byOkrug: [String: OkrugBenchmark],
        byDistrict: [String: OkrugBenchmark] = [:],
        globalMedian: Double?,
        globalSampleSize: Int,
        districtScores: [String: Int] = [:],
        useDistrictScore: Bool = false,
        useDistrictBenchmark: Bool = false
    ) {
        self.byOkrug = byOkrug
        self.byDistrict = byDistrict
        self.globalMedian = globalMedian
        self.globalSampleSize = globalSampleSize
        self.districtScores = districtScores
        self.useDistrictScore = useDistrictScore
        self.useDistrictBenchmark = useDistrictBenchmark
    }

    static let empty = BenchmarkContext(byOkrug: [:], globalMedian: nil, globalSampleSize: 0)
}

struct OkrugBenchmark {
    let medianPriceSqm: Double
    let sampleSize: Int
    let okrug: String
}
