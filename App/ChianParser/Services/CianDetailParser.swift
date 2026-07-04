//
//  CianDetailParser.swift
//  ChianParser
//
//  Парсер детальной страницы объявления
//

import Foundation
import SwiftSoup
import SwiftData

final class CianDetailParser: @unchecked Sendable {
    
    // MARK: - Dependencies
    public let selectorsManager: any SelectorsManagerProtocol

    // MARK: - Init
    public init(selectorsManager: any SelectorsManagerProtocol = SelectorsManager()) {
        self.selectorsManager = selectorsManager
    }
    
    // MARK: - Instance Methods
    
    /// Парсит JSON из `window.__NEXT_DATA__` (предпочтительный метод) и обновляет объект Apartment.
    /// Вызывается из DetailPageLoader, когда JSON был извлечён напрямую через JS без загрузки полного HTML.
    func parseDetailJSON(jsonString: String, apartment: Apartment) {
        let oldViewsTotal = apartment.viewsTotal
        let oldLastUpdate = apartment.lastUpdate
        
        if let jsonData = jsonString.data(using: .utf8),
           let jsonObject = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
           let viewsHistory = jsonObject["__viewsHistory"] as? String {
            apartment.viewsHistoryJSON = viewsHistory
        }
        
        let wrappedHTML = "<html><head><script id=\"__NEXT_DATA__\" type=\"application/json\">\(jsonString)</script></head><body></body></html>"
        if tryExtractFromJSON(html: wrappedHTML, apartment: apartment) {
            applyTitleFallback(apartment: apartment)
            updateViewsSnapshot(apartment: apartment, oldViewsTotal: oldViewsTotal, oldLastUpdate: oldLastUpdate)
            generateBasicTags(for: apartment)
            apartment.isDetailedParsed = true
            apartment.lastUpdate = Date()
            
            if let context = apartment.modelContext {
                let config = context.fetchOrCreateScoringConfiguration()
                if (config.excludeStudios && apartment.isStudio) || (config.excludeApartments && apartment.isApartments) {
                    print("🗑️ [Detail] Удаляем отфильтрованную квартиру (тип не подходит): \(apartment.id)")
                    context.delete(apartment)
                    try? context.save()
                    return
                }
            }
            
            print("✅ [Detail] \(apartment.id) цена=\(apartment.price) площадь=\(apartment.area.map { String($0) } ?? "?") метро=\(apartment.metro ?? "?")")
        } else {
            print("⚠️ [Detail] \(apartment.id) — не удалось распарсить JSON")
        }
    }
    
    /// Парсит детальную страницу объявления и обновляет данные объекта Apartment
    /// - Parameters:
    ///   - html: HTML-код страницы объявления
    ///   - apartment: Объект квартиры для обновления
    func parseDetailPage(html: String, apartment: Apartment) {
        let oldViewsTotal = apartment.viewsTotal
        let oldLastUpdate = apartment.lastUpdate
        
        do {
            let doc = try SwiftSoup.parse(html)
            
            // 0. Сначала пробуем JSON (самый точный способ)
            if tryExtractFromJSON(html: html, apartment: apartment) {
                // ok
            } else {
                
                // 1. Основные характеристики из блока с параметрами
                parseMainCharacteristics(from: doc, apartment: apartment)
                
                // 2. Описание объявления
                parseDescription(from: doc, apartment: apartment)
                
                // 3. Фотографии
                parseImages(from: doc, apartment: apartment)
            }
            
            // Информация из заголовка (всегда полезно как fallback)
            applyTitleFallback(apartment: apartment)
            
            // 4. Информация о доме (всегда пробуем дополнить)
            parseHouseInfo(from: doc, apartment: apartment)
            
            // 5. Метро и расположение (всегда пробуем дополнить)
            parseLocation(from: doc, apartment: apartment)
            
            // 6. Статистика просмотров
            parseStatistics(from: doc, apartment: apartment)
            
            // 7. Информация о продавце
            parseSellerInfo(from: doc, apartment: apartment)
            
            // Отмечаем, что детальный парсинг выполнен
            updateViewsSnapshot(apartment: apartment, oldViewsTotal: oldViewsTotal, oldLastUpdate: oldLastUpdate)
            generateBasicTags(for: apartment)
            apartment.isDetailedParsed = true
            apartment.lastUpdate = Date()
            
            if let context = apartment.modelContext {
                let config = context.fetchOrCreateScoringConfiguration()
                if (config.excludeStudios && apartment.isStudio) || (config.excludeApartments && apartment.isApartments) {
                    print("🗑️ [Detail/HTML] Удаляем отфильтрованную квартиру (тип не подходит): \(apartment.id)")
                    context.delete(apartment)
                    try? context.save()
                    return
                }
            }
            
            print("✅ [Detail/HTML] \(apartment.id) цена=\(apartment.price) площадь=\(apartment.area.map { String($0) } ?? "?") метро=\(apartment.metro ?? "?")")
            
        } catch {
            print("❌ Ошибка парсинга детальной страницы: \(error)")
        }
    }
    
    // MARK: - Semantic Tags Generator
    
