//
//  FlipAnalyzerProtocol.swift
//  ChianParser
//

import Foundation

protocol FlipAnalyzerProtocol: Sendable {
    /// Analyze a single apartment given a pre-computed benchmark context.
    nonisolated func analyze(apartment: Apartment, benchmark: BenchmarkContext, thresholds: DemandThresholds) -> FlipScoreResult

    /// Build a benchmark context from a collection of apartments using the target percentile (e.g. 0.8 for 80th percentile).
    func buildBenchmark(from apartments: [Apartment], targetPercentile: Double) -> BenchmarkContext

    /// Extract the Moscow okrug name from an address string (e.g. "ЮВАО", "ЦАО").
    nonisolated func extractOkrug(from address: String) -> String

    /// Extract the Moscow district (район) name from an address string (e.g. "Арбат", "Чертаново Северное").
    /// Returns nil when the address does not contain a "р-н …" fragment.
    nonisolated func extractDistrict(from address: String) -> String?
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

    /// Median price/m² per metro station. Same struct as okrug benchmark.
    let byMetro: [String: OkrugBenchmark]

    /// Per-district/okrug scores. Score -1 = banned (handled upstream).
    let districtScores: [String: Int]

    /// When true, district score is used instead of floor position for location score.
    let useDistrictScore: Bool

    /// Mode for calculating price benchmark.
    let benchmarkMode: BenchmarkMode

    /// When true, promoted apartments have their view counts penalized.
    let penalizePromotions: Bool

    /// When true, normalizes views for morning parsing according to a non-linear distribution curve.
    let extrapolateMorningViews: Bool

    /// When enabled, uses the liquidity-optimized bell curve for Area scoring.
    let useLiquidityAreaScore: Bool

    /// When true, Metro score (0-25) is replaced with a Views score based on demand level.
    let useViewsScoreInsteadOfMetro: Bool

    /// The target percentile used to calculate the benchmark (e.g., 0.8 for upper market).
    let targetPercentile: Double

    init(
        byOkrug: [String: OkrugBenchmark],
        byDistrict: [String: OkrugBenchmark] = [:],
        byMetro: [String: OkrugBenchmark] = [:],
        globalMedian: Double?,
        globalSampleSize: Int,
        districtScores: [String: Int] = [:],
        useDistrictScore: Bool = false,
        benchmarkMode: BenchmarkMode = .okrug,
        penalizePromotions: Bool = true,
        extrapolateMorningViews: Bool = true,
        useLiquidityAreaScore: Bool = false,
        useViewsScoreInsteadOfMetro: Bool = false,
        targetPercentile: Double = 0.5
    ) {
        self.byOkrug = byOkrug
        self.byDistrict = byDistrict
        self.byMetro = byMetro
        self.globalMedian = globalMedian
        self.globalSampleSize = globalSampleSize
        self.districtScores = districtScores
        self.useDistrictScore = useDistrictScore
        self.benchmarkMode = benchmarkMode
        self.penalizePromotions = penalizePromotions
        self.extrapolateMorningViews = extrapolateMorningViews
        self.useLiquidityAreaScore = useLiquidityAreaScore
        self.useViewsScoreInsteadOfMetro = useViewsScoreInsteadOfMetro
        self.targetPercentile = targetPercentile
    }

    static let empty = BenchmarkContext(byOkrug: [:], globalMedian: nil, globalSampleSize: 0)
}

enum BenchmarkMode: String {
    case okrug
    case district
    case smart
}

struct OkrugBenchmark {
    let medianPriceSqm: Double
    let sampleSize: Int
    let okrug: String
}
