//
//  ParserActor.swift
//  ChianParser
//
//  Created by Gemini CLI.
//  A background actor for safe and performant parsing of Cian search results
//  and persistence using SwiftData's @ModelActor pattern.
//

import Foundation
import SwiftData

@ModelActor
actor ParserActor {

    var selectorsManager: any SelectorsManagerProtocol = SelectorsManager()
    // `var` with default so @ModelActor's synthesised conformance inits compile;
    // always overridden by the designated init below.
    var powerManager: any PowerManagementServiceProtocol = PowerManagementService()

    init(
        modelContainer: ModelContainer,
        selectorsManager: any SelectorsManagerProtocol,
        powerManager: any PowerManagementServiceProtocol
    ) {
        self.selectorsManager = selectorsManager
        self.powerManager = powerManager
        self.modelContainer = modelContainer
        self.modelExecutor = DefaultSerialModelExecutor(modelContext: ModelContext(modelContainer))
    }

    /// Parses search results on a background thread, updates existing apartments,
    /// inserts new ones, and returns the identifiers and counts of the operations.
    func parseAndSaveSearchPage(
        _ html: String,
        targetPercentile: Double
    ) throws -> (newlyInsertedIDs: [PersistentIdentifier], newCount: Int, updatedCount: Int, totalCount: Int) {
        powerManager.startActivity(reason: "Parsing Cian catalog page")
        defer { powerManager.endActivity() }
        
        let extractor = CianDataExtractor(selectorsManager: selectorsManager)
        let foundApartments = extractor.extractData(from: html)
        guard !foundApartments.isEmpty else {
            return ([], 0, 0, 0)
        }
        
        var newCount = 0
        var updatedCount = 0
        var newlyInsertedIDs: [PersistentIdentifier] = []
        
        let analyzer = FlipAnalyzer()
        
        for apartment in foundApartments {
            autoreleasepool {
                let id = apartment.id
                let fetchDescriptor = FetchDescriptor<Apartment>(predicate: #Predicate { $0.id == id })
                
                if let existing = try? modelContext.fetch(fetchDescriptor).first {
                    if updateExistingApartment(existing, with: apartment) {
                        updatedCount += 1
                    }
                    if existing.okrug == nil {
                        existing.okrug = analyzer.extractOkrug(from: existing.address)
                    }
                    if existing.district == nil {
                        existing.district = analyzer.extractDistrict(from: existing.address)
                    }
                } else if apartment.price > 0 {
                    apartment.okrug = analyzer.extractOkrug(from: apartment.address)
                    apartment.district = analyzer.extractDistrict(from: apartment.address)
                    
                    modelContext.insert(apartment)
                    // Save context immediately to assign persistent identifier
                    try? modelContext.save()
                    newlyInsertedIDs.append(apartment.persistentModelID)
                    newCount += 1
                }
            }
        }
        
        if newCount > 0 || updatedCount > 0 {
            try modelContext.save()
        }
        
        return (newlyInsertedIDs, newCount, updatedCount, foundApartments.count)
    }

    private func updateExistingApartment(_ existing: Apartment, with new: Apartment) -> Bool {
        var hasChanges = false
        
        // Always mark as seen in this search run
        existing.lastSeenInSearch = Date()
        
        // Only update price if the new value is valid (> 0).
        if new.price > 0 && existing.price != new.price {
            existing.price = new.price
            existing.priceHistory.append(PricePoint(price: new.price, date: Date()))
            existing.isDetailedParsed = false
            hasChanges = true
            print("💰 Цена изменилась для квартиры \(existing.id): \(existing.price) → \(new.price)")
        }
        
        if existing.title != new.title { existing.title = new.title; hasChanges = true }
        if existing.address != new.address { existing.address = new.address; hasChanges = true }
        if existing.area != new.area { existing.area = new.area; hasChanges = true }
        if existing.floor != new.floor { existing.floor = new.floor; hasChanges = true }
        if existing.totalFloors != new.totalFloors { existing.totalFloors = new.totalFloors; hasChanges = true }
        if existing.houseMaterial != new.houseMaterial { existing.houseMaterial = new.houseMaterial; hasChanges = true }
        if existing.metro != new.metro { existing.metro = new.metro; hasChanges = true }
        if existing.metroDistance != new.metroDistance { existing.metroDistance = new.metroDistance; hasChanges = true }
        if existing.metroTransportType != new.metroTransportType { existing.metroTransportType = new.metroTransportType; hasChanges = true }
        
        if let newViews = new.viewsToday, existing.viewsToday != newViews {
            existing.viewsToday = newViews; hasChanges = true
        }
        if let newTotal = new.viewsTotal, existing.viewsTotal != newTotal {
            existing.viewsTotal = newTotal; hasChanges = true
        }
        
        if hasChanges { existing.lastUpdate = Date() }
        
        return hasChanges
    }
}
