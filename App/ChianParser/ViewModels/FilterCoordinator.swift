//
//  FilterCoordinator.swift
//  ChianParser
//
//  Created by Gemini CLI.
//  Coordinates active filtering criteria for the apartment dataset.
//

import Foundation
import Observation

@Observable
final class FilterCoordinator {

    // MARK: - Transient UI Filters

    var activeStatusFilters: Set<ApartmentStatus> = ApartmentStatus.defaultVisible
    var activeOkrugFilters: Set<String> = []
    var activeRoomFilters: Set<Int> = []
    var activeDistrictFilters: Set<String> = []

    // MARK: - Persistent Filter Settings (synced from AppStorage)

    var requireDetailParsed: Bool = false
    var hideStudios: Bool = false
    var hideApartments: Bool = false
    var showAuctions: Bool = false
    var showDeposits: Bool = false
    var showOnlyPopular: Bool = false
    var maxMetroDistance: Int = 0
    var metroWalkOnly: Bool = false
    var minBuildingFloors: Int = 0

    // MARK: - Toggle Actions

    func toggleStatusFilter(_ status: ApartmentStatus) {
        if activeStatusFilters.contains(status) {
            activeStatusFilters.remove(status)
        } else {
            activeStatusFilters.insert(status)
        }
    }

    func toggleOkrugFilter(_ okrug: String) {
        if activeOkrugFilters.contains(okrug) {
            activeOkrugFilters.remove(okrug)
        } else {
            activeOkrugFilters.insert(okrug)
        }
    }

    func toggleRoomFilter(_ bucket: Int) {
        if activeRoomFilters.contains(bucket) {
            activeRoomFilters.remove(bucket)
        } else {
            activeRoomFilters.insert(bucket)
        }
    }

    func toggleDistrictFilter(_ district: String) {
        if activeDistrictFilters.contains(district) {
            activeDistrictFilters.remove(district)
        } else {
            activeDistrictFilters.insert(district)
        }
    }

    // MARK: - Evaluation

    /// Evaluates if a given apartment matches all active filters.
    func shouldKeep(
        apartment: Apartment,
        metroBanlist: Set<String>,
        districtScores: [String: Int],
        useDistrictScore: Bool
    ) -> Bool {
        // Status filter
        guard activeStatusFilters.contains(apartment.status) else { return false }

        // Require detail parsed
        if requireDetailParsed && !apartment.isDetailedParsed { return false }
        
        // Show only popular
        if showOnlyPopular && (apartment.viewsTotal ?? 0) < 200 { return false }

        // Hide studios/apartments
        if hideStudios && apartment.isStudio { return false }
        if hideApartments && apartment.isApartments { return false }

        // Auctions/Deposits
        if apartment.isAuction && !showAuctions { return false }
        if apartment.isDepositPaid && !showDeposits { return false }

        // Metro banlist
        if let metro = apartment.metro, metroBanlist.contains(metro) { return false }

        // Building height limits
        if minBuildingFloors > 0, let floors = apartment.totalFloors, floors < minBuildingFloors { return false }

        // Metro distance limits
        if maxMetroDistance > 0, let dist = apartment.metroDistance, dist > maxMetroDistance { return false }

        // Metro transport type limits
        if metroWalkOnly, apartment.metroTransportType == "transport" { return false }

        // District/Okrug ban (-1 score)
        if let district = apartment.district, (districtScores[district] ?? 0) < 0 { return false }
        if let okrug = apartment.okrug, (districtScores[okrug] ?? 0) < 0 { return false }

        // Okrug selection filter
        if !activeOkrugFilters.isEmpty {
            guard let okrug = apartment.okrug, activeOkrugFilters.contains(okrug) else { return false }
        }

        // Room count selection filter
        if !activeRoomFilters.isEmpty {
            // Bucket 0 represents Studio
            if !activeRoomFilters.contains(0) && apartment.isStudio { return false }
            if let rooms = apartment.roomsCount {
                guard activeRoomFilters.contains(min(rooms, 4)) else { return false }
            }
        }

        // District selection filter (only active when using district score)
        if useDistrictScore && !activeDistrictFilters.isEmpty {
            guard let district = apartment.district, activeDistrictFilters.contains(district) else { return false }
        }

        return true
    }
}
