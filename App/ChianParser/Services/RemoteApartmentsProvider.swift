//
//  RemoteApartmentsProvider.swift
//  ChianParser
//

import Foundation
import SwiftData

@MainActor
final class RemoteApartmentsProvider: ApartmentsProviderProtocol {
    
    struct ApartmentDTO: Codable {
        let id: String
        let title: String
        let price: Int
        let url: String
        let address: String
        
        let area: Double?
        let livingArea: Double?
        let kitchenArea: Double?
        let floor: Int?
        let totalFloors: Int?
        let roomsCount: Int?
        let houseMaterial: String?
        let buildingType: String?
        let yearBuilt: Int?
        
        // Моки флиппинг-калькулятора
        let repairCost: Int?
        let targetSellPrice: Int?
        let taxes: Int?
        let netProfit: Int?
        let roi: Double?
        
        let viewsHistoryJSON: String?
        
        enum CodingKeys: String, CodingKey {
            case id, title, price, url, address
            case area, livingArea, kitchenArea, floor, totalFloors, roomsCount
            case houseMaterial, buildingType, yearBuilt
            case repairCost, targetSellPrice, taxes, netProfit, roi
            case viewsHistoryJSON = "views_history_json"
        }
    }
    
    func fetchApartments(using context: ModelContext) async throws -> [Apartment] {
        guard let url = URL(string: "http://localhost:8000/api/v1/apartments") else {
            return []
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        let dtos = try JSONDecoder().decode([ApartmentDTO].self, from: data)
        
        let apartments = dtos.map { dto in
            let apt = Apartment(id: dto.id, title: dto.title, price: dto.price, url: dto.url, address: dto.address)
            apt.area = dto.area
            apt.livingArea = dto.livingArea
            apt.kitchenArea = dto.kitchenArea
            apt.floor = dto.floor
            apt.totalFloors = dto.totalFloors
            apt.roomsCount = dto.roomsCount
            apt.houseMaterial = dto.houseMaterial
            apt.buildingType = dto.buildingType
            apt.yearBuilt = dto.yearBuilt
            
            apt.repairCost = dto.repairCost
            apt.targetSellPrice = dto.targetSellPrice
            apt.taxes = dto.taxes
            apt.netProfit = dto.netProfit
            apt.roi = dto.roi
            apt.viewsHistoryJSON = dto.viewsHistoryJSON
            
            return apt
        }
        
        return apartments
    }
}
