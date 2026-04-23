//
//  FlipScoreResult.swift
//  ChianParser
//
//  Models for flip analysis scoring system.
//

import SwiftUI

// MARK: - Demand Level

enum DemandLevel {
    case noData
    case low        // < threshold1 views/day
    case moderate   // threshold1..<threshold2
    case market     // threshold2..<threshold3
    case hot        // >= threshold3

    var label: String {
        switch self {
        case .noData:   return "Нет данных"
        case .low:      return "Низкий спрос"
        case .moderate: return "Умеренный"
        case .market:   return "Рыночный"
        case .hot:      return "Горячий"
        }
    }

    var icon: String {
        switch self {
        case .noData:   return "questionmark.circle"
        case .low:      return "tortoise"
        case .moderate: return "gauge.with.dots.needle.33percent"
        case .market:   return "gauge.with.dots.needle.67percent"
        case .hot:      return "flame.fill"
        }
    }

    var color: Color {
        switch self {
        case .noData:   return .secondary
        case .low:      return .gray
        case .moderate: return .yellow
        case .market:   return .orange
        case .hot:      return .red
        }
    }
}

// MARK: - Flip Grade

enum FlipGrade {
    case excellent  // 70+
    case good       // 55+
    case average    // 40+
    case weak       // < 40

    init(score: Int) {
        switch score {
        case 70...: self = .excellent
        case 55...: self = .good
        case 40...: self = .average
        default:    self = .weak
        }
    }

    var label: String {
        switch self {
        case .excellent: return "Отличная"
        case .good:      return "Хорошая"
        case .average:   return "Средняя"
        case .weak:      return "Слабая"
        }
    }

    var icon: String {
        switch self {
        case .excellent: return "star.fill"
        case .good:      return "hand.thumbsup.fill"
        case .average:   return "minus.circle"
        case .weak:      return "xmark.circle"
        }
    }

    var color: Color {
        switch self {
        case .excellent: return .green
        case .good:      return .blue
        case .average:   return .orange
        case .weak:      return .red
        }
    }
}

// MARK: - Demand Thresholds

struct DemandThresholds {
    var moderate: Int   // views/day to reach "moderate"
    var market: Int     // views/day to reach "market"
    var hot: Int        // views/day to reach "hot"

    static let `default` = DemandThresholds(moderate: 50, market: 100, hot: 200)
}

// MARK: - Flip Score Result

struct FlipScoreResult {
    // Overall score 0-100
    let totalScore: Int

    // Component scores
    let priceScore: Int  // max 40 — discount vs benchmark
    let metroScore: Int  // max 25 — proximity to metro
    let floorScore: Int  // max 20 — floor position
    let areaScore: Int   // max 15 — apartment area

    // Benchmark context
    let priceSqm: Double?        // calculated price per m² for this apartment
    let benchmarkSqm: Double?    // median price/m² from DB for this okrug
    let benchmarkOkrug: String?  // which okrug was used for benchmark
    let benchmarkSampleSize: Int // how many apartments were in the benchmark

    // Demand (separate from intrinsic score)
    let demandLevel: DemandLevel
    let viewsPerDay: Double?     // computed views/day

    var grade: FlipGrade { FlipGrade(score: totalScore) }

    /// Discount relative to benchmark, e.g. -0.12 means 12% below market
    var priceDiscount: Double? {
        guard let priceSqm, let benchmarkSqm, benchmarkSqm > 0 else { return nil }
        return (priceSqm - benchmarkSqm) / benchmarkSqm
    }
}
