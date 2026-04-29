//
//  FlipAnalyzer.swift
//  ChianParser
//
//  Computes FlipScoreResult for apartments based on market benchmark data.
//
//  Scoring breakdown (total 100 pts):
//    Price vs benchmark   40 pts  — deeper discount → higher score
//    Metro proximity      25 pts  — walk < 5 min is best
//    Floor position       20 pts  — avoid 1st and last floor
//    Area                 15 pts  — larger is better
//

import Foundation

final class FlipAnalyzer {}

// MARK: - FlipAnalyzerProtocol

extension FlipAnalyzer: FlipAnalyzerProtocol {

    func buildBenchmark(from apartments: [Apartment]) -> BenchmarkContext {
        var groups: [String: [Double]] = [:]
        var allPricesSqm: [Double] = []

        for apt in apartments {
            guard let area = apt.area, area > 10, apt.price > 0 else { continue }
            let priceSqm = Double(apt.price) / area
            let okrug = extractOkrug(from: apt.address)
            groups[okrug, default: []].append(priceSqm)
            allPricesSqm.append(priceSqm)
        }

        let minSamples = 5
        var byOkrug: [String: OkrugBenchmark] = [:]
        for (okrug, prices) in groups where prices.count >= minSamples {
            byOkrug[okrug] = OkrugBenchmark(
                medianPriceSqm: median(of: prices),
                sampleSize: prices.count,
                okrug: okrug
            )
        }

        let globalMedian = allPricesSqm.count >= minSamples ? median(of: allPricesSqm) : nil

        return BenchmarkContext(
            byOkrug: byOkrug,
            globalMedian: globalMedian,
            globalSampleSize: allPricesSqm.count
        )
    }

    func analyze(apartment: Apartment, benchmark: BenchmarkContext, thresholds: DemandThresholds) -> FlipScoreResult {
        let priceSqm: Double? = {
            guard let area = apartment.area, area > 10, apartment.price > 0 else { return nil }
            return Double(apartment.price) / area
        }()

        let okrug = extractOkrug(from: apartment.address)
        let okrugBenchmark = benchmark.byOkrug[okrug]
        let benchmarkSqm = okrugBenchmark?.medianPriceSqm ?? benchmark.globalMedian
        let benchmarkOkrug = okrugBenchmark?.okrug
        let sampleSize = okrugBenchmark?.sampleSize ?? benchmark.globalSampleSize

        let priceScore = computePriceScore(priceSqm: priceSqm, benchmarkSqm: benchmarkSqm)
        let metroScore = computeMetroScore(apartment: apartment)
        let floorScore = computeFloorScore(apartment: apartment)
        let areaScore  = computeAreaScore(apartment: apartment)

        let total = priceScore + metroScore + floorScore + areaScore

        let (demandLevel, viewsPerDay) = computeDemand(apartment: apartment, thresholds: thresholds)

        return FlipScoreResult(
            totalScore: min(total, 100),
            priceScore: priceScore,
            metroScore: metroScore,
            floorScore: floorScore,
            areaScore: areaScore,
            priceSqm: priceSqm,
            benchmarkSqm: benchmarkSqm,
            benchmarkOkrug: benchmarkOkrug,
            benchmarkSampleSize: sampleSize,
            demandLevel: demandLevel,
            viewsPerDay: viewsPerDay
        )
    }
}

// MARK: - Score Components

private extension FlipAnalyzer {

    /// Price score: max 40 pts.
    /// Discount bands: ≥25% off → 40, ≥15% → 32, ≥10% → 24, ≥5% → 16, 0% → 8, premium → 0.
    func computePriceScore(priceSqm: Double?, benchmarkSqm: Double?) -> Int {
        guard let priceSqm, let benchmarkSqm, benchmarkSqm > 0 else { return 6 }
        let discount = (benchmarkSqm - priceSqm) / benchmarkSqm
        switch discount {
        case 0.25...: return 40
        case 0.15...: return 32
        case 0.10...: return 24
        case 0.05...: return 16
        case 0.0...:  return 8
        default:      return 0
        }
    }

    /// Metro score: max 25 pts.
    /// Walk ≤5 min → 25, walk ≤10 → 20, walk ≤15 → 15, walk ≤20 → 10,
    /// transport ≤10 → 13, transport ≤20 → 8, no data → 0.
    func computeMetroScore(apartment: Apartment) -> Int {
        guard let distance = apartment.metroDistance, distance > 0 else { return 0 }
        let isWalk = apartment.metroTransportType == "walk"
        if isWalk {
            switch distance {
            case ...5:  return 25
            case ...10: return 20
            case ...15: return 15
            case ...20: return 10
            default:    return 5
            }
        } else {
            switch distance {
            case ...10: return 13
            case ...20: return 8
            default:    return 3
            }
        }
    }

