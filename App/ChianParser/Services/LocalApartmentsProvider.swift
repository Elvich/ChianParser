//
//  LocalApartmentsProvider.swift
//  ChianParser
//

import Foundation
import SwiftData

@MainActor
final class LocalApartmentsProvider: ApartmentsProviderProtocol {
    func fetchApartments(using context: ModelContext) async throws -> [Apartment] {
        let descriptor = FetchDescriptor<Apartment>()
        return try context.fetch(descriptor)
    }
}
