//
//  CianDetailParser.swift
//  ChianParser
//
//  Парсер детальной страницы объявления
//

import Foundation
import SwiftSoup

final class CianDetailParser {
    
    /// Парсит JSON из `window.__NEXT_DATA__` (предпочтительный метод) и обновляет объект Apartment.
    /// Вызывается из DetailPageLoader, когда JSON был извлечён напрямую через JS без загрузки полного HTML.
    static func parseDetailJSON(jsonString: String, apartment: Apartment) {
        let wrappedHTML = "<html><head><script id=\"__NEXT_DATA__\" type=\"application/json\">\(jsonString)</script></head><body></body></html>"
        if tryExtractFromJSON(html: wrappedHTML, apartment: apartment) {
            applyTitleFallback(apartment: apartment)
            apartment.isDetailedParsed = true
            apartment.lastUpdate = Date()
            print("✅ [Detail] \(apartment.id) цена=\(apartment.price) площадь=\(apartment.area.map { String($0) } ?? "?") метро=\(apartment.metro ?? "?")")
        } else {
            print("⚠️ [Detail] \(apartment.id) — не удалось распарсить JSON")
        }
    }
    
    /// Парсит детальную страницу объявления и обновляет данные объекта Apartment
    /// - Parameters:
    ///   - html: HTML-код страницы объявления
    ///   - apartment: Объект квартиры для обновления
    static func parseDetailPage(html: String, apartment: Apartment) {

        
        // DEBUG: Сохранение HTML для отладки (раскомментируйте при необходимости)
        // saveHTMLForDebug(html: html, apartmentId: apartment.id)
        
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
            apartment.isDetailedParsed = true
            apartment.lastUpdate = Date()
            
            print("✅ [Detail/HTML] \(apartment.id) цена=\(apartment.price) площадь=\(apartment.area.map { String($0) } ?? "?") метро=\(apartment.metro ?? "?")")
            
        } catch {
            print("❌ Ошибка парсинга детальной страницы: \(error)")
        }
    }
    
    // MARK: - JSON Detail Extraction
    
    private static func tryExtractFromJSON(html: String, apartment: Apartment) -> Bool {
        do {
            let doc = try SwiftSoup.parse(html)
            
            // Пробуем разные селекторы для JSON
            let jsonSelectors = [
                "script#__NEXT_DATA__",
                "script[type='application/json']",
                "script[id*='__']",
                "script:containsData(offerData)",
                "script:containsData(cianAd)"
            ]
            
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
            // Это аналогично уже исправленному пути для stats: offerData.offer.stats
            let offerNode = (offerData["offer"] as? [String: Any]) ?? offerData
            
            // 0. Цена и заголовок (обновляем из детальной страницы — более надёжно чем из поиска)
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
            
            // 1. Площадь (offerNode["totalArea"] → offerData["totalArea"] → fallback)
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
            
            // 5. Дом (расширенный парсинг — building может быть в offerData или offerNode)
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
            
            // 6. Адрес и метро (расширенное извлечение)

            // geo может быть в offerNode["geo"] или offerData["geo"]
            if let geo = (offerNode["geo"] as? [String: Any])
                ?? (offerData["geo"] as? [String: Any])
                ?? (findValue(forKey: "geo", in: jsonObject) as? [String: Any]) {
                // Пробуем разные способы получить адрес
                var addressComponents: [String] = []
                
                // Способ 1: Массив address с компонентами
                if let addressArray = geo["address"] as? [[String: Any]] {
                    addressComponents = addressArray.compactMap { 
                        ($0["fullName"] as? String) ?? ($0["title"] as? String) ?? ($0["name"] as? String) 
                    }
                }
                
                // Способ 2: Строка displayAddress
                if addressComponents.isEmpty {
                    if let displayAddr = (geo["displayAddress"] as? String) ?? (geo["userInputAddress"] as? String) {
                        addressComponents = [displayAddr]
                    }
                }
                
                // Способ 3: Разбираем отдельные поля (город, улица, дом)
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
                    // Fields: travelTime (minutes), travelType ("walk"/"transport")
                    // Treat time == 0 as "not specified" — Cian uses 0 as a sentinel value
                    if let time = extractInt(metro["travelTime"]) ?? extractInt(metro["time"]) ?? extractInt(metro["distance"]), time > 0 {
                        apartment.metroDistance = time
                    }
                    apartment.metroTransportType = (metro["travelType"] as? String) ?? (metro["transportType"] as? String)


                }
            }
            
            // Если всё еще пусто, ищем поле address в корне или pageProps
            if apartment.address.isEmpty || apartment.address == "Адрес не указан" {
                // Брутфорс через рекурсивный поиск
                let possibleKeys = ["displayAddress", "userInputAddress", "address", "fullAddress", "location"]
                for key in possibleKeys {
                    if let addr = findValue(forKey: key, in: jsonObject) as? String, !addr.isEmpty {
                        apartment.address = addr
                        break
                    }
                }
            }
            
            // 7. Статистика (расширенная)
            // offerNode уже определён выше как offerData["offer"]
            // stats может лежать как в offerData["offer"]["stats"], так и прямо в offerData["stats"]
            let statsNode = (offerNode["stats"] as? [String: Any])
                ?? (offerData["stats"] as? [String: Any])
            
            // Вариант А: числа напрямую (расширенный набор ключей)
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
            
            // Вариант Б: форматированная строка "1709 просмотров, 44 за сегодня"
            if apartment.viewsTotal == nil || apartment.viewsToday == nil {
                let formattedStr = statsNode?["totalViewsFormattedString"] as? String
                    ?? offerNode["totalViewsFormattedString"] as? String
                    ?? offerData["totalViewsFormattedString"] as? String
                if let formatted = formattedStr {
                    parseViewsFormattedString(formatted, apartment: apartment)
                }
            }
            
            // Вариант В: рекурсивный поиск (fallback)
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

            // Вариант Г: поиск по всему JSON-строке (last resort)
            // Циан может хранить строку в разных полях — ищем любую "N просмотров · M за сегодня"
            if apartment.viewsToday == nil {
                parseViewsFormattedString(jsonString, apartment: apartment)
            }

            // Вариант Д: sentinel-поля __domViewsTotal / __domViewsToday
            // JS-скрипт вытащил числа просмотров прямо из DOM и записал в корень JSON.
            // Это страховочный вариант, когда stats вообще нет в __NEXT_DATA__.
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

            let descLower = apartment.apartmentDescription?.lowercased() ?? ""
            let depositPhrases = ["залог внесен", "залог внесён", "задаток внесен", "задаток внесён",
                                  "аванс внесен", "аванс внесён", "внесен залог", "внесён залог",
                                  "внесен задаток", "внесён задаток", "внесен аванс", "внесён аванс"]
            apartment.isDepositPaid = depositPhrases.contains { descLower.contains($0) }

            // Дата публикации
            let publishedDateStr = (offerNode["publishedDate"] as? String)
                ?? (offerData["publishedDate"] as? String)
            if let dateStr = publishedDateStr {
                let formatter = ISO8601DateFormatter()
                apartment.publishedDate = formatter.date(from: dateStr)
            } else if let ts = (offerNode["addedTimestamp"] as? TimeInterval) ?? (offerData["addedTimestamp"] as? TimeInterval) {
                apartment.publishedDate = Date(timeIntervalSince1970: ts)
            }
            
            // 8. Продавец (расширенный)
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
    private static func findValue(forKey key: String, in dictionary: [String: Any]) -> Any? {
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
    
    // Парсинг форматированной строки просмотров: "1709 просмотров, 44 за сегодня"
    // или "446 просмотров · 513 за сегодня" (разделитель может быть запятой или средней точкой ·)
    private static func parseViewsFormattedString(_ text: String, apartment: Apartment) {
        // Cian formats totals with spaces/NBSP (\u00A0): "1\u{00A0}709 просмотров, 44 за сегодня".
        // [\d \u00A0] captures both regular spaces and non-breaking spaces used as thousands separators.
        // Group 1 = total views (may have spaces/NBSP inside), Group 2 = today views.

        // Паттерн 1: полная строка с общим числом + числом за сегодня
        let fullPattern = "(\\d[\\d \\u00A0]*\\d|\\d)\\s*просмотр[^,·\\n]*[,·]\\s*(\\d+)\\s*за сегодня"
        if let regex = try? NSRegularExpression(pattern: fullPattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) {
            if apartment.viewsTotal == nil, let totalRange = Range(match.range(at: 1), in: text) {
                apartment.viewsTotal = Int(String(text[totalRange]).filter(\.isNumber))
            }
            if apartment.viewsToday == nil, let todayRange = Range(match.range(at: 2), in: text) {
                apartment.viewsToday = Int(text[todayRange])
            }
            return
        }

        // Паттерн 2 (fallback): только «N за сегодня» без общего числа
        // Например: "44 за сегодня" без предшествующего блока просмотров
        let todayOnlyPattern = "(\\d+)\\s*за сегодня"
        if apartment.viewsToday == nil,
           let regex = try? NSRegularExpression(pattern: todayOnlyPattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let todayRange = Range(match.range(at: 1), in: text) {
            apartment.viewsToday = Int(text[todayRange])
        }
    }
    
    // Fallback из заголовка
    private static func applyTitleFallback(apartment: Apartment) {
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
    
    // MARK: - Вспомогательные методы
    
    private static func extractDouble(_ value: Any?) -> Double? {
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        if let n = value as? NSNumber { return n.doubleValue }
        if let s = value as? String { return Double(s.replacingOccurrences(of: ",", with: ".")) }
        return nil
    }
    
    private static func extractInt(_ value: Any?) -> Int? {
        if let i = value as? Int { return i }
        if let n = value as? NSNumber { return n.intValue }
        if let d = value as? Double { return Int(d) }
        if let s = value as? String {
            let digits = s.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
            return Int(digits)
        }
        return nil
    }
    
    // MARK: - HTML Fallbacks (Старые методы)
    
    private static func parseMainCharacteristics(from doc: Document, apartment: Apartment) {
        print("  🔍 DEBUG: Начинаю HTML-парсинг характеристик...")
        
        // Пробуем разные селекторы для блока характеристик
        let selectors = [
            "[data-name='OfferSummaryInfoItem']",
            "[data-testid='object-summary-info-item']",
            ".a10a3f92e9--item--_ipjK",
            "[class*='item']"
        ]
        
        var foundItems = false
        
        for selector in selectors {
            if let items = try? doc.select(selector), !items.isEmpty() {
                print("  ✓ Найдено элементов по селектору '\(selector)': \(items.count)")
                foundItems = true
                
                for item in items {
                    var title = ""
                    var value = ""
                    
                    // Способ 1: дочерние элементы (надёжнее всего для SwiftSoup)
                    // data-name="OfferSummaryInfoItem" обычно имеет структуру:
                    //   <div> <span>Название</span> <span>Значение</span> </div>
                    let children = item.children()
                    if children.count >= 2 {
                        title = (try? children.get(0).text()) ?? ""
                        value = (try? children.get(children.count - 1).text()) ?? ""
                    } else if children.count == 1 {
                        // Один дочерний элемент — значит у него самого есть дети
                        let grandchildren = children.get(0).children()
                        if grandchildren.count >= 2 {
                            title = (try? grandchildren.get(0).text()) ?? ""
                            value = (try? grandchildren.get(grandchildren.count - 1).text()) ?? ""
                        }
                    }
                    
                    // Способ 2: data-mark атрибуты (на случай если Циан их вернул)
                    if title.isEmpty {
                        title = (try? item.select("[data-mark='OfferSummaryInfoItem/Title']").first()?.text()) ?? ""
                    }
                    if value.isEmpty {
                        value = (try? item.select("[data-mark='OfferSummaryInfoItem/Value']").first()?.text()) ?? ""
                    }
                    
                    // Способ 3: если весь текст — разделяем по длинному пробелу / специальным символам
                    if title.isEmpty || value.isEmpty {
                        let fullText = (try? item.text()) ?? ""
                        // SwiftSoup склеивает текст через пробелы — ищем шаблон "Слово ... цифра/слово"
                        // Делим по последнему существенному слову
                        let t = fullText.trimmingCharacters(in: .whitespaces)
                        // Если всё в одной строке, делим на половину по последнему числовому токену
                        if !t.isEmpty {
                            if title.isEmpty { title = t }
                            if value.isEmpty { value = t }
                        }
                    }
                    
                    // Если ничего не нашли, пропускаем
                    if title.isEmpty && value.isEmpty {
                        continue
                    }

                    
                    let titleLower = title.lowercased()
                    let valueCleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    // Логируем что нашли
                    if !title.isEmpty && !value.isEmpty {
                        print("  📋 \(title): \(valueCleaned)")
                    }
                    
                    // Парсим по ключевым словам
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
                
                break // Нашли подходящий селектор
            }
        }
        
        if !foundItems {
            print("  ⚠️ Не найдено элементов характеристик через стандартные селекторы")
            print("  🔍 Пробую альтернативный парсинг...")
        }
        
        // Альтернативный селектор для характеристик
        if let allItems = try? doc.select("[data-name='GeneralInformation'] li, [data-name='AboutFlatItem'], .object_descr_params li") {
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
    
    private static func parseDescription(from doc: Document, apartment: Apartment) {
        if apartment.apartmentDescription != nil && !apartment.apartmentDescription!.isEmpty {
            return // Уже есть из JSON
        }
        
        // Несколько селекторов для описания
        let selectors = [
            "[data-name='Description']",
            "[itemprop='description']",
            ".description_text",
            "[class*='description']"
        ]
        
        for selector in selectors {
            if let desc = try? doc.select(selector).first()?.text(), !desc.isEmpty {
                apartment.apartmentDescription = desc
                print("  📝 Описание найдено (длина: \(desc.count) символов)")
                return
            }
        }
    }
    
    private static func parseImages(from doc: Document, apartment: Apartment) {
        if !apartment.imageURLs.isEmpty {
            return // Уже есть из JSON
        }
        
        print("  🔍 DEBUG: Поиск изображений...")
        var images: [String] = []
        
        // Способ 1: Прямой поиск img с атрибутами src и data-src
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
                // Проверяем srcset
                if let srcset = try? img.attr("srcset"), !srcset.isEmpty {
                    let urls = srcset.components(separatedBy: ",").compactMap { component -> String? in
                        let url = component.trimmingCharacters(in: .whitespaces).components(separatedBy: " ").first
                        return url?.contains("cian") == true ? url : nil
                    }
                    images.append(contentsOf: urls)
                }
            }
        }
        
        // Способ 2: Поиск фоновых изображений в style-атрибутах
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
        
        // Способ 3: Брутфорс - ищем все URL с cian.site в HTML
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
    
    private static func parseHouseInfo(from doc: Document, apartment: Apartment) {
        // data-name="BtiHouseData" и data-name="HouseData" удалены с сайта, используем поиск по тексту
        // Ищем год и материал через универсальные паттерны
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
    
    private static func parseLocation(from doc: Document, apartment: Apartment) {
        print("  🔍 DEBUG: Парсинг адреса и метро...")
        
        // Адрес, если ещё не получен
        if apartment.address.isEmpty || apartment.address == "Адрес не указан" {
            let addressSelectors = [
                "[data-name='Geo']",
                "[itemprop='address']",
                "[class*='address']",
                "h1[itemprop='name']"
            ]
            
            for selector in addressSelectors {
                if let addressElement = try? doc.select(selector).first() {
                    if let addr = try? addressElement.text(), !addr.isEmpty {
                        // Очищаем адрес от мусора (например, "На карте", метро и т.д.)
                        var cleanedAddr = addr
                        cleanedAddr = cleanedAddr.replacingOccurrences(of: "На карте", with: "")
                        
                        // Убираем информацию о метро (обычно идёт после адреса)
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
        
        // Метро
        if apartment.metro == nil {
            let metroSelectors = [
                "[data-name='UndergroundStation']",
                "[class*='underground']",
                "[class*='metro']",
                "a[href*='metro']"
            ]
            
            for selector in metroSelectors {
                if let metroElements = try? doc.select(selector) {
                    for elem in metroElements {
                        if let metroText = try? elem.text(), !metroText.isEmpty {
                            // Извлекаем название метро (обычно первое слово или всё до чисел)
                            let components = metroText.components(separatedBy: CharacterSet.decimalDigits)
                            if let name = components.first?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
                                apartment.metro = name
                                
                                // Пробуем найти время в пути
                                let timeRegex = try? NSRegularExpression(pattern: #"(\d+)\s*мин"#)
                                if let match = timeRegex?.firstMatch(in: metroText, range: NSRange(metroText.startIndex..., in: metroText)),
                                   let range = Range(match.range(at: 1), in: metroText) {
                                    apartment.metroDistance = Int(metroText[range])
                                }
                                
                                print("  🚇 Метро: \(apartment.metro ?? "н/д")\(apartment.metroDistance != nil ? ", \(apartment.metroDistance!) мин" : "")")
                                break
                            }
                        }
                    }
                    if apartment.metro != nil { break }
                }
            }
        }
    }
    
    private static func parseStatistics(from doc: Document, apartment: Apartment) {
        // ПРИМЕЧАНИЕ: [data-name="OfferStats"] удален с сайта.
        // Данные о просмотрах извлекаются из JSON в tryExtractFromJSON.
        // Этот HTML fallback обрабатывает только дату публикации.
        
        // Дата публикации
        if apartment.publishedDate == nil {
            if let dateElement = try? doc.select("time[datetime]").first() {
                if let dateStr = try? dateElement.attr("datetime") {
                    let formatter = ISO8601DateFormatter()
                    apartment.publishedDate = formatter.date(from: dateStr)
                } else if let dateText = try? dateElement.text() {
                    // Попробуем распарсить текстовую дату
                    print("  📅 Дата публикации (текст): \(dateText)")
                }
            }
        }
    }
    
    private static func parseSellerInfo(from doc: Document, apartment: Apartment) {
        if apartment.sellerName != nil {
            return // Уже есть из JSON
        }
        
        // ПРИМЕЧАНИЕ: [data-name="OfferOwner"] и [data-name="Agent"] удалены с сайта.
        // Используем data-automation и семантические якоря.
        let selectors = [
            "[data-automation='agent-info']",
            "[data-automation='seller-info']",
            "[class*='--agent-info--']",
            "[class*='--owner-info--']"
        ]
        
        for selector in selectors {
            if let sellerBlock = try? doc.select(selector).first() {
                // Ищем имя как первый крупный текстовый элемент внутри блока
                if let name = try? sellerBlock.select("p, span, div").first(where: { (try? $0.text().isEmpty) == false })?.text() {
                    apartment.sellerName = name
                    print("  👤 Продавец (HTML fallback): \(name)")
                    return
                }
            }
        }
    }
    
    // MARK: - Debug Helpers
    
    /// Сохраняет HTML в файл для отладки (только для разработки)
    private static func saveHTMLForDebug(html: String, apartmentId: String) {
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
        CianDetailParser.parseDetailJSON(jsonString: jsonString, apartment: apartment)
    }

    func parseHTML(html: String, apartment: Apartment) {
        CianDetailParser.parseDetailPage(html: html, apartment: apartment)
    }
}
