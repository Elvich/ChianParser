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
    /// Извлекает данные о квартирах из HTML страницы
    /// Приоритет: JSON из __NEXT_DATA__ → Fallback: SwiftSoup HTML парсинг
    static func extractData(from html: String) -> [Apartment] {
        // 1. Пытаемся извлечь JSON (ПРИОРИТЕТ)
        if let apartments = tryExtractFromJSON(html) {
            print("✅ Данные извлечены из JSON (__NEXT_DATA__)")
            return apartments
        }
        
        // 2. Fallback: классический HTML парсинг через SwiftSoup
        print("⚠️ JSON не найден, используем HTML парсинг (fallback)")
        return extractOffersFromHTML(from: html)
    }
    
    // MARK: - JSON Extraction (Основной метод)
    
    private static func tryExtractFromJSON(_ html: String) -> [Apartment]? {
        do {
            let doc = try SwiftSoup.parse(html)
            guard let jsonTag = try doc.select("script#__NEXT_DATA__").first() else { return nil }
            let jsonString = jsonTag.data()
            
            guard let jsonData = jsonString.data(using: .utf8),
                  let jsonObject = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else { return nil }
            
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
                // ID может прийти как Int или Double — используем extractInt
                guard let idNum = extractNumber(item["id"]) else { continue }
                let id = "\(idNum)"
                
                // Заголовок: "title" или "fullName" (оба содержат тип жилья, площадь, этаж)
                let title = (item["title"] as? String)
                    ?? (item["fullName"] as? String)
                    ?? "Квартира \(id)"
                
                // Цена: bargainTerms.price — ВАЖНО: приходит как NSNumber, не всегда как Int
                let bargainTerms = item["bargainTerms"] as? [String: Any]
                let price = extractInt(bargainTerms?["price"])
                    ?? extractInt(bargainTerms?["priceTotal"])
                    ?? 0
                
                // Ссылка
                let fullUrl = (item["fullUrl"] as? String) ?? ""
                
                // Адрес (максимально агрессивный поиск)
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
                
                // Дополнительные данные из поиска — totalArea приходит как Double, не String
                apartment.area = extractDouble(item["totalArea"])
                apartment.roomsCount = extractInt(item["roomsCount"])
                apartment.floor = extractInt(item["floorNumber"])
                
                // Этажность дома (если есть)
                if let building = item["building"] as? [String: Any] {
                    apartment.totalFloors = extractInt(building["floorsCount"])
                    if apartment.houseMaterial == nil {
                        apartment.houseMaterial = building["materialType"] as? String
                    }
                }

                // Метро из поискового JSON (ближайшая станция)
                if let geo = item["geo"] as? [String: Any],
                   let undergrounds = geo["undergrounds"] as? [[String: Any]],
                   let nearest = undergrounds.first {
                    apartment.metro = (nearest["name"] as? String) ?? (nearest["title"] as? String)
                    // Fields: travelTime (minutes), travelType ("walk"/"transport")
                    // Treat time == 0 as "not specified" — Cian uses 0 as a sentinel value
                    if let time = extractInt(nearest["travelTime"]) ?? extractInt(nearest["time"]) ?? extractInt(nearest["distance"]), time > 0 {
                        apartment.metroDistance = time
                    }
                    apartment.metroTransportType = (nearest["travelType"] as? String) ?? (nearest["transportType"] as? String)
                }

                apartments.append(apartment)
            }

            
            return apartments.isEmpty ? nil : apartments
            
        } catch {
            print("❌ JSON Parsing Error: \(error)")
            return nil
        }
    }
    
    // MARK: - HTML Extraction (Fallback) - переименованный старый метод
    static func extractOffersFromHTML(from html: String) -> [Apartment] {
        // Старый рабочий код
        return extractOffers(from: html)
    }
    
    // Старый метод (для совместимости)
    static func extractOffers(from html: String) -> [Apartment] {
        var apartments: [Apartment] = []
        
        do {
            let doc: Document = try SwiftSoup.parse(html)
            
            // ПРИМЕЧАНИЕ: [data-name="CardComponent"], [data-mark="MainPrice"], [data-name="AddressItem"]
            // удалены с сайта Циан. Используем универсальные теги и паттерны классов.
            //
            // Ищем карточки по тегу article (семантически стабильно)
            let cards = try doc.select("article")
            
            for card in cards {
                // Ссылка на объявление (стабильна — содержит /sale/flat/)
                guard let linkEl = try card.select("a[href*='/sale/flat/']").first() else { continue }
                let url = try linkEl.attr("href")
                
                // Извлекаем ID из URL
                guard let id = extractID(from: url) else { continue }
                
                // Цена: ищем элемент с "₽" в тексте или класс *--price*
                var priceText = try card.select("[class*='--price--']").first()?.text() ?? ""
                if priceText.isEmpty {
                    // Fallback: ищем любой элемент с символом рубля
                    priceText = try card.select("*").first(where: { (try? $0.text().contains("₽")) == true })?.text() ?? ""
                }
                let price = cleanPrice(priceText)
                
                // Заголовок: h2, h3 или первый крупный span внутри карточки
                var title = try card.select("h2, h3").first()?.text() ?? ""
                if title.isEmpty {
                    title = try card.select("[class*='--title--'], [class*='--name--']").first()?.text() ?? ""
                }
                
                // Адрес: ищем элементы с типичными паттернами классов
                var address = try card.select("[class*='--address--']").text()
                if address.isEmpty {
                    address = try card.select("[class*='--geo--'], [class*='--location--']").text()
                }
                
                // Создаём объект
                let apartment = Apartment(
                    id: id,
                    title: title.isEmpty ? "Квартира \(id)" : title,
                    price: price,
                    url: url.hasPrefix("http") ? url : "https://www.cian.ru" + url,
                    address: address.isEmpty ? "Адрес не указан" : address
                )
                
                apartments.append(apartment)
            }
        } catch {
            print("❌ Error parsing HTML with SwiftSoup: \(error)")
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
}

// MARK: - SearchParserProtocol

extension CianDataExtractor: SearchParserProtocol {
    func extractData(from html: String) -> [Apartment] {
        CianDataExtractor.extractData(from: html)
    }
}

