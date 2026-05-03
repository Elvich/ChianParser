//
//  ApartmentStatus.swift
//  ChianParser
//
//  Workflow status for tracking apartment evaluation progress.
//

import SwiftUI

enum ApartmentStatus: String, Codable, CaseIterable, Identifiable {
    case new      = "new"      // Just found, not reviewed
    case study    = "study"    // Under analysis
    case call     = "call"     // Need to call seller
    case visit    = "visit"    // Scheduled/need to visit
    case calc     = "calc"     // Running deal calculations
    case deal     = "deal"     // Active deal in progress
    case deposit  = "deposit"  // Deposit paid — tracking only, hidden by default
    case waiting  = "waiting"  // Waiting for a condition
    case auction  = "auction"  // Listed as auction — excluded from analysis
    case ban      = "ban"      // Rejected / blacklisted

    var id: String { rawValue }

    var label: String {
        switch self {
        case .new:     return "Новая"
        case .study:   return "Изучение"
        case .call:    return "Звонок"
        case .visit:   return "Просмотр"
        case .calc:    return "Расчёт"
        case .deal:    return "Сделка"
        case .deposit: return "Залог"
        case .waiting: return "Ожидание"
        case .auction: return "Аукцион"
        case .ban:     return "Отклонена"
        }
    }

    var icon: String {
        switch self {
        case .new:     return "sparkle"
        case .study:   return "magnifyingglass"
        case .call:    return "phone"
        case .visit:   return "figure.walk"
        case .calc:    return "function"
        case .deal:    return "handshake"
        case .deposit: return "banknote"
        case .waiting: return "clock"
        case .auction: return "hammer"
        case .ban:     return "xmark.circle"
        }
    }

    var color: Color {
        switch self {
        case .new:     return .blue
        case .study:   return .cyan
        case .call:    return .orange
        case .visit:   return .purple
        case .calc:    return .yellow
        case .deal:    return .green
        case .deposit: return .teal
        case .waiting: return .gray
        case .auction: return .brown
        case .ban:     return .red
        }
    }

    /// Statuses visible by default in the filter.
    /// .deposit, .auction, .waiting and .ban are hidden by default.
    static let defaultVisible: Set<ApartmentStatus> = [.new, .study, .call, .visit, .calc, .deal]
}
