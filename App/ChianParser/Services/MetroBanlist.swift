//
//  MetroBanlist.swift
//  ChianParser
//
//  Default metro station banlist: MCD1–MCD4 stations that have NO regular metro counterpart.
//  Stations that share a name with a metro station are intentionally excluded.
//

import Foundation

enum MetroBanlist {

    static let appStorageKey = "metroBanlistJSON"

    // MARK: - Default Stations

    /// MCD-only stations (no regular metro station with the same name).
    static let defaultStations: [String] = [
        // MCD1 (Одинцово — Лобня)
        "Одинцово", "Сколково", "Инновационный центр", "Немчиновка", "Победа",
        "Рабочий Посёлок", "Тестовская", "Лианозово", "Марк", "Лось",
        "Лосиноостровская", "Северянин", "Яуза", "Лобня",

        // MCD2 (Нахабино — Подольск)
        "Нахабино", "Павшино", "Красногорская", "Опалиха", "Снегири",
        "Дедовск", "Угрешская", "Депо", "Кленовый бульвар", "Нижние Котлы",
        "Красный строитель", "Покровское", "Битца", "Бутово", "Щербинка",
        "Остафьево", "Силикатная", "Подольск",

        // MCD3 (Зеленоград-Крюково — Раменское)
        "Зеленоград-Крюково", "Крюково", "Фирсановка", "Химки",
        "Водники", "Долгопрудная", "Новодачная", "Шереметьевская",
        "Останкино", "Карачарово", "Люберцы", "Малаховка",
        "Быково", "Ильинское", "Раменское",

        // MCD4 (Апрелевка — Железнодорожная)
        "Апрелевка", "Алабино", "Кокошкино", "Санино", "Крёкшино",
        "Толстопальцево", "Внуково", "Солнечная", "Переделкино",
        "Мичуринец", "Сетунь", "Каланчёвская", "Реутово", "Железнодорожная"
    ]

    static let defaultJSON: String = encode(Set(defaultStations))

    // MARK: - Serialization

    static func decode(from json: String) -> Set<String> {
        guard let data = json.data(using: .utf8),
              let array = try? JSONDecoder().decode([String].self, from: data)
        else { return Set(defaultStations) }
        return Set(array)
    }

    static func encode(_ stations: Set<String>) -> String {
        let sorted = stations.sorted()
        guard let data = try? JSONEncoder().encode(sorted),
              let json = String(data: data, encoding: .utf8)
        else { return defaultJSON }
        return json
    }
}
