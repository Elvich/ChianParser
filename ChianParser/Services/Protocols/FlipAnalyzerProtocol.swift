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
}

/// Pre-computed market benchmark derived from a DB snapshot.
struct BenchmarkContext {
    /// Median price/m² per okrug (city district).  Key is the okrug name.
    let byOkrug: [String: OkrugBenchmark]

    /// Global Moscow fallback when okrug data is unavailable.
    let globalMedian: Double?
    let globalSampleSize: Int

    static let empty = BenchmarkContext(byOkrug: [:], globalMedian: nil, globalSampleSize: 0)
}

struct OkrugBenchmark {
    let medianPriceSqm: Double
    let sampleSize: Int
    let okrug: String
}
