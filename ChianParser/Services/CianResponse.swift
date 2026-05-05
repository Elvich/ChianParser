//
//  CianResponse.swift
//  ChianParser
//
//  Парсер данных Циан: JSON (приоритет) + HTML (fallback)
//

import Foundation
import SwiftSoup

// MARK: - Главный класс для извлечения данных
final class CianDataExtractor {
    
    // MARK: - Единая точка входа
    /// Извлекает данные о квартирах.
    /// Принимает либо "__NEXT_DATA__:<json>" (прямой JSON из JS), либо полный HTML.
    /// Приоритет: прямой JSON → JSON из HTML → HTML парсинг
    static func extractData(from input: String) -> [Apartment] {
        // Fast path: XHR/fetch intercepted API response
        let apiPrefix = "__API__:"
        if input.hasPrefix(apiPrefix) {
            let jsonString = String(input.dropFirst(apiPrefix.count))
            if let apartments = parseAPIResponseJSON(jsonString), !apartments.isEmpty {
                print("✅ Данные извлечены из перехваченного API-ответа (\(apartments.count) шт.)")
                return apartments
            }
            // Maybe the string is actually __NEXT_DATA__ format — try it
            if let apartments = parseNextDataJSON(jsonString), !apartments.isEmpty {
                return apartments
            }
            print("⚠️ API-ответ получен но не распознан")
            return []
        }

        // Fast path: CianWebView extracted __NEXT_DATA__ directly via JS
        let prefix = "__NEXT_DATA__:"
        if input.hasPrefix(prefix) {
            let jsonString = String(input.dropFirst(prefix.count))
            if let apartments = parseNextDataJSON(jsonString), !apartments.isEmpty {
                print("✅ Данные извлечены из JSON (__NEXT_DATA__, прямой JS)")
                return apartments
            }
            print("⚠️ __NEXT_DATA__ получен но не распознан — возвращаем пустой результат")
            return []
        }

        // Slow path: full HTML received — try JSON first, then HTML fallback
        if let apartments = tryExtractFromJSON(input) {
            print("✅ Данные извлечены из JSON (__NEXT_DATA__, через HTML)")
            return apartments
        }

        print("⚠️ JSON не найден, используем HTML парсинг (fallback)")
        return extractOffersFromHTML(from: input)
    }
    
    // MARK: - JSON Extraction

    /// Parse a raw Cian API response JSON (captured via XHR/fetch interception).
    /// Cian API responses contain offer arrays under various paths — we search flexibly.
    private static func parseAPIResponseJSON(_ jsonString: String) -> [Apartment]? {
        guard let jsonData = jsonString.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: jsonData) else {
            return nil
        }

        // Try to find an array of offer objects containing "bargainTerms"
        let results = findOffersArray(in: root)
        guard !results.isEmpty else {
            print("⚠️ API JSON: массив объявлений не найден")
            return nil
        }

        print("✅ API JSON: \(results.count) объявлений")

        var apartments: [Apartment] = []
        for item in results {
            guard let idNum = extractNumber(item["id"]) else { continue }
            let id = "\(idNum)"

            let title = (item["title"] as? String)
                ?? (item["fullName"] as? String)
                ?? "Квартира \(id)"

            let bargainTerms = item["bargainTerms"] as? [String: Any]
            let price = extractInt(bargainTerms?["price"])
                ?? extractInt(bargainTerms?["priceTotal"])
                ?? 0

            let fullUrl = (item["fullUrl"] as? String) ?? ""

            var address = ""
            if let geo = item["geo"] as? [String: Any] {
                if let addressArray = geo["address"] as? [[String: Any]] {
                    address = addressArray.compactMap {
                        ($0["fullName"] as? String) ?? ($0["title"] as? String) ?? ($0["name"] as? String)
                    }.joined(separator: ", ")
                }
                if address.isEmpty {
                    address = (geo["userInputAddress"] as? String) ?? (geo["displayAddress"] as? String) ?? ""
                }
            }
            if address.isEmpty {
                address = (item["displayAddress"] as? String) ?? (item["address"] as? String) ?? ""
            }

            let apartment = Apartment(
                id: id,
                title: title,
                price: price,
                url: fullUrl,
                address: address.isEmpty ? "Адрес не указан" : address
            )

            apartment.area = extractDouble(item["totalArea"])
            apartment.roomsCount = extractInt(item["roomsCount"])
            apartment.floor = extractInt(item["floorNumber"])

            if let building = item["building"] as? [String: Any] {
                apartment.totalFloors = extractInt(building["floorsCount"])
                apartment.houseMaterial = building["materialType"] as? String
            }

            if let geo = item["geo"] as? [String: Any],
               let undergrounds = geo["undergrounds"] as? [[String: Any]],
               let nearest = undergrounds.first {
                apartment.metro = (nearest["name"] as? String) ?? (nearest["title"] as? String)
                if let time = extractInt(nearest["travelTime"]) ?? extractInt(nearest["time"]) ?? extractInt(nearest["distance"]), time > 0 {
                    apartment.metroDistance = time
                }
                apartment.metroTransportType = (nearest["travelType"] as? String) ?? (nearest["transportType"] as? String)
            }

            detectApartmentType(apartment: apartment, item: item)
            apartments.append(apartment)
        }

