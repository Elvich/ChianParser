//
//  DistrictRanking.swift
//  ChianParser
//
//  Manages per-district FlipScore location points.
//
//  Score semantics:
//    -1      → ban: apartments in this district/okrug are always hidden
//     0…20   → locationScore used in FlipScore (max 20 pts)
//
//  Default scoring is okrug-level (all districts in one okrug share the same default),
//  but each district can be customized individually in Settings.
//

import Foundation

struct DistrictRanking {

    static let scoresKey = "districtScoresJSON"

    // MARK: - Default Scores (center → outskirts)

    static let defaultScores: [String: Int] = {
        var s: [String: Int] = [:]

        // ЦАО — 20 pts
        for d in ["Арбат", "Хамовники", "Тверской", "Якиманка", "Замоскворечье",
                  "Пресненский", "Мещанский", "Таганский", "Басманный", "Красносельский"] {
            s[d] = 20
        }
        // ЮЗАО — 17 pts
        for d in ["Гагаринский", "Ломоносовский", "Академический", "Черёмушки", "Обручевский",
                  "Котловка", "Зюзино", "Коньково", "Ясенево", "Тёплый Стан",
                  "Северное Бутово", "Южное Бутово", "Внуково"] {
            s[d] = 17
        }
        // ЗАО — 15 pts
        for d in ["Дорогомилово", "Раменки", "Проспект Вернадского", "Тропарёво-Никулино",
                  "Очаково-Матвеевское", "Крылатское", "Фили-Давыдково", "Филёвский Парк",
                  "Кунцево", "Можайский", "Солнцево", "Ново-Переделкино"] {
            s[d] = 15
        }
        // СЗАО — 13 pts
        for d in ["Покровское-Стрешнево", "Хорошёво-Мнёвники", "Щукино", "Строгино",
                  "Северное Тушино", "Южное Тушино", "Митино", "Куркино"] {
            s[d] = 13
        }
        // САО — 11 pts
        for d in ["Сокол", "Беговой", "Аэропорт", "Хорошёвский", "Савёловский",
                  "Войковский", "Тимирязевский", "Головинский", "Коптево",
                  "Левобережный", "Дмитровский", "Бескудниковский",
                  "Восточное Дегунино", "Западное Дегунино", "Молжаниновский", "Ховрино"] {
            s[d] = 11
        }
        // СВАО — 9 pts
        for d in ["Марьина роща", "Останкинский", "Алексеевский", "Ростокино",
                  "Марфино", "Свиблово", "Бутырский", "Отрадное",
                  "Бабушкинский", "Ярославский", "Южное Медведково", "Северное Медведково",
                  "Алтуфьевский", "Лосиноостровский", "Бибирево", "Лианозово", "Северный"] {
            s[d] = 9
        }
        // ВАО — 7 pts
        for d in ["Сокольники", "Преображенское", "Богородское", "Соколиная Гора",
                  "Измайлово", "Северное Измайлово", "Восточное Измайлово",
                  "Перово", "Новогиреево", "Метрогородок",
                  "Ивановское", "Вешняки", "Косино-Ухтомский", "Новокосино",
                  "Гольяново", "Восточный"] {
            s[d] = 7
        }
        // ЮВАО — 5 pts
        for d in ["Лефортово", "Нижегородский", "Текстильщики", "Кузьминки",
                  "Рязанский", "Люблино", "Марьино", "Печатники",
                  "Южнопортовый", "Выхино-Жулебино", "Некрасовка", "Капотня"] {
            s[d] = 5
        }
        // ЮАО — 4 pts
        for d in ["Даниловский", "Донской", "Нагатинский Затон", "Нагатино-Садовники",
                  "Нагорный", "Москворечье-Сабурово", "Царицыно",
                  "Чертаново Северное", "Чертаново Центральное", "Чертаново Южное",
                  "Орехово-Борисово Северное", "Орехово-Борисово Южное",
                  "Братеево", "Зябликово", "Бирюлёво Восточное", "Бирюлёво Западное"] {
            s[d] = 4
        }
        // Новая Москва + Зеленоград — ban (checked against apt.okrug)
        s["ТАО"] = -1
        s["НАО"] = -1
        s["Зеленоград"] = -1

        return s
    }()

    static var defaultScoresJSON: String { encodeScores(defaultScores) }

    // MARK: - Encode / Decode

    static func decodeScores(from json: String) -> [String: Int] {
        guard let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: Int].self, from: data) else {
            return defaultScores
        }
        return decoded
    }

    static func encodeScores(_ scores: [String: Int]) -> String {
        (try? String(data: JSONEncoder().encode(scores), encoding: .utf8)) ?? "{}"
    }

    // MARK: - Sorted Display List

    /// All district/okrug entries sorted for display: banned (score -1) last, then by score descending, then by name.
    static func sortedEntries(from scores: [String: Int]) -> [(name: String, score: Int)] {
        scores.map { (name: $0.key, score: $0.value) }
            .sorted { lhs, rhs in
                if lhs.score == -1 && rhs.score != -1 { return false }
                if lhs.score != -1 && rhs.score == -1 { return true }
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return lhs.name < rhs.name
            }
    }
}
