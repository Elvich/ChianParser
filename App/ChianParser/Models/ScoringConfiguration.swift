//
//  ScoringConfiguration.swift
//  ChianParser
//
//  Модель настроек скоринга и глобальных исключений (фильтрации) в SwiftData.
//

import Foundation
import SwiftData

@Model
final class ScoringConfiguration {
    @Attribute(.unique) var id: UUID = UUID()
    
    // Переключатели функций (Feature Toggles)
    var isCustomAreaScoreEnabled: Bool = true
    var isPercentileBenchmarkEnabled: Bool = true
    
    // Глобальные правила фильтрации (Global Filtering Rules)
    var excludeStudios: Bool = true
    var excludeApartments: Bool = true
    
    // Параметры бенчмаркинга (Benchmarking Parameters)
    var targetPercentile: Double = 0.80 // По умолчанию 80-й перцентиль (верхняя граница рынка)
    
    // Настраиваемые веса скоринга (Configurable Score Weights)
    var priceScoreWeight: Int = 40
    var metroProximityWeight: Int = 25
    var locationFloorWeight: Int = 20
    var areaScoreWeight: Int = 15
    
    init(
        id: UUID = UUID(),
        isCustomAreaScoreEnabled: Bool = true,
        isPercentileBenchmarkEnabled: Bool = true,
        excludeStudios: Bool = true,
        excludeApartments: Bool = true,
        targetPercentile: Double = 0.80,
        priceScoreWeight: Int = 40,
        metroProximityWeight: Int = 25,
        locationFloorWeight: Int = 20,
        areaScoreWeight: Int = 15
    ) {
        self.id = id
        self.isCustomAreaScoreEnabled = isCustomAreaScoreEnabled
        self.isPercentileBenchmarkEnabled = isPercentileBenchmarkEnabled
        self.excludeStudios = excludeStudios
        self.excludeApartments = excludeApartments
        self.targetPercentile = targetPercentile
        self.priceScoreWeight = priceScoreWeight
        self.metroProximityWeight = metroProximityWeight
        self.locationFloorWeight = locationFloorWeight
        self.areaScoreWeight = areaScoreWeight
    }
}

extension ModelContext {
    func fetchOrCreateScoringConfiguration() -> ScoringConfiguration {
        let descriptor = FetchDescriptor<ScoringConfiguration>()
        if let config = (try? fetch(descriptor))?.first {
            return config
        }
        let newConfig = ScoringConfiguration()
        insert(newConfig)
        try? save()
        return newConfig
    }
}