    /// Floor score: max 20 pts.
    /// First floor → 0, last floor → 5, near-last → 13, all other floors → 20.
    func computeFloorScore(apartment: Apartment) -> Int {
        guard let floor = apartment.floor, let total = apartment.totalFloors, total > 0 else { return 7 }
        if floor == 1       { return 0 }
        if floor == total   { return 5 }
        if floor == total - 1 { return 13 }
        return 20
    }

    /// Area score: max 15 pts. ≥60 m² → 15, ≥45 → 11, ≥30 → 6, <30 → 2.
    func computeAreaScore(apartment: Apartment) -> Int {
        guard let area = apartment.area else { return 0 }
        switch area {
        case 60...: return 15
        case 45...: return 11
        case 30...: return 6
        default:    return 2
        }
    }

    /// Compute demand level from views/day.
    func computeDemand(apartment: Apartment, thresholds: DemandThresholds) -> (DemandLevel, Double?) {
        guard let viewsToday = apartment.viewsToday, viewsToday > 0 else {
            if let total = apartment.viewsTotal, total > 0, let published = apartment.publishedDate {
                let days = max(1.0, Date().timeIntervalSince(published) / 86400)
                let perDay = Double(total) / days
                return (demandLevel(perDay: perDay, thresholds: thresholds), perDay)
            }
            return (.noData, nil)
        }
        let perDay = Double(viewsToday)
        return (demandLevel(perDay: perDay, thresholds: thresholds), perDay)
    }

    func demandLevel(perDay: Double, thresholds: DemandThresholds) -> DemandLevel {
        switch Int(perDay) {
        case thresholds.hot...:      return .hot
        case thresholds.market...:   return .market
        case thresholds.moderate...: return .moderate
        default:                     return .low
        }
    }
}

// MARK: - Okrug Extraction

extension FlipAnalyzer {

