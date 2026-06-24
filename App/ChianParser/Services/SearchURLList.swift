//
//  SearchURLList.swift
//  ChianParser
//
//  Manages the ordered list of search URLs persisted in AppStorage.
//  The parser cycles through the list infinitely while scraping is active.
//

import Foundation

enum SearchURLList {
    static let appStorageKey = "searchURLListJSON"

    static let defaultURLs: [String] = [
        "https://www.cian.ru/cat.php?deal_type=sale&district%5B0%5D=9&electronic_trading=2&engine_version=2&flat_share=2&floornl=1&foot_min=7&is_first_floor=0&minfloorn=5&offer_type=flat&only_foot=2&repair%5B0%5D=1&sort=price_object_order",
        "https://www.cian.ru/cat.php?deal_type=sale&district%5B0%5D=8&electronic_trading=2&engine_version=2&flat_share=2&floornl=1&foot_min=7&is_first_floor=0&minfloorn=5&offer_type=flat&only_foot=2&repair%5B0%5D=1&sort=price_object_order",
        "https://www.cian.ru/cat.php?deal_type=sale&district%5B0%5D=10&electronic_trading=2&engine_version=2&flat_share=2&floornl=1&foot_min=7&is_first_floor=0&minfloorn=5&offer_type=flat&only_foot=2&repair%5B0%5D=1&sort=price_object_order",
        "https://www.cian.ru/cat.php?deal_type=sale&district%5B0%5D=7&electronic_trading=2&engine_version=2&flat_share=2&floornl=1&foot_min=7&is_first_floor=0&minfloorn=5&offer_type=flat&only_foot=2&repair%5B0%5D=1&sort=price_object_order",
        "https://www.cian.ru/cat.php?deal_type=sale&district%5B0%5D=4&electronic_trading=2&engine_version=2&flat_share=2&floornl=1&foot_min=7&is_first_floor=0&minfloorn=5&offer_type=flat&only_foot=2&repair%5B0%5D=1&sort=price_object_order",
        "https://www.cian.ru/cat.php?deal_type=sale&district%5B0%5D=11&electronic_trading=2&engine_version=2&flat_share=2&floornl=1&foot_min=7&is_first_floor=0&minfloorn=5&offer_type=flat&only_foot=2&repair%5B0%5D=1&sort=price_object_order",
        "https://www.cian.ru/cat.php?deal_type=sale&district%5B0%5D=6&electronic_trading=2&engine_version=2&flat_share=2&floornl=1&foot_min=7&is_first_floor=0&minfloorn=5&offer_type=flat&only_foot=2&repair%5B0%5D=1&sort=price_object_order",
        "https://www.cian.ru/cat.php?deal_type=sale&district%5B0%5D=1&electronic_trading=2&engine_version=2&flat_share=2&floornl=1&foot_min=7&is_first_floor=0&minfloorn=5&offer_type=flat&only_foot=2&repair%5B0%5D=1&sort=price_object_order"
    ]

    static var defaultJSON: String { encode(defaultURLs) }

    static func decode(from json: String) -> [String] {
        guard let data = json.data(using: .utf8),
              let urls = try? JSONDecoder().decode([String].self, from: data) else {
            return defaultURLs
        }
        return urls
    }

    static func encode(_ urls: [String]) -> String {
        guard let data = try? JSONEncoder().encode(urls),
              let string = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return string
    }

    /// Extracts a short human-readable label from a Cian search URL.
    /// Uses the district parameter if present, otherwise falls back to the host.
    static func shortLabel(for urlString: String) -> String {
        guard let components = URLComponents(string: urlString),
              let districtItem = components.queryItems?.first(where: { $0.name == "district[0]" || $0.name.hasPrefix("district") }),
              let value = districtItem.value else {
            return URLComponents(string: urlString)?.host ?? urlString
        }
        return "Район \(value)"
    }
}
