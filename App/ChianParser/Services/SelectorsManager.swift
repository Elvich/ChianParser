//
//  SelectorsManager.swift
//  ChianParser
//
//  Created by Antigravity on 20.05.2026.
//

import Foundation

public final class SelectorsManager: SelectorsManagerProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var _config: SelectorsConfig



    public var config: SelectorsConfig {
        lock.lock()
        defer { lock.unlock() }
        return _config
    }

    public nonisolated static let fallbackConfig = SelectorsConfig(
        search: SearchSelectorsConfig(
            cardSelector: "article",
            linkSelector: "a[href]",
            linkPattern: "/flat/",
            titleKeys: ["TitleComponent", "OfferTitle"],
            priceKeys: ["MainPrice", "ContentRow"],
            geoKeys: ["GeoLabel"],
            metroKeys: ["SpecialGeo"]
        ),
        detail: DetailSelectorsConfig(
            jsonSelectors: [
                "script#__NEXT_DATA__",
                "script[type='application/json']",
                "script[id*='__']",
                "script:containsData(offerData)",
                "script:containsData(cianAd)"
            ],
            mainCharacteristicsSelectors: [
                "[data-name='OfferSummaryInfoItem']",
                "[data-testid='object-summary-info-item']",
                ".a10a3f92e9--item--_ipjK",
                "[class*='item']"
            ],
            mainCharacteristicsTitleSelector: "[data-mark='OfferSummaryInfoItem/Title']",
            mainCharacteristicsValueSelector: "[data-mark='OfferSummaryInfoItem/Value']",
            alternativeCharacteristicsSelectors: "[data-name='GeneralInformation'] li, [data-name='AboutFlatItem'], .object_descr_params li",
            descriptionSelectors: [
                "[data-name='Description']",
                "[itemprop='description']",
                ".description_text",
                "[class*='description']"
            ],
            addressSelectors: [
                "[data-name='Geo']",
                "[itemprop='address']",
                "[class*='address']",
                "h1[itemprop='name']"
            ],
            metroSelectors: [
                "[data-name='UndergroundStation']",
                "[class*='underground']",
                "[class*='metro']",
                "a[href*='metro']"
            ],
            sellerSelectors: [
                "[data-automation='agent-info']",
                "[data-automation='seller-info']",
                "[class*='--agent-info--']",
                "[class*='--owner-info--']"
            ]
        )
    )

    public nonisolated init() {
        self._config = Self.fallbackConfig
        reloadConfig()
    }

    public func reloadConfig() {
        lock.lock()
        defer { lock.unlock() }

        guard let url = Bundle.main.url(forResource: "SelectorsConfig", withExtension: "json") else {
            print("⚠️ SelectorsConfig.json not found in Bundle, using hardcoded fallback config")
            self._config = Self.fallbackConfig
            return
        }

        do {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode(SelectorsConfig.self, from: data)
            self._config = decoded
            print("✅ Successfully loaded HTML/CSS selectors from SelectorsConfig.json")
        } catch {
            print("❌ Failed to decode SelectorsConfig.json: \(error). Falling back to hardcoded defaults.")
            self._config = Self.fallbackConfig
        }
    }

    @discardableResult
    public func updateConfig(with jsonString: String) -> Bool {
        guard let data = jsonString.data(using: .utf8) else {
            print("❌ Invalid JSON string provided to updateConfig")
            return false
        }

        do {
            let decoded = try JSONDecoder().decode(SelectorsConfig.self, from: data)
            lock.lock()
            self._config = decoded
            lock.unlock()
            print("✅ Dynamic HTML/CSS selectors updated successfully")
            return true
        } catch {
            print("❌ Failed to decode dynamic config updates: \(error)")
            return false
        }
    }
}