        return apartments.isEmpty ? nil : apartments
    }

    /// Recursively search any JSON value for an array of offer dicts (containing "bargainTerms").
    private static func findOffersArray(in value: Any, depth: Int = 0) -> [[String: Any]] {
        guard depth < 6 else { return [] }

        if let array = value as? [[String: Any]] {
            // Check if this is an array of offer objects
            let hasOffers = array.contains { $0["bargainTerms"] != nil || $0["id"] != nil && $0["fullUrl"] != nil }
            if hasOffers { return array }
        }

        if let dict = value as? [String: Any] {
            // Prioritise known Cian API keys
            for key in ["offers", "results", "items", "data", "offersSerialized", "list"] {
                if let child = dict[key] {
                    let found = findOffersArray(in: child, depth: depth + 1)
                    if !found.isEmpty { return found }
                }
            }
            // Generic search over all values
            for (_, child) in dict {
                let found = findOffersArray(in: child, depth: depth + 1)
                if !found.isEmpty { return found }
            }
        }

        return []
    }

    /// Parse a raw __NEXT_DATA__ JSON string (already extracted from the script tag).
    private static func parseNextDataJSON(_ jsonString: String) -> [Apartment]? {
        guard let jsonData = jsonString.data(using: .utf8),
              let jsonObject = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            return nil
        }
        return parseNextDataObject(jsonObject)
    }

    /// Extract __NEXT_DATA__ from full HTML via SwiftSoup, then parse.
    private static func tryExtractFromJSON(_ html: String) -> [Apartment]? {
        do {
            let doc = try SwiftSoup.parse(html)
            guard let jsonTag = try doc.select("script#__NEXT_DATA__").first() else { return nil }
            return parseNextDataJSON(jsonTag.data())
        } catch {
            print("❌ SwiftSoup error: \(error)")
            return nil
        }
    }

    /// Navigate props → pageProps → initialState → offers → results and build Apartment objects.
    private static func parseNextDataObject(_ jsonObject: [String: Any]) -> [Apartment]? {
        guard let props = jsonObject["props"] as? [String: Any] else {
            print("⚠️ SEARCH JSON: нет 'props'"); return nil
        }
        guard let pageProps = props["pageProps"] as? [String: Any] else {
            print("⚠️ SEARCH JSON: нет 'pageProps'"); return nil
        }
        guard let initialState = pageProps["initialState"] as? [String: Any] else {
            print("⚠️ SEARCH JSON: нет 'initialState', ключи pageProps:", Array(pageProps.keys).sorted().prefix(8).joined(separator: ", "))
            return nil
        }
        guard let offers = initialState["offers"] as? [String: Any] else {
            print("⚠️ SEARCH JSON: нет 'offers', ключи initialState:", Array(initialState.keys).sorted().prefix(12).joined(separator: ", "))
            return nil
        }
        guard let results = offers["results"] as? [[String: Any]] else {
            print("⚠️ SEARCH JSON: нет 'results', ключи offers:", Array(offers.keys).sorted().prefix(8).joined(separator: ", "))
            return nil
        }

        print("✅ SEARCH JSON: \(results.count) объявлений")

        var apartments: [Apartment] = []

        for item in results {
            guard let idNum = extractNumber(item["id"]) else { continue }
            let id = "\(idNum)"

            let title = (item["title"] as? String)
                ?? (item["fullName"] as? String)
                ?? "Квартира \(id)"

            let bargainTerms = item["bargainTerms"] as? [String: Any]
            let price = extractInt(bargainTerms?["price"])
                ?? extractInt(bargainTerms?["priceTotal"])
                ?? 0

            let fullUrl = (item["fullUrl"] as? String) ?? ""

            var address = ""
            if let geo = item["geo"] as? [String: Any] {
                if let addressArray = geo["address"] as? [[String: Any]] {
                    address = addressArray.compactMap {
                        ($0["fullName"] as? String) ?? ($0["title"] as? String) ?? ($0["name"] as? String)
                    }.joined(separator: ", ")
                }
                if address.isEmpty {
                    address = (geo["userInputAddress"] as? String) ?? (geo["displayAddress"] as? String) ?? ""
                }
            }
            if address.isEmpty {
                address = (item["displayAddress"] as? String) ?? (item["userInputAddress"] as? String) ?? (item["address"] as? String) ?? ""
            }

            let apartment = Apartment(
                id: id,
                title: title,
                price: price,
                url: fullUrl,
                address: address.isEmpty ? "Адрес не указан" : address
            )

            apartment.area = extractDouble(item["totalArea"])
            apartment.roomsCount = extractInt(item["roomsCount"])
            apartment.floor = extractInt(item["floorNumber"])

            if let building = item["building"] as? [String: Any] {
                apartment.totalFloors = extractInt(building["floorsCount"])
                if apartment.houseMaterial == nil {
                    apartment.houseMaterial = building["materialType"] as? String
                }
            }

            if let geo = item["geo"] as? [String: Any],
               let undergrounds = geo["undergrounds"] as? [[String: Any]],
               let nearest = undergrounds.first {
                apartment.metro = (nearest["name"] as? String) ?? (nearest["title"] as? String)
                if let time = extractInt(nearest["travelTime"]) ?? extractInt(nearest["time"]) ?? extractInt(nearest["distance"]), time > 0 {
                    apartment.metroDistance = time
                }
                apartment.metroTransportType = (nearest["travelType"] as? String) ?? (nearest["transportType"] as? String)
            }

            detectApartmentType(apartment: apartment, item: item)
            apartments.append(apartment)
        }

        return apartments.isEmpty ? nil : apartments
    }

    // MARK: - HTML Extraction (Fallback) - переименованный старый метод
    static func extractOffersFromHTML(from html: String) -> [Apartment] {
        // Старый рабочий код
        return extractOffers(from: html)
    }
    
    // Парсинг HTML карточек Cian через data-name атрибуты (стабильнее CSS-модульных классов)
    static func extractOffers(from html: String) -> [Apartment] {
        var apartments: [Apartment] = []

        do {
            let doc: Document = try SwiftSoup.parse(html)
            let cards = try doc.select("article")
            var skippedNoLink = 0, skippedNoID = 0

            for card in cards {
                // Link: programmatic filter to avoid SwiftSoup *='' selector quirks
                let allLinks = try card.select("a[href]")
                guard let linkEl = allLinks.first(where: {
                    (try? $0.attr("href").contains("/flat/")) == true
                }) else { skippedNoLink += 1; continue }
                let rawUrl = try linkEl.attr("href")
                let url = rawUrl.hasPrefix("http") ? rawUrl : "https://www.cian.ru" + rawUrl

                guard let id = extractID(from: url) else { skippedNoID += 1; continue }

                // Walk all descendants with an explicit for loop — avoids SwiftSoup
                // Elements.first{} ambiguity with its computed `first` property.
                var title = ""
                var priceText = ""
                var geoLabels: [String] = []
                var metroText = ""

                for el in try card.select("*") {
                    guard el.hasAttr("data-name"), let dn = try? el.attr("data-name") else { continue }
                    switch dn {
                    case "TitleComponent", "OfferTitle":
                        if title.isEmpty { title = (try? el.text()) ?? "" }
                    case "MainPrice":
                        // Present before React hydration
                        if priceText.isEmpty { priceText = (try? el.text()) ?? "" }
                    case "ContentRow":
                        // After hydration, MainPrice disappears but ContentRow with price remains.
                        // Pick ContentRow whose text has "₽" but NOT "/м" (to exclude price-per-m²).
                        if priceText.isEmpty, let t = try? el.text(),
                           t.contains("₽"), !t.contains("/м") {
                            priceText = t
                        }
                    case "GeoLabel":
                        if let t = try? el.text() { geoLabels.append(t) }
                    case "SpecialGeo":
                        if metroText.isEmpty { metroText = (try? el.text()) ?? "" }
                    default:
                        break
                    }
                }

                let price = cleanPrice(priceText)
                let address = geoLabels.joined(separator: ", ")

                let apartment = Apartment(
                    id: id,
                    title: title.isEmpty ? "Квартира \(id)" : title,
                    price: price,
                    url: url,
                    address: address.isEmpty ? "Адрес не указан" : address
                )

                // Area and floor from title: "24,2 м², 23/30 этаж"
                let areaPattern = #"(\d+[,\.]\d+|\d+)\s*м²"#
                if let m = title.range(of: areaPattern, options: .regularExpression) {
                    let areaStr = String(title[m])
                        .replacingOccurrences(of: "м²", with: "")
                        .trimmingCharacters(in: .whitespaces)
                        .replacingOccurrences(of: ",", with: ".")
                    apartment.area = Double(areaStr)
                }
                let floorPattern = #"(\d+)/(\d+)\s*этаж"#
                if let m = title.range(of: floorPattern, options: .regularExpression) {
                    let parts = String(title[m]).components(separatedBy: "/")
                    if let f = parts.first.flatMap({ Int($0.trimmingCharacters(in: .whitespaces)) }) {
                        apartment.floor = f
                    }
                    if let totalPart = parts.last?.components(separatedBy: CharacterSet.letters.union(.whitespaces)).first,
                       let t = Int(totalPart) {
                        apartment.totalFloors = t
                    }
                }

                // Metro: data-name="SpecialGeo" → "Аннино 6 минут пешком" (SwiftSoup joins \n with space)
                if !metroText.isEmpty {
                    // Metro name = everything before the first digit ("Аннино 6 минут пешком" → "Аннино")
                    if let digitRange = metroText.rangeOfCharacter(from: .decimalDigits) {
                        let metroName = String(metroText[..<digitRange.lowerBound]).trimmingCharacters(in: .whitespaces)
                        if !metroName.isEmpty { apartment.metro = metroName }
                    } else {
                        apartment.metro = metroText.trimmingCharacters(in: .whitespaces)
                    }
                    if let timeRange = metroText.range(of: #"(\d+)\s*минут"#, options: .regularExpression) {
                        let digits = String(metroText[timeRange]).filter { $0.isNumber }
                        apartment.metroDistance = Int(digits)
                    }
                    apartment.metroTransportType = metroText.contains("пешком") ? "walk" : "transport"
                }

                // Rooms from title
                let lower = title.lowercased()
                if lower.contains("студия") {
                    apartment.roomsCount = 0
                } else if let rm = title.range(of: #"(\d+)-комн"#, options: .regularExpression) {
                    let digit = String(title[rm]).filter { $0.isNumber }
                    apartment.roomsCount = Int(digit)
                }

                apartments.append(apartment)
            }

            print("✅ HTML парсер: извлечено=\(apartments.count)")
        } catch {
            print("❌ SwiftSoup error: \(error)")
        }

        return apartments
    }

    
    // Вспомогательная функция для очистки цены
    private static func cleanPrice(_ text: String) -> Int {
        let digits = text.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
        return Int(digits) ?? 0
    }
    
    // Вспомогательная функция для ID (регулярное выражение)
    private static func extractID(from url: String) -> String? {
        let pattern = "/flat/(\\d+)"
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: url, range: NSRange(url.startIndex..., in: url)) {
            if let range = Range(match.range(at: 1), in: url) {
                return String(url[range])
            }
        }
        return nil
    }
    
    // MARK: - Вспомогательные методы для безопасного приведения JSON-чисел
    
    /// Универсальный парсинг числа из JSON (Int, Double, NSNumber, String)
    private static func extractNumber(_ value: Any?) -> Int? {
        guard let value = value else { return nil }
        if let i = value as? Int { return i }
        if let d = value as? Double { return Int(d) }
        // JSONSerialization часто возвращает NSNumber
        if let n = value as? NSNumber { return n.intValue }
        if let s = value as? String {
            let digits = s.components(separatedBy: CharacterSet(charactersIn: "0123456789").inverted).joined()
            return Int(digits)
        }
        return nil
    }
    
    private static func extractInt(_ value: Any?) -> Int? {
        return extractNumber(value)
    }
    
    private static func extractDouble(_ value: Any?) -> Double? {
        guard let value = value else { return nil }
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        if let n = value as? NSNumber { return n.doubleValue }
        if let s = value as? String { return Double(s.replacingOccurrences(of: ",", with: ".")) }
        return nil
    }

    // MARK: - Apartment type detection

    /// Detects studio and apartments (non-residential) flags from a JSON offer dict.
    /// Called from both API and __NEXT_DATA__ parsers at search-result parse time.
    private static func detectApartmentType(apartment: Apartment, item: [String: Any]) {
        let category = ((item["category"] as? String) ?? "").lowercased()
        let flatType  = ((item["flatType"]  as? String) ?? (item["objectType"] as? String) ?? "").lowercased()

        // Studio: JSON flatType=="studio" or category contains "studio"
        if flatType == "studio" || category.contains("studio") {
            apartment.isStudioFlag = true
        }

        // Апартаменты: Cian uses category "apartmentSale"/"newBuildingApartmentSale" etc.
        // Key heuristic: category contains "apartment" but NOT "newBuilding" alone.
        if category.contains("apartment") {
            apartment.isApartmentsFlag = true
        }
    }
}

// MARK: - SearchParserProtocol

extension CianDataExtractor: SearchParserProtocol {
    func extractData(from html: String) -> [Apartment] {
        CianDataExtractor.extractData(from: html)
    }
}