    /// Extract the Moscow okrug name from an address string.
    /// Order matters: 4-char abbreviations must be checked before their 3-char substrings
    /// (e.g. "ЮВАО" contains "ВАО", "СЗАО" contains "ЗАО").
    func extractOkrug(from address: String) -> String {
        // Pass 1: abbreviations (4-char before 3-char to avoid substring collision)
        let okrugs = [
            "СВАО", "ЮВАО", "ЮЗАО", "СЗАО",    // 4-char — checked first
            "ЦАО", "САО", "ВАО", "ЮАО", "ЗАО", // 3-char
            "ТАО", "НАО", "Зеленоград"
        ]
        for okrug in okrugs where address.contains(okrug) {
            return okrug
        }

        // Pass 2: full Russian names (Cian often uses full names in geo.address JSON).
        // Compound names (e.g. "Северо-Восточный") contain the simple name ("Восточный")
        // as a suffix, so compound ones must come first.
        let fullNames: [(String, String)] = [
            ("Северо-Восточный административный округ", "СВАО"),
            ("Юго-Восточный административный округ",   "ЮВАО"),
            ("Северо-Западный административный округ", "СЗАО"),
            ("Юго-Западный административный округ",    "ЮЗАО"),
            ("Центральный административный округ",     "ЦАО"),
            ("Северный административный округ",        "САО"),
            ("Восточный административный округ",       "ВАО"),
            ("Южный административный округ",           "ЮАО"),
            ("Западный административный округ",        "ЗАО"),
            ("Троицкий административный округ",        "ТАО"),
            ("Новомосковский административный округ",  "НАО"),
            ("Зеленоградский административный округ",  "Зеленоград"),
        ]
        for (fullName, okrug) in fullNames where address.contains(fullName) {
            return okrug
        }
        // Full mapping of Moscow districts to okrugs
        let knownDistricts: [String: String] = [
            // ЦАО
            "Арбат": "ЦАО", "Басманный": "ЦАО", "Замоскворечье": "ЦАО",
            "Красносельский": "ЦАО", "Мещанский": "ЦАО", "Пресня": "ЦАО",
            "Пресненский": "ЦАО", "Таганский": "ЦАО", "Тверской": "ЦАО",
            "Хамовники": "ЦАО", "Якиманка": "ЦАО",
            // САО
            "Аэропорт": "САО", "Беговой": "САО", "Бескудниковский": "САО",
            "Войковский": "САО", "Восточное Дегунино": "САО", "Головинский": "САО",
            "Дмитровский": "САО", "Западное Дегунино": "САО", "Коптево": "САО",
            "Левобережный": "САО", "Молжаниновский": "САО", "Савёловский": "САО",
            "Сокол": "САО", "Тимирязевский": "САО", "Ховрино": "САО", "Хорошёвский": "САО",
            // СВАО
            "Алексеевский": "СВАО", "Алтуфьевский": "СВАО", "Бабушкинский": "СВАО",
            "Бибирево": "СВАО", "Бутырский": "СВАО", "Лианозово": "СВАО",
            "Лосиноостровский": "СВАО", "Марфино": "СВАО", "Марьина роща": "СВАО",
            "Останкинский": "СВАО", "Отрадное": "СВАО", "Ростокино": "СВАО",
            "Свиблово": "СВАО", "Северное Медведково": "СВАО", "Северный": "СВАО",
            "Южное Медведково": "СВАО", "Ярославский": "СВАО",
            // ВАО
            "Богородское": "ВАО", "Вешняки": "ВАО", "Восточное Измайлово": "ВАО",
            "Восточный": "ВАО", "Гольяново": "ВАО", "Ивановское": "ВАО",
            "Измайлово": "ВАО", "Косино-Ухтомский": "ВАО", "Метрогородок": "ВАО",
            "Новогиреево": "ВАО", "Новокосино": "ВАО", "Перово": "ВАО",
            "Преображенское": "ВАО", "Северное Измайлово": "ВАО",
            "Соколиная Гора": "ВАО", "Сокольники": "ВАО",
            // ЮВАО
            "Выхино-Жулебино": "ЮВАО", "Капотня": "ЮВАО", "Кузьминки": "ЮВАО",
            "Лефортово": "ЮВАО", "Люблино": "ЮВАО", "Марьино": "ЮВАО",
            "Некрасовка": "ЮВАО", "Нижегородский": "ЮВАО", "Печатники": "ЮВАО",
            "Рязанский": "ЮВАО", "Текстильщики": "ЮВАО", "Южнопортовый": "ЮВАО",
            // ЮАО
            "Бирюлёво Восточное": "ЮАО", "Бирюлёво Западное": "ЮАО",
            "Братеево": "ЮАО", "Даниловский": "ЮАО", "Донской": "ЮАО",
            "Зябликово": "ЮАО", "Москворечье-Сабурово": "ЮАО", "Нагатино-Садовники": "ЮАО",
            "Нагатинский Затон": "ЮАО", "Нагорный": "ЮАО", "Орехово-Борисово Северное": "ЮАО",
            "Орехово-Борисово Южное": "ЮАО", "Царицыно": "ЮАО", "Чертаново Северное": "ЮАО",
            "Чертаново Центральное": "ЮАО", "Чертаново Южное": "ЮАО",
            // ЮЗАО
            "Академический": "ЮЗАО", "Внуково": "ЮЗАО", "Гагаринский": "ЮЗАО",
            "Зюзино": "ЮЗАО", "Коньково": "ЮЗАО", "Котловка": "ЮЗАО",
            "Ломоносовский": "ЮЗАО", "Обручевский": "ЮЗАО", "Северное Бутово": "ЮЗАО",
            "Тёплый Стан": "ЮЗАО", "Черёмушки": "ЮЗАО", "Южное Бутово": "ЮЗАО",
            "Ясенево": "ЮЗАО",
            // ЗАО
            "Дорогомилово": "ЗАО", "Крылатское": "ЗАО", "Кунцево": "ЗАО",
            "Можайский": "ЗАО", "Ново-Переделкино": "ЗАО", "Очаково-Матвеевское": "ЗАО",
            "Проспект Вернадского": "ЗАО", "Раменки": "ЗАО", "Солнцево": "ЗАО",
            "Тропарёво-Никулино": "ЗАО", "Филёвский Парк": "ЗАО", "Фили-Давыдково": "ЗАО",
            // СЗАО
            "Куркино": "СЗАО", "Митино": "СЗАО", "Покровское-Стрешнево": "СЗАО",
            "Северное Тушино": "СЗАО", "Строгино": "СЗАО", "Хорошёво-Мнёвники": "СЗАО",
            "Щукино": "СЗАО", "Южное Тушино": "СЗАО"
        ]
        for (district, okrug) in knownDistricts where address.contains(district) {
            return okrug
        }
        return "Москва"
    }
}

// MARK: - Helpers

private extension FlipAnalyzer {

    func median(of values: [Double]) -> Double {
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2)
            ? (sorted[mid - 1] + sorted[mid]) / 2
            : sorted[mid]
    }

}