    /// Генерирует базовые семантические теги на основе уже распарсенных данных
    private func generateBasicTags(for apartment: Apartment) {
        var tags: [String] = []
        
        // 1. Комнаты
        if apartment.isStudio {
            tags.append("Студия")
        } else if let rooms = apartment.roomsCount {
            if rooms >= 4 {
                tags.append("4+ комн.")
            } else {
                tags.append("\(rooms)-комн.")
            }
        }
        
        // 2. Метро
        if let metroDist = apartment.metroDistance {
            if metroDist <= 5 {
                tags.append("до 5 мин")
            } else if metroDist <= 10 {
                tags.append("до 10 мин")
            } else if metroDist <= 15 {
                tags.append("до 15 мин")
            } else {
                tags.append("> 15 мин")
            }
        }
        
        // 3. Этаж
        if let floor = apartment.floor, let total = apartment.totalFloors, total > 0 {
            if floor == 1 {
                tags.append("Первый этаж")
            } else if floor == total {
                tags.append("Последний этаж")
            } else if floor == total - 1 {
                tags.append("Предпоследний этаж")
            }
        }
        
        // 4. Площадь
        if let area = apartment.area {
            if area < 30 {
                tags.append("до 30 м²")
            } else if area <= 50 {
                tags.append("30-50 м²")
            } else if area <= 70 {
                tags.append("50-70 м²")
            } else {
                tags.append("> 70 м²")
            }
        }
        
        // 5. Особенности
        if apartment.isAuction { tags.append("Аукцион") }
        if apartment.isAlternative { tags.append("Альтернатива") }
        if apartment.isShare { tags.append("Доля") }
        if apartment.isApartments { tags.append("Апартаменты") }
        if apartment.isPaidPromotion { tags.append("Продвижение (\(apartment.promotionType ?? ""))") }
        
        apartment.semanticTags = tags
    }
    
    // MARK: - JSON Detail Extraction
    
