//
//  ApartmentsProviderProtocol.swift
//  ChianParser
//

import Foundation
import SwiftData

@MainActor
protocol ApartmentsProviderProtocol {
    /// Получает список квартир. В локальной версии используется переданный контекст.
    func fetchApartments(using context: ModelContext) async throws -> [Apartment]
}
