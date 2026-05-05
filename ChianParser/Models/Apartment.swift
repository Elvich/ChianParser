//
//  Apartment.swift
//  ChianParser
//

import Foundation
import SwiftData

@Model
final class Apartment {
    @Attribute(.unique) var id: String // Уникальный ID объявления на Циан
    var title: String
    var price: Int
    var url: String
    var address: String
    
    // Технические характеристики
    var area: Double?           // Площадь общая
    var livingArea: Double?     // Площадь жилая
    var kitchenArea: Double?    // Площадь кухни
    var floor: Int?             // Этаж
    var totalFloors: Int?       // Всего этажей в доме
    var roomsCount: Int?        // Количество комнат
    var houseMaterial: String?  // Материал дома (монолит, кирпич и т.д.)
    var buildingType: String?   // Тип дома
    var yearBuilt: Int?         // Год постройки
    
    // Дополнительные параметры
    var ceilingHeight: Double?  // Высота потолков
    var bathroomType: String?   // Санузел (совмещённый/раздельный)
    var balcony: String?        // Балкон/лоджия
    var windowView: String?     // Вид из окон
    var repair: String?         // Ремонт
    var furniture: Bool?        // Есть мебель
    
    // Инфраструктура
    var metro: String?              // Ближайшее метро
    var metroDistance: Int?         // Расстояние до метро (минуты)
    var metroTransportType: String? // Тип транспорта: "walk" или "transport"
    var parking: String?            // Парковка
    var elevator: String?           // Лифт
    
    // Описание и фото
    var apartmentDescription: String? // Полное описание
    var imageURLs: [String] = []      // URL фотографий
    
    // Информация о продавце
    var sellerType: String?     // Тип продавца (собственник, агент)
    var sellerName: String?     // Имя продавца
    
    // Статистика
    var viewsToday: Int?        // Просмотров сегодня
    var viewsTotal: Int?        // Просмотров всего
    var publishedDate: Date?    // Дата публикации объявления
    
    // Флаг детального парсинга
    var isDetailedParsed: Bool = false // Был ли выполнен детальный парсинг

    // Авто-детекция особых условий (устанавливается парсером)
    var isAuction: Bool = false      // Объявление является аукционом
    var isDepositPaid: Bool = false  // В описании упоминается внесённый залог/задаток

    // Тип объекта (устанавливается парсером из JSON; вычисляемые свойства дополняют эвристиками)
    var isStudioFlag: Bool = false      // Явно определено как студия из JSON (flatType/category)
    var isApartmentsFlag: Bool = false  // Явно определено как апартаменты из JSON (category)

    /// Студия — из JSON или по заголовку/количеству комнат (работает без детального парсинга)
    var isStudio: Bool {
        isStudioFlag
            || (roomsCount == 0)
            || title.lowercased().hasPrefix("студия")
    }

    /// Апартаменты (не жильё) — из JSON или по заголовку/описанию
    var isApartments: Bool {
        isApartmentsFlag
            || title.lowercased().contains("апартамент")
            || (apartmentDescription?.lowercased().contains("апартамент") ?? false)
    }

    // MARK: - Workflow (статус, заметки, ожидание)

    /// Current workflow status (raw string for SwiftData persistence)
    var statusRaw: String = ApartmentStatus.new.rawValue

    /// User notes for this apartment
    var notes: String = ""

    /// JSON-encoded WaitingCondition — nil when status != .waiting
    var waitingConditionJSON: String? = nil

    // MARK: - Computed workflow helpers

    /// Strongly-typed status backed by statusRaw
    var status: ApartmentStatus {
        get { ApartmentStatus(rawValue: statusRaw) ?? .new }
        set { statusRaw = newValue.rawValue }
    }

    /// Decoded WaitingCondition backed by waitingConditionJSON
    var waitingCondition: WaitingCondition? {
        get {
            guard let json = waitingConditionJSON,
                  let data = json.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode(WaitingCondition.self, from: data)
        }
        set {
            guard let condition = newValue else {
                waitingConditionJSON = nil
                return
            }
            waitingConditionJSON = (try? String(data: JSONEncoder().encode(condition), encoding: .utf8)) ?? nil
        }
    }
    
    // Географическая классификация (вычисляется при парсинге, хранится для фильтрации)
    var okrug: String? = nil      // Административный округ Москвы (ЦАО, ЮВАО и т.д.)
    var district: String? = nil   // Район Москвы (р-н ..., напр. «Арбат», «Чертаново Северное»)

    // Служебные даты
    var dateAdded: Date         // Когда мы впервые нашли это объявление
    var lastUpdate: Date        // Когда парсер последний раз обновлял данные
    var lastSeenInSearch: Date  // Когда объявление последний раз появлялось в поиске
    
    // История изменения цен (связанная модель)
    @Relationship(deleteRule: .cascade) var priceHistory: [PricePoint] = []
    
    init(id: String, title: String, price: Int, url: String, address: String) {
        self.id = id
        self.title = title
        self.price = price
        self.url = url
        self.address = address
        self.dateAdded = Date()
        self.lastUpdate = Date()
        self.lastSeenInSearch = Date()
        self.priceHistory = [PricePoint(price: price, date: Date())]
    }
}

@Model
final class PricePoint {
    var price: Int
    var date: Date
    
    init(price: Int, date: Date = Date()) {
        self.price = price
        self.date = date
    }
}