    private func tryExtractFromJSON(html: String, apartment: Apartment) -> Bool {
        do {
            let doc = try SwiftSoup.parse(html)
            
            // Пробуем разные селекторы для JSON из SelectorsManager
            let jsonSelectors = selectorsManager.config.detail.jsonSelectors
            
            var jsonTag: Element?
            var jsonString = ""
            
            for selector in jsonSelectors {
                if let tag = try? doc.select(selector).first() {
                    jsonTag = tag
                    jsonString = tag.data()
                    break
                }
            }
            
            if jsonTag == nil {
                if let scripts = try? doc.select("script") {
                    for script in scripts {
                        let data = script.data()
                        if data.contains("offerData") || data.contains("\"id\":") && data.count > 1000 {
                            jsonString = data
                            break
                        }
                    }
                }
            }

            if jsonString.isEmpty { return false }

            guard let jsonData = jsonString.data(using: .utf8),
                  let jsonObject = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                return false
            }
            
            // Ищем offerData рекурсивно
            guard let offerData = findValue(forKey: "offerData", in: jsonObject) as? [String: Any] else {
                return false
            }
            
            // КЛЮЧЕВОЕ: все поля квартиры вложены в offerData["offer"], не в offerData напрямую
            let offerNode = (offerData["offer"] as? [String: Any]) ?? offerData
            
            // 0. Цена и заголовок
            let bargainTerms = (offerNode["bargainTerms"] as? [String: Any])
                ?? (offerData["bargainTerms"] as? [String: Any])
            if let bt = bargainTerms {
                let detailPrice = extractInt(bt["price"])
                    ?? extractInt(bt["priceRur"])
                    ?? extractInt(bt["priceTotal"])
                    ?? extractInt(bt["priceTotalRur"])
                if let p = detailPrice, p > 0 {
                    apartment.price = p
                }
            }
            
            // Заголовок — берём из поля title или fullName
            if apartment.title.hasPrefix("Квартира ") {
                let t = (offerNode["title"] as? String) ?? (offerNode["fullName"] as? String)
                    ?? (offerData["title"] as? String) ?? (offerData["fullName"] as? String)
                if let t = t, !t.isEmpty { apartment.title = t }
            }
            
            // 1. Площадь
            apartment.area = extractDouble(offerNode["totalArea"])
                ?? extractDouble(offerNode["area"])
                ?? extractDouble(offerData["totalArea"])
                ?? extractDouble(offerData["allArea"])
            apartment.livingArea = extractDouble(offerNode["livingArea"])
                ?? extractDouble(offerData["livingArea"])
            apartment.kitchenArea = extractDouble(offerNode["kitchenArea"])
                ?? extractDouble(offerData["kitchenArea"])
            
            // 2. Этаж и комнаты
            apartment.floor = extractInt(offerNode["floorNumber"])
                ?? extractInt(offerNode["floor"])
                ?? extractInt(offerData["floorNumber"])
            apartment.roomsCount = extractInt(offerNode["roomsCount"])
                ?? extractInt(offerNode["rooms"])
                ?? extractInt(offerData["roomsCount"])
            
            // 3. Описание
            apartment.apartmentDescription = (offerNode["description"] as? String)
                ?? (offerData["description"] as? String)
                ?? (offerData["text"] as? String)
            
            // 4. Фотографии
            var photos: [String] = []
            let photosSource = (offerNode["photos"] as? [[String: Any]])
                ?? (offerData["photos"] as? [[String: Any]])
                ?? (offerData["images"] as? [[String: Any]])
            if let photosData = photosSource {
                photos = photosData.compactMap { ($0["fullUrl"] as? String) ?? ($0["url"] as? String) ?? ($0["src"] as? String) }
            }
            
            // БРУТФОРС ФОТО: Если фото мало или нет, ищем во всей строке JSON
            if photos.count < 3 {
                let regex = try? NSRegularExpression(pattern: "https://cdn-p\\.cian\\.site/[^\"\\s]+\\.jpg", options: [])
                let matches = regex?.matches(in: jsonString, range: NSRange(jsonString.startIndex..., in: jsonString))
                let brutePhotos = matches?.compactMap { match -> String? in
                    if let range = Range(match.range, in: jsonString) { return String(jsonString[range]) }
                    return nil
                } ?? []
                photos.append(contentsOf: brutePhotos)
            }
            apartment.imageURLs = Array(Set(photos.filter { !$0.isEmpty }))
            
            // 5. Дом
            if let building = (offerNode["building"] as? [String: Any])
                ?? (offerData["building"] as? [String: Any])
                ?? (findValue(forKey: "building", in: jsonObject) as? [String: Any]) {
                apartment.totalFloors = extractInt(building["floorsCount"]) ?? extractInt(building["floors"])
                apartment.yearBuilt = extractInt(building["buildYear"]) ?? extractInt(building["year"])
                apartment.houseMaterial = (building["materialType"] as? String) ?? (building["material"] as? String)
                
                if let parking = building["parking"] as? String { apartment.parking = parking }
                if let elevatorData = building["passenger_lifts_count"] ?? building["lifts"] {
                    if let count = extractInt(elevatorData), count > 0 { apartment.elevator = "\(count) шт." }
                }
            }
            
            // Дополнительные характеристики квартиры
            apartment.ceilingHeight = extractDouble(offerNode["ceilingHeight"])
                ?? extractDouble(offerData["ceilingHeight"])
            apartment.bathroomType = (offerNode["bathroomType"] as? String) ?? (offerData["bathroomType"] as? String)
            apartment.balcony = (offerNode["balconyType"] as? String) ?? (offerData["balcony"] as? String)
            apartment.repair = (offerNode["repairType"] as? String) ?? (offerData["repair"] as? String)
            if let furniture = (offerNode["hasFurniture"] as? Bool) ?? (offerData["hasFurniture"] as? Bool) {
                apartment.furniture = furniture
            }
            apartment.windowView = (offerNode["windowView"] as? String) ?? (offerData["windowView"] as? String)
            
            // 6. Адрес и метро
            if let geo = (offerNode["geo"] as? [String: Any])
                ?? (offerData["geo"] as? [String: Any])
                ?? (findValue(forKey: "geo", in: jsonObject) as? [String: Any]) {
                var addressComponents: [String] = []
                
                if let addressArray = geo["address"] as? [[String: Any]] {
                    addressComponents = addressArray.compactMap { 
                        ($0["fullName"] as? String) ?? ($0["title"] as? String) ?? ($0["name"] as? String) 
                    }
                }
                
                if addressComponents.isEmpty {
                    if let displayAddr = (geo["displayAddress"] as? String) ?? (geo["userInputAddress"] as? String) {
                        addressComponents = [displayAddr]
                    }
                }
                
                if addressComponents.isEmpty {
                    if let city = geo["city"] as? String { addressComponents.append(city) }
                    if let street = geo["street"] as? String { addressComponents.append(street) }
                    if let house = geo["house"] as? String { addressComponents.append(house) }
                }
                
                let fullAddress = addressComponents.joined(separator: ", ")
                if !fullAddress.isEmpty {
                    apartment.address = fullAddress
                }
                
                // Метро
                if let undergrounds = geo["undergrounds"] as? [[String: Any]], let metro = undergrounds.first {
                    apartment.metro = (metro["name"] as? String) ?? (metro["title"] as? String)
                    if let time = extractInt(metro["travelTime"]) ?? extractInt(metro["time"]) ?? extractInt(metro["distance"]), time > 0 {
                        apartment.metroDistance = time
                    }
                    apartment.metroTransportType = (metro["travelType"] as? String) ?? (metro["transportType"] as? String)
                }
            }
            
            if apartment.address.isEmpty || apartment.address == "Адрес не указан" {
                let possibleKeys = ["displayAddress", "userInputAddress", "address", "fullAddress", "location"]
                for key in possibleKeys {
                    if let addr = findValue(forKey: key, in: jsonObject) as? String, !addr.isEmpty {
                        apartment.address = addr
                        break
                    }
                }
            }
            
            // 7. Статистика
            let statsNode = (offerNode["stats"] as? [String: Any])
                ?? (offerData["stats"] as? [String: Any])
            
            if let stats = statsNode {
                print("  🔍 DEBUG: Ключи внутри stats: \(stats.keys.joined(separator: ", "))")
                for (key, value) in stats {
                    if let array = value as? [Any] {
                        print("  🔍 DEBUG: Найден массив в stats['\(key)']: \(array)")
                    }
                }
            }
            
            if let stats = statsNode {
                apartment.viewsTotal = extractInt(stats["total"])
                    ?? extractInt(stats["totalViews"])
                    ?? extractInt(stats["allViews"])
                apartment.viewsToday = extractInt(stats["daily"])
                    ?? extractInt(stats["dailyViews"])
                    ?? extractInt(stats["today"])
                    ?? extractInt(stats["todayViews"])
                    ?? extractInt(stats["viewsToday"])
                    ?? extractInt(stats["dayViews"])
            }
            
            if apartment.viewsTotal == nil || apartment.viewsToday == nil {
                let formattedStr = statsNode?["totalViewsFormattedString"] as? String
                    ?? offerNode["totalViewsFormattedString"] as? String
                    ?? offerData["totalViewsFormattedString"] as? String
                if let formatted = formattedStr {
                    parseViewsFormattedString(formatted, apartment: apartment)
                }
            }
            
            if apartment.viewsTotal == nil || apartment.viewsToday == nil {
                if let stats = findValue(forKey: "stats", in: jsonObject) as? [String: Any] {
                    if let formatted = stats["totalViewsFormattedString"] as? String {
                        parseViewsFormattedString(formatted, apartment: apartment)
                    }
                    if apartment.viewsTotal == nil {
                        apartment.viewsTotal = extractInt(stats["total"])
                            ?? extractInt(stats["totalViews"])
                            ?? extractInt(stats["allViews"])
                    }
                    if apartment.viewsToday == nil {
                        apartment.viewsToday = extractInt(stats["daily"])
                            ?? extractInt(stats["dailyViews"])
                            ?? extractInt(stats["today"])
                            ?? extractInt(stats["todayViews"])
                            ?? extractInt(stats["viewsToday"])
                            ?? extractInt(stats["dayViews"])
                    }
                }
            }

            if apartment.viewsToday == nil {
                parseViewsFormattedString(jsonString, apartment: apartment)
            }

            if apartment.viewsTotal == nil {
                apartment.viewsTotal = extractInt(jsonObject["__domViewsTotal"])
            }
            if apartment.viewsToday == nil {
                apartment.viewsToday = extractInt(jsonObject["__domViewsToday"])
            }

            if let total = apartment.viewsTotal, let today = apartment.viewsToday {
                print("  📊 Просмотры: сегодня \(today), всего \(total)")
            }

            // 9. Авто-детекция аукциона и внесённого залога
            let isAuctionFlag = (offerNode["isAuction"] as? Bool) ?? (offerData["isAuction"] as? Bool) ?? false
            let saleType = ((offerNode["bargainTerms"] as? [String: Any])?["saleType"] as? String)
                ?? (offerNode["saleType"] as? String)
                ?? (offerData["saleType"] as? String)
                ?? ""
            apartment.isAuction = isAuctionFlag
                || saleType.lowercased().contains("auction")
                || apartment.title.lowercased().contains("аукцион")
                || (apartment.apartmentDescription?.lowercased().contains("аукцион") ?? false)
                
            apartment.isAlternative = saleType.lowercased().contains("alternative")

            let descLower = apartment.apartmentDescription?.lowercased() ?? ""
            let depositPhrases = [
                "залог внесен", "залог внесён", "задаток внесен", "задаток внесён",
                "аванс внесен", "аванс внесён", "внесен залог", "внесён залог",
                "внесен задаток", "внесён задаток", "внесен аванс", "внесён аванс",
                "под авансом", "принят аванс", "получен аванс", "взяли аванс", "дали аванс",
                "под залогом", "принят залог", "получен залог",
                "под бронью", "квартира забронирована", "забронировано", "бронь до"
            ]
            apartment.isDepositPaid = depositPhrases.contains { descLower.contains($0) }

            // 11. Платное продвижение
            let placement = ((offerNode["placementType"] as? String)
                ?? (offerData["placementType"] as? String)
                ?? (offerNode["promotionType"] as? String)
                ?? (offerData["promotionType"] as? String)
                ?? (findValue(forKey: "placementType", in: jsonObject) as? String)
                ?? (findValue(forKey: "promotionType", in: jsonObject) as? String)
                ?? "").lowercased()
            if !placement.isEmpty && placement != "simple" && placement != "organic" {
                apartment.isPaidPromotion = true
                apartment.promotionType = placement
                print("  📢 Продвижение: \(placement) — \(apartment.id)")
            }

            // 10. Тип объекта
            let category = ((offerNode["category"] as? String) ?? (offerData["category"] as? String) ?? "").lowercased()
            let flatType  = ((offerNode["flatType"]  as? String) ?? (offerData["flatType"]  as? String)
                ?? (offerNode["objectType"] as? String) ?? (offerData["objectType"] as? String) ?? "").lowercased()
            let titleLower = apartment.title.lowercased()

            if flatType == "studio" || category.contains("studio")
                || titleLower.hasPrefix("студия")
                || descLower.contains("студия") {
                apartment.isStudioFlag = true
            }
            if category.contains("apartment")
                || titleLower.contains("апартамент")
                || descLower.contains("апартамент") {
                apartment.isApartmentsFlag = true
            }
            if category.contains("share") || titleLower.contains("доля") {
                apartment.isShare = true
            }

            // Дата публикации
            let publishedDateStr = (offerNode["publishedDate"] as? String)
                ?? (offerData["publishedDate"] as? String)
            if let dateStr = publishedDateStr {
                let formatter = ISO8601DateFormatter()
                if let date = formatter.date(from: dateStr) {
                    apartment.publishedDate = date
                } else {
                    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                    apartment.publishedDate = formatter.date(from: dateStr)
                }
            } else if let ts = (offerNode["addedTimestamp"] as? TimeInterval) ?? (offerData["addedTimestamp"] as? TimeInterval) {
                apartment.publishedDate = Date(timeIntervalSince1970: ts)
            }
            
            // 8. Продавец
            let sellerNode = (offerNode["seller"] as? [String: Any])
                ?? (offerNode["agent"] as? [String: Any])
                ?? (offerData["seller"] as? [String: Any])
                ?? (offerData["agent"] as? [String: Any])
            if let seller = sellerNode {
                apartment.sellerName = (seller["name"] as? String) ?? (seller["alias"] as? String) ?? (seller["companyName"] as? String)
                apartment.sellerType = (seller["type"] as? String) ?? (seller["category"] as? String)
            }
            return true
        } catch {
            return false
        }
    }
    
    // Рекурсивный поиск ключа
    private func findValue(forKey key: String, in dictionary: [String: Any]) -> Any? {
        if let value = dictionary[key] { return value }
        for (_, value) in dictionary {
            if let nestedDict = value as? [String: Any] {
                if let result = findValue(forKey: key, in: nestedDict) { return result }
            } else if let array = value as? [[String: Any]] {
                for item in array {
                    if let result = findValue(forKey: key, in: item) { return result }
                }
            }
        }
        return nil
    }
    
    private func parseViewsFormattedString(_ text: String, apartment: Apartment) {
        // 1. Извлечение общего количества просмотров
        let totalPattern = "(\\d[\\d \\u00A0]*)\\s*просмотр"
        if apartment.viewsTotal == nil,
           let regex = try? NSRegularExpression(pattern: totalPattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let totalRange = Range(match.range(at: 1), in: text) {
            let totalStr = String(text[totalRange]).filter(\.isNumber)
            apartment.viewsTotal = Int(totalStr)
        }
        
        // 2. Извлечение сегодняшних просмотров
        // Вариант А: число за сегодня
        let todayPattern = "(\\d+)\\s*за сегодня"
        if apartment.viewsToday == nil,
           let regex = try? NSRegularExpression(pattern: todayPattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let todayRange = Range(match.range(at: 1), in: text) {
            apartment.viewsToday = Int(text[todayRange])
        }
        
        // Вариант Б: фраза "нет за сегодня" (интерпретируется как 0)
        let noTodayPattern = "нет\\s*за сегодня"
        if apartment.viewsToday == nil,
           let regex = try? NSRegularExpression(pattern: noTodayPattern, options: .caseInsensitive),
           let _ = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) {
            apartment.viewsToday = 0
        }
    }
    
    // Fallback из заголовка
    private func applyTitleFallback(apartment: Apartment) {
        let title = apartment.title
        if apartment.area == nil || apartment.area == 0 {
            let regex = try? NSRegularExpression(pattern: "(\\d+[.,]\\d+|\\d+)\\s*м²")
            if let match = regex?.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)),
               let range = Range(match.range(at: 1), in: title) {
                apartment.area = Double(title[range].replacingOccurrences(of: ",", with: "."))
            }
        }
        if apartment.floor == nil || apartment.floor == 0 {
            let regex = try? NSRegularExpression(pattern: "(\\d+)/(\\d+)\\s*этаж")
            if let match = regex?.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)),
               let floorRange = Range(match.range(at: 1), in: title),
               let totalRange = Range(match.range(at: 2), in: title) {
                apartment.floor = Int(title[floorRange])
                apartment.totalFloors = Int(title[totalRange])
            }
        }
    }
    
    // MARK: - Views Snapshot Helper
    
    private func updateViewsSnapshot(apartment: Apartment, oldViewsTotal: Int?, oldLastUpdate: Date) {
        if let oldTotal = oldViewsTotal, let newTotal = apartment.viewsTotal, newTotal > oldTotal {
            let prevDate = apartment.previousViewsDate ?? Date.distantPast
            if Date().timeIntervalSince(prevDate) > 20 * 3600 {
                apartment.previousViewsTotal = oldTotal
                apartment.previousViewsDate = oldLastUpdate
                print("  ⏱ Обновлен снэпшот просмотров: \(oldTotal) (зафиксировано от \(oldLastUpdate))")
            }
        } else if apartment.previousViewsTotal == nil, let currentTotal = apartment.viewsTotal {
             apartment.previousViewsTotal = currentTotal
             apartment.previousViewsDate = oldLastUpdate
        }
    }
    
    // MARK: - Вспомогательные методы
    
    private func extractDouble(_ value: Any?) -> Double? {
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        if let n = value as? NSNumber { return n.doubleValue }
        if let s = value as? String { return Double(s.replacingOccurrences(of: ",", with: ".")) }
        return nil
    }
    
    private func extractInt(_ value: Any?) -> Int? {
        if let i = value as? Int { return i }
        if let n = value as? NSNumber { return n.intValue }
        if let d = value as? Double { return Int(d) }
        if let s = value as? String {
            let digits = s.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
            return Int(digits)
        }
        return nil
    }
    
    // MARK: - HTML Fallbacks
    
    private func parseMainCharacteristics(from doc: Document, apartment: Apartment) {
        print("  🔍 DEBUG: Начинаю HTML-парсинг характеристик...")
        
        let selectors = selectorsManager.config.detail.mainCharacteristicsSelectors
        var foundItems = false
        
        for selector in selectors {
            if let items = try? doc.select(selector), !items.isEmpty() {
                print("  ✓ Найдено элементов по селектору '\(selector)': \(items.count)")
                foundItems = true
                
                for item in items {
                    var title = ""
                    var value = ""
                    
                    let children = item.children()
                    if children.count >= 2 {
                        title = (try? children.get(0).text()) ?? ""
                        value = (try? children.get(children.count - 1).text()) ?? ""
                    } else if children.count == 1 {
                        let grandchildren = children.get(0).children()
                        if grandchildren.count >= 2 {
                            title = (try? grandchildren.get(0).text()) ?? ""
                            value = (try? grandchildren.get(grandchildren.count - 1).text()) ?? ""
                        }
                    }
                    
                    if title.isEmpty {
                        title = (try? item.select(selectorsManager.config.detail.mainCharacteristicsTitleSelector).first()?.text()) ?? ""
                    }
                    if value.isEmpty {
                        value = (try? item.select(selectorsManager.config.detail.mainCharacteristicsValueSelector).first()?.text()) ?? ""
                    }
                    
                    if title.isEmpty || value.isEmpty {
                        let fullText = (try? item.text()) ?? ""
                        let t = fullText.trimmingCharacters(in: .whitespaces)
                        if !t.isEmpty {
                            if title.isEmpty { title = t }
                            if value.isEmpty { value = t }
                        }
                    }
                    
                    if title.isEmpty && value.isEmpty {
                        continue
                    }
                    
                    let titleLower = title.lowercased()
                    let valueCleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    if !title.isEmpty && !value.isEmpty {
                        print("  📋 \(title): \(valueCleaned)")
                    }
                    
                    if titleLower.contains("общая площадь") || titleLower.contains("общая") {
                        apartment.area = extractDouble(valueCleaned)
                    }
                    else if titleLower.contains("жилая площадь") || titleLower.contains("жилая") {
                        apartment.livingArea = extractDouble(valueCleaned)
                    }
                    else if titleLower.contains("площадь кухни") || titleLower.contains("кухня") {
                        apartment.kitchenArea = extractDouble(valueCleaned)
                    }
                    else if titleLower.contains("этаж") {
                        let parts = valueCleaned.split(separator: " ")
                        if let floorPart = parts.first?.split(separator: "/").first {
                            apartment.floor = Int(floorPart)
                        }
                        if let totalPart = parts.first?.split(separator: "/").last {
                            apartment.totalFloors = Int(totalPart)
                        }
                    }
                    else if titleLower.contains("комнат") {
                        apartment.roomsCount = extractInt(valueCleaned)
                    }
                    else if titleLower.contains("год постройки") || titleLower.contains("построен") {
                        apartment.yearBuilt = extractInt(valueCleaned)
                    }
                    else if titleLower.contains("тип дома") || titleLower.contains("материал") {
                        apartment.houseMaterial = valueCleaned
                    }
                    else if titleLower.contains("высота потолков") || titleLower.contains("потолки") {
                        apartment.ceilingHeight = extractDouble(valueCleaned)
                    }
                    else if titleLower.contains("санузел") {
                        apartment.bathroomType = valueCleaned
                    }
                    else if titleLower.contains("балкон") || titleLower.contains("лоджия") {
                        apartment.balcony = valueCleaned
                    }
                    else if titleLower.contains("ремонт") || titleLower.contains("отделка") {
                        apartment.repair = valueCleaned
                    }
                    else if titleLower.contains("лифт") {
                        apartment.elevator = valueCleaned
                    }
                    else if titleLower.contains("парковка") {
                        apartment.parking = valueCleaned
                    }
                    else if titleLower.contains("вид из окон") || titleLower.contains("окна") {
                        apartment.windowView = valueCleaned
                    }
                }
                break
            }
        }
        
        if !foundItems {
            print("  ⚠️ Не найдено элементов характеристик через стандартные селекторы")
            print("  🔍 Пробую альтернативный парсинг...")
        }
        
        if let allItems = try? doc.select(selectorsManager.config.detail.alternativeCharacteristicsSelectors) {
            for item in allItems {
                if let text = try? item.text() {
                    let parts = text.components(separatedBy: ":")
                    if parts.count >= 2 {
                        let key = parts[0].trimmingCharacters(in: .whitespaces).lowercased()
                        let value = parts[1...].joined(separator: ":").trimmingCharacters(in: .whitespaces)
                        
                        if key.contains("жилая") && apartment.livingArea == nil {
                            apartment.livingArea = extractDouble(value)
                        } else if key.contains("кухн") && apartment.kitchenArea == nil {
                            apartment.kitchenArea = extractDouble(value)
                        } else if key.contains("год") && apartment.yearBuilt == nil {
                            apartment.yearBuilt = extractInt(value)
                        } else if key.contains("потолк") && apartment.ceilingHeight == nil {
                            apartment.ceilingHeight = extractDouble(value)
                        }
                    }
                }
            }
        }
    }
    
    private func parseDescription(from doc: Document, apartment: Apartment) {
        if let desc = apartment.apartmentDescription, !desc.isEmpty {
            return
        }
        
        let selectors = selectorsManager.config.detail.descriptionSelectors
        
        for selector in selectors {
            if let desc = try? doc.select(selector).first()?.text(), !desc.isEmpty {
                apartment.apartmentDescription = desc
                print("  📝 Описание найдено (длина: \(desc.count) символов)")
                return
            }
        }
    }
    
    private func parseImages(from doc: Document, apartment: Apartment) {
        if !apartment.imageURLs.isEmpty {
            return
        }
        
        print("  🔍 DEBUG: Поиск изображений...")
        var images: [String] = []
        
        if let imgs = try? doc.select("img") {
            print("  📸 Найдено img-тегов: \(imgs.count)")
            for img in imgs {
                if let src = try? img.attr("src"), !src.isEmpty {
                    if src.contains("cian.site") || src.contains("cian.ru") {
                        images.append(src)
                    }
                }
                if let dataSrc = try? img.attr("data-src"), !dataSrc.isEmpty {
                    if dataSrc.contains("cian.site") || dataSrc.contains("cian.ru") {
                        images.append(dataSrc)
                    }
                }
                if let srcset = try? img.attr("srcset"), !srcset.isEmpty {
                    let urls = srcset.components(separatedBy: ",").compactMap { component -> String? in
                        let url = component.trimmingCharacters(in: .whitespaces).components(separatedBy: " ").first
                        return url?.contains("cian") == true ? url : nil
                    }
                    images.append(contentsOf: urls)
                }
            }
        }
        
        if let elementsWithStyle = try? doc.select("[style*='background-image']") {
            for elem in elementsWithStyle {
                if let style = try? elem.attr("style") {
                    let regex = try? NSRegularExpression(pattern: "url\\(['\"]?([^'\"\\)]+)['\"]?\\)", options: [])
                    if let matches = regex?.matches(in: style, range: NSRange(style.startIndex..., in: style)) {
                        for match in matches {
                            if let range = Range(match.range(at: 1), in: style) {
                                let url = String(style[range])
                                if url.contains("cian") {
                                    images.append(url)
                                }
                            }
                        }
                    }
                }
            }
        }
        
        if images.isEmpty {
            print("  ⚠️ Стандартные способы не сработали, пробую брутфорс...")
            let htmlString = (try? doc.html()) ?? ""
            let patterns = [
                "https://cdn-p\\.cian\\.site/[^\"\\s']+\\.jpg",
                "https://cdn-p\\.cian\\.site/[^\"\\s']+\\.jpeg",
                "https://cdn-p\\.cian\\.site/[^\"\\s']+\\.png",
                "https://[^\"\\s']*cian[^\"\\s']*\\.(jpg|jpeg|png)"
            ]
            
            for pattern in patterns {
                if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                    let matches = regex.matches(in: htmlString, range: NSRange(htmlString.startIndex..., in: htmlString))
                    let urls = matches.compactMap { match -> String? in
                        if let range = Range(match.range, in: htmlString) {
                            return String(htmlString[range])
                        }
                        return nil
                    }
                    images.append(contentsOf: urls)
                }
            }
        }
        
        apartment.imageURLs = Array(Set(images.filter { !$0.isEmpty }))
        print("  🖼️ Найдено изображений: \(apartment.imageURLs.count)")
        
        if apartment.imageURLs.count > 0 {
            print("  📸 Примеры URL:")
            for (index, url) in apartment.imageURLs.prefix(3).enumerated() {
                print("     \(index + 1). \(url.prefix(80))...")
            }
        }
    }
    
    private func parseHouseInfo(from doc: Document, apartment: Apartment) {
        guard apartment.yearBuilt == nil || apartment.houseMaterial == nil else { return }
        
        let candidates = (try? doc.select("dl, table, [class*='--summary--'], [class*='--params--']")) ?? Elements()
        for elem in candidates {
            if let text = try? elem.text() {
                if apartment.yearBuilt == nil, text.contains("Год постройки") {
                    let pattern = #"Год постройки.{0,10}(\d{4})"#
                    if let regex = try? NSRegularExpression(pattern: pattern),
                       let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                       let range = Range(match.range(at: 1), in: text) {
                        apartment.yearBuilt = Int(text[range])
                    }
                }
                if apartment.houseMaterial == nil, text.contains("Тип дома") {
                    let pattern = #"Тип дома[^\n]{0,5}([А-Яа-яёЁ]+(?:[- ][А-Яа-яёЁ]+)*)"#
                    if let regex = try? NSRegularExpression(pattern: pattern),
                       let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                       let range = Range(match.range(at: 1), in: text) {
                        apartment.houseMaterial = String(text[range]).trimmingCharacters(in: .whitespaces)
                    }
                }
            }
            if apartment.yearBuilt != nil && apartment.houseMaterial != nil { break }
        }
    }
    
    private func parseLocation(from doc: Document, apartment: Apartment) {
        print("  🔍 DEBUG: Парсинг адреса и метро...")
        
        if apartment.address.isEmpty || apartment.address == "Адрес не указан" {
            let addressSelectors = selectorsManager.config.detail.addressSelectors
            
            for selector in addressSelectors {
                if let addressElement = try? doc.select(selector).first() {
                    if let addr = try? addressElement.text(), !addr.isEmpty {
                        var cleanedAddr = addr
                        cleanedAddr = cleanedAddr.replacingOccurrences(of: "На карте", with: "")
                        
                        if let metroRange = cleanedAddr.range(of: #"\d+\s*мин\."#, options: .regularExpression) {
                            cleanedAddr = String(cleanedAddr[..<metroRange.lowerBound])
                        }
                        
                        cleanedAddr = cleanedAddr.trimmingCharacters(in: .whitespacesAndNewlines)
                        
                        if !cleanedAddr.isEmpty && cleanedAddr.count > 5 {
                            apartment.address = cleanedAddr
                            print("  📍 Адрес: \(cleanedAddr)")
                            break
                        }
                    }
                }
            }
        }
        
        if apartment.metro == nil {
            let metroSelectors = selectorsManager.config.detail.metroSelectors
            
            for selector in metroSelectors {
                if let metroElements = try? doc.select(selector) {
                    for elem in metroElements {
                        if let metroText = try? elem.text(), !metroText.isEmpty {
                            let components = metroText.components(separatedBy: CharacterSet.decimalDigits)
                            if let name = components.first?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
                                apartment.metro = name
                                
                                let timeRegex = try? NSRegularExpression(pattern: #"(\d+)\s*мин"#)
                                if let match = timeRegex?.firstMatch(in: metroText, range: NSRange(metroText.startIndex..., in: metroText)),
                                   let range = Range(match.range(at: 1), in: metroText) {
                                    apartment.metroDistance = Int(metroText[range])
                                }
                                
                                let distanceStr = apartment.metroDistance.map { ", \($0) мин" } ?? ""
                                print("  🚇 Метро: \(apartment.metro ?? "н/д")\(distanceStr)")
                                break
                            }
                        }
                    }
                    if apartment.metro != nil { break }
                }
            }
        }
    }
    
    /// Дополнительный парсинг просмотров из DOM (если они не были найдены в JSON)
    private func parseViewsDOMFallback(from doc: Document, apartment: Apartment) {
        if apartment.viewsTotal != nil && apartment.viewsToday != nil {
            return
        }
        
        print("  🔍 DOM Fallback: Поиск просмотров в HTML...")
        
        // 1. Поиск по специфическим селекторам атрибутов
        let attributeSelectors = [
            "[data-name*='views']",
            "[data-name*='Views']",
            "[data-name*='stats']",
            "[data-name*='Stats']",
            "[class*='views']",
            "[class*='Views']",
            "[class*='stats']",
            "[class*='Stats']"
        ]
        
        for selector in attributeSelectors {
            if let elements = try? doc.select(selector) {
                for element in elements {
                    if let text = try? element.text(), !text.isEmpty {
                        parseViewsFormattedString(text, apartment: apartment)
                        if apartment.viewsTotal != nil && apartment.viewsToday != nil {
                            print("  ✓ Просмотры успешно найдены по селектору '\(selector)': \(text)")
                            return
                        }
                    }
                }
            }
        }
        
        // 2. Поиск по всему текстовому содержимому страницы
        if apartment.viewsTotal == nil || apartment.viewsToday == nil {
            if let pageText = try? doc.text(), !pageText.isEmpty {
                parseViewsFormattedString(pageText, apartment: apartment)
                if apartment.viewsTotal != nil || apartment.viewsToday != nil {
                    print("  ✓ Просмотры частично или полностью найдены в тексте страницы")
                }
            } else if let bodyText = try? doc.body()?.text(), !bodyText.isEmpty {
                parseViewsFormattedString(bodyText, apartment: apartment)
                if apartment.viewsTotal != nil || apartment.viewsToday != nil {
                    print("  ✓ Просмотры частично или полностью найдены в теле страницы")
                }
            }
        }
    }

    private func parseStatistics(from doc: Document, apartment: Apartment) {
        if apartment.publishedDate == nil {
            if let dateElement = try? doc.select("time[datetime]").first() {
                if let dateStr = try? dateElement.attr("datetime") {
                    let formatter = ISO8601DateFormatter()
                    if let date = formatter.date(from: dateStr) {
                        apartment.publishedDate = date
                    } else {
                        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                        apartment.publishedDate = formatter.date(from: dateStr)
                    }
                } else if let dateText = try? dateElement.text() {
                    print("  📅 Дата публикации (текст): \(dateText)")
                }
            }
        }
        
        // Вызов DOM Fallback парсинга просмотров
        parseViewsDOMFallback(from: doc, apartment: apartment)
    }
    
    private func parseSellerInfo(from doc: Document, apartment: Apartment) {
        if apartment.sellerName != nil {
            return
        }
        
        let selectors = selectorsManager.config.detail.sellerSelectors
        
        for selector in selectors {
            if let sellerBlock = try? doc.select(selector).first() {
                if let name = try? sellerBlock.select("p, span, div").first(where: { (try? $0.text().isEmpty) == false })?.text() {
                    apartment.sellerName = name
                    print("  👤 Продавец (HTML fallback): \(name)")
                    return
                }
            }
        }
    }
    
    private func saveHTMLForDebug(html: String, apartmentId: String) {
        #if DEBUG
        let fileName = "apartment_\(apartmentId).html"
        if let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let filePath = documentsPath.appendingPathComponent(fileName)
            try? html.write(to: filePath, atomically: true, encoding: .utf8)
            print("  💾 HTML сохранён: \(filePath.path)")
        }
        #endif
    }
}

// MARK: - DetailParserProtocol

extension CianDetailParser: DetailParserProtocol {
    func parseJSON(jsonString: String, apartment: Apartment) {
        self.parseDetailJSON(jsonString: jsonString, apartment: apartment)
    }

    func parseHTML(html: String, apartment: Apartment) {
        self.parseDetailPage(html: html, apartment: apartment)
    }
}
