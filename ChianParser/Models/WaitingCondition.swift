//
//  WaitingCondition.swift
//  ChianParser
//
//  Condition that, when met, automatically moves an apartment from .waiting back to .study.
//  Stored as a JSON string in SwiftData (structs cannot be persisted directly).
//

import Foundation

struct WaitingCondition: Codable, Equatable {

    // MARK: - Condition Type

    enum ConditionType: String, Codable, CaseIterable {
        case priceBelow  // Price drops below a threshold (absolute ₽)
        case scoreAbove  // FlipScore rises above a threshold (0-100)
        case timer       // Wait N days from now

        var label: String {
            switch self {
            case .priceBelow: return "Цена ниже"
            case .scoreAbove: return "Score выше"
            case .timer:      return "Через дней"
            }
        }
    }

    // MARK: - Properties

    var type: ConditionType
    var threshold: Double?   // Used for priceBelow (₽) and scoreAbove (pts)
    var targetDate: Date?    // Used for timer — computed from days at creation
    var note: String = ""

    // MARK: - Helpers

    /// Human-readable summary of the condition
    var summary: String {
        switch type {
        case .priceBelow:
            if let t = threshold {
                let formatted = Int(t).formatted(.number)
                return "Цена < \(formatted) ₽"
            }
            return "Цена снизится"
        case .scoreAbove:
            if let t = threshold {
                return "Score > \(Int(t))"
            }
            return "Score вырастет"
        case .timer:
            if let date = targetDate {
                let formatter = DateFormatter()
                formatter.dateStyle = .short
                formatter.timeStyle = .none
                return "До \(formatter.string(from: date))"
            }
            return "По таймеру"
        }
    }

    /// Returns true if the condition is currently satisfied.
    func isMet(currentPrice: Int, currentScore: Int) -> Bool {
        switch type {
        case .priceBelow:
            guard let t = threshold else { return false }
            return Double(currentPrice) < t
        case .scoreAbove:
            guard let t = threshold else { return false }
            return Double(currentScore) > t
        case .timer:
            guard let date = targetDate else { return false }
            return Date() >= date
        }
    }
}
