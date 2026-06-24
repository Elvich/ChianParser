//
//  SelectorsManagerProtocol.swift
//  ChianParser
//
//  Created by Antigravity on 20.05.2026.
//

import Foundation

public struct SearchSelectorsConfig: Codable, Sendable {
    public let cardSelector: String
    public let linkSelector: String
    public let linkPattern: String
    public let titleKeys: [String]
    public let priceKeys: [String]
    public let geoKeys: [String]
    public let metroKeys: [String]

    public init(
        cardSelector: String,
        linkSelector: String,
        linkPattern: String,
        titleKeys: [String],
        priceKeys: [String],
        geoKeys: [String],
        metroKeys: [String]
    ) {
        self.cardSelector = cardSelector
        self.linkSelector = linkSelector
        self.linkPattern = linkPattern
        self.titleKeys = titleKeys
        self.priceKeys = priceKeys
        self.geoKeys = geoKeys
        self.metroKeys = metroKeys
    }
}

public struct DetailSelectorsConfig: Codable, Sendable {
    public let jsonSelectors: [String]
    public let mainCharacteristicsSelectors: [String]
    public let mainCharacteristicsTitleSelector: String
    public let mainCharacteristicsValueSelector: String
    public let alternativeCharacteristicsSelectors: String
    public let descriptionSelectors: [String]
    public let addressSelectors: [String]
    public let metroSelectors: [String]
    public let sellerSelectors: [String]

    public init(
        jsonSelectors: [String],
        mainCharacteristicsSelectors: [String],
        mainCharacteristicsTitleSelector: String,
        mainCharacteristicsValueSelector: String,
        alternativeCharacteristicsSelectors: String,
        descriptionSelectors: [String],
        addressSelectors: [String],
        metroSelectors: [String],
        sellerSelectors: [String]
    ) {
        self.jsonSelectors = jsonSelectors
        self.mainCharacteristicsSelectors = mainCharacteristicsSelectors
        self.mainCharacteristicsTitleSelector = mainCharacteristicsTitleSelector
        self.mainCharacteristicsValueSelector = mainCharacteristicsValueSelector
        self.alternativeCharacteristicsSelectors = alternativeCharacteristicsSelectors
        self.descriptionSelectors = descriptionSelectors
        self.addressSelectors = addressSelectors
        self.metroSelectors = metroSelectors
        self.sellerSelectors = sellerSelectors
    }
}

public struct SelectorsConfig: Codable, Sendable {
    public let search: SearchSelectorsConfig
    public let detail: DetailSelectorsConfig

    public init(search: SearchSelectorsConfig, detail: DetailSelectorsConfig) {
        self.search = search
        self.detail = detail
    }
}

public protocol SelectorsManagerProtocol: Sendable {
    var config: SelectorsConfig { get }
    func reloadConfig()
    @discardableResult
    func updateConfig(with jsonString: String) -> Bool
}
