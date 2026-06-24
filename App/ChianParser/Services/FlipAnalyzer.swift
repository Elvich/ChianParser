//
//  FlipAnalyzer.swift
//  ChianParser
//
//  Computes FlipScoreResult for apartments based on market benchmark data.
//
//  Scoring breakdown (total 100 pts):
//    Price vs benchmark   40 pts  — deeper discount → higher score
//    Metro proximity      25 pts  — walk < 5 min is best
//    Location             20 pts  — floor position (default) OR district rank (district mode)
//    Area                 15 pts  — larger is better
//

import Foundation

final class FlipAnalyzer: @unchecked Sendable {}

// MARK: - FlipAnalyzerProtocol

extension FlipAnalyzer: FlipAnalyzerProtocol {

    func buildBenchmark(from apartments: [Apartment], targetPercentile: Double) -> BenchmarkContext {
        var okrugGroups: [String: [Double]] = [:]
        var districtGroups: [String: [Double]] = [:]
        var metroGroups: [String: [Double]] = [:]
        var allPricesSqm: [Double] = []

        for apt in apartments {
            guard let area = apt.area, area > 10, apt.price > 0 else { continue }
            let priceSqm = Double(apt.price) / area
            let okrug = extractOkrug(from: apt.address)
            okrugGroups[okrug, default: []].append(priceSqm)
            allPricesSqm.append(priceSqm)
            if let district = apt.district {
                districtGroups[district, default: []].append(priceSqm)
            }
            if let metro = apt.metro {
                metroGroups[metro, default: []].append(priceSqm)
            }
        }

        let minSamples = 5
        var byOkrug: [String: OkrugBenchmark] = [:]
        for (okrug, prices) in okrugGroups where prices.count >= minSamples {
            byOkrug[okrug] = OkrugBenchmark(
                medianPriceSqm: percentile(of: prices, target: targetPercentile),
                sampleSize: prices.count,
                okrug: okrug
            )
        }

        var byDistrict: [String: OkrugBenchmark] = [:]
        for (district, prices) in districtGroups where prices.count >= minSamples {
            byDistrict[district] = OkrugBenchmark(
                medianPriceSqm: percentile(of: prices, target: targetPercentile),
                sampleSize: prices.count,
                okrug: district  // store district name in 'okrug' field for display
            )
        }

        var byMetro: [String: OkrugBenchmark] = [:]
        for (metro, prices) in metroGroups where prices.count >= minSamples {
            byMetro[metro] = OkrugBenchmark(
                medianPriceSqm: percentile(of: prices, target: targetPercentile),
                sampleSize: prices.count,
                okrug: metro  // store metro name in 'okrug' field for display
            )
        }

        let globalMedian = allPricesSqm.count >= minSamples ? percentile(of: allPricesSqm, target: targetPercentile) : nil

        // districtScores, useDistrictScore, benchmarkMode enriched by ContentViewModel
        return BenchmarkContext(
            byOkrug: byOkrug,
            byDistrict: byDistrict,
            byMetro: byMetro,
            globalMedian: globalMedian,
            globalSampleSize: allPricesSqm.count
        )
    }

    nonisolated func analyze(apartment: Apartment, benchmark: BenchmarkContext, thresholds: DemandThresholds) -> FlipScoreResult {
        let priceSqm: Double? = {
            guard let area = apartment.area, area > 10, apartment.price > 0 else { return nil }
            return Double(apartment.price) / area
        }()

        let okrug = extractOkrug(from: apartment.address)

        var benchmarkSqm: Double?
        var benchmarkOkrug: String?
        var sampleSize: Int = 0
        var foundBenchmark = false

        if benchmark.benchmarkMode == .smart {
            if let metro = apartment.metro, let metroBM = benchmark.byMetro[metro] {
                benchmarkSqm = metroBM.medianPriceSqm
                benchmarkOkrug = metroBM.okrug
                sampleSize = metroBM.sampleSize
                foundBenchmark = true
            } else if let district = apartment.district, let districtBM = benchmark.byDistrict[district] {
                benchmarkSqm = districtBM.medianPriceSqm
                benchmarkOkrug = districtBM.okrug
                sampleSize = districtBM.sampleSize
                foundBenchmark = true
            }
        } else if benchmark.benchmarkMode == .district {
            if let district = apartment.district, let districtBM = benchmark.byDistrict[district] {
                benchmarkSqm = districtBM.medianPriceSqm
                benchmarkOkrug = districtBM.okrug
                sampleSize = districtBM.sampleSize
                foundBenchmark = true
            }
        }

        if !foundBenchmark {
            let okrugBM = benchmark.byOkrug[okrug]
            benchmarkSqm = okrugBM?.medianPriceSqm ?? benchmark.globalMedian
            benchmarkOkrug = okrugBM?.okrug
            sampleSize = okrugBM?.sampleSize ?? benchmark.globalSampleSize
        }

        let priceScore = computePriceScore(priceSqm: priceSqm, benchmarkSqm: benchmarkSqm)
        
        let (demandLevel, viewsPerDay) = computeDemand(apartment: apartment, thresholds: thresholds, penalizePromotions: benchmark.penalizePromotions, extrapolateMorningViews: benchmark.extrapolateMorningViews)
        
        let metroScore: Int
        if benchmark.useViewsScoreInsteadOfMetro {
            switch demandLevel {
            case .hot:      metroScore = 25
            case .market:   metroScore = 15
            case .moderate: metroScore = 5
            default:        metroScore = 0
            }
        } else {
            metroScore = computeMetroScore(apartment: apartment)
        }
        
        let (locationScore, isDistrictScore) = computeLocationScore(apartment: apartment, benchmark: benchmark)
        let areaScore  = computeAreaScore(apartment: apartment, benchmark: benchmark)
        let sellerBonus = computeSellerBonus(apartment: apartment)

        let total = priceScore + metroScore + locationScore + areaScore + sellerBonus

        return FlipScoreResult(
            totalScore: min(total, 100),
            priceScore: priceScore,
            metroScore: metroScore,
            locationScore: locationScore,
            isDistrictScore: isDistrictScore,
            areaScore: areaScore,
            sellerBonus: sellerBonus,
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
    nonisolated func computePriceScore(priceSqm: Double?, benchmarkSqm: Double?) -> Int {
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
    nonisolated func computeMetroScore(apartment: Apartment) -> Int {
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

    /// Location score: max 20 pts.
    /// District mode ON  — reads score directly from benchmark.districtScores (0…20), neutral 7 if unknown.
    /// District mode OFF — floor position (1st floor → 0, last → 5, near-last → 13, other → 20).
    nonisolated func computeLocationScore(apartment: Apartment, benchmark: BenchmarkContext) -> (score: Int, isDistrict: Bool) {
        guard benchmark.useDistrictScore else {
            return (computeFloorScore(apartment: apartment), false)
        }
        // District mode ON: look up the explicit score for this district
        if let district = apartment.district,
           let score = benchmark.districtScores[district],
           score >= 0 {
            return (min(score, 20), true)
        }
        return (7, true)  // No district data or district not in table — neutral score
    }

    /// Floor score (used in default mode): max 20 pts.
    nonisolated func computeFloorScore(apartment: Apartment) -> Int {
        guard let floor = apartment.floor, let total = apartment.totalFloors, total > 0 else { return 7 }
        if floor == 1         { return 0 }
        if floor == total     { return 2 } // Pessimize top floor strongly
        if floor == total - 1 { return 13 }
        return 20
    }

    /// Area score: max 15 pts.
    /// Liquidity mode (bell curve): 35-50 → 15, 25-35 → 11, 51-70 → 6, else → 2.
    /// Default mode (linear): ≥60 → 15, ≥45 → 11, ≥30 → 6, <30 → 2.
    nonisolated func computeAreaScore(apartment: Apartment, benchmark: BenchmarkContext) -> Int {
        guard let area = apartment.area else { return 0 }
        
        var score = 0
        if benchmark.useLiquidityAreaScore {
            switch area {
            case 35.0...50.0: score = 15
            case 25.0..<35.0: score = 11
            case 50.0...70.0: score = 6
            default:          score = 2
            }
        } else {
            switch area {
            case 60...: score = 15
            case 45...: score = 11
            case 30...: score = 6
            default:    score = 2
            }
        }
        
        // Double rooms bonus (most marginable for flipping)
        if apartment.roomsCount == 2 {
            score = min(15, score + 4)
        }
        return score
    }

    /// Нормализует просмотры для рекламных объявлений (убирает накрутку за счет верхних позиций)
    nonisolated func normalizeViews(_ viewsPerDay: Double, promotionType: String?) -> Double {
        guard let promo = promotionType?.lowercased() else { return viewsPerDay }
        
        switch promo {
        case "standard":
            return viewsPerDay / 1.5
        case "top3":
            return viewsPerDay / 3.0
        case "premium", "highlight":
            return viewsPerDay / 2.0
        case "simple", "organic", "":
            return viewsPerDay
        default:
            return viewsPerDay / 1.5 // Базовый штраф для неизвестных видов платного продвижения
        }
    }

    /// Demand computation from views/day.
    nonisolated func computeDemand(apartment: Apartment, thresholds: DemandThresholds, penalizePromotions: Bool, extrapolateMorningViews: Bool = true) -> (DemandLevel, Double?) {
        var rawPerDay: Double? = nil
        
        // 1. Приоритет: честная дельта (rolling window) за последние N часов
        if let prevTotal = apartment.previousViewsTotal,
           let prevDate = apartment.previousViewsDate,
           let currentTotal = apartment.viewsTotal {
            let hoursPassed = Date().timeIntervalSince(prevDate) / 3600.0
            if hoursPassed > 12.0 {
                let deltaViews = currentTotal - prevTotal
                if deltaViews >= 0 {
                    rawPerDay = Double(deltaViews) / (hoursPassed / 24.0)
                }
            }
        }

        // 2. Фолбэк 1: Просмотры "за сегодня" (от Циана)
        if rawPerDay == nil, let viewsToday = apartment.viewsToday, viewsToday > 0 {
            if extrapolateMorningViews {
                let hour = Calendar.current.component(.hour, from: Date())
                
                // Cumulative percentage of daily views by hour (approximate curve)
                // 0: 0%, 4: 3%, 8: 10%, 12: 38%, 16: 66%, 20: 90%, 24: 100%
                let distribution: [Double] = [
                    0.0, 0.01, 0.02, 0.02, 0.03, 0.03, 0.04, 0.06, 0.10, 0.15, 0.22, 0.30, 0.38,
                    0.45, 0.52, 0.59, 0.66, 0.73, 0.79, 0.85, 0.90, 0.94, 0.97, 0.99, 1.0
                ]
                
                let h = max(0, min(24, hour))
                let percentage = distribution[h]
                
                // Если процент слишком мал (до 8 утра), лучше пропустить этот шаг 
                // и перейти к Фолбэку 2 (среднее за все время), чтобы избежать ошибок экстраполяции
                if percentage >= 0.10 {
                    rawPerDay = Double(viewsToday) / percentage
                }
            } else {
                rawPerDay = Double(viewsToday)
            }
        }
        
        // 3. Фолбэк 2: Среднее значение за всё время жизни объявления
        if rawPerDay == nil, let total = apartment.viewsTotal, total > 0, let published = apartment.publishedDate {
            let days = max(1.0, Date().timeIntervalSince(published) / 86400)
            rawPerDay = Double(total) / days
        }
        
        guard let finalRaw = rawPerDay else {
            return (.noData, nil)
        }
        
        // Нормализуем просмотры, если есть платное продвижение и включены санкции
        let normalizedPerDay = penalizePromotions ? normalizeViews(finalRaw, promotionType: apartment.promotionType) : finalRaw
        
        return (demandLevel(perDay: normalizedPerDay, thresholds: thresholds), normalizedPerDay)
    }

    /// Seller bonus: +3 for agent/agency, 0 for owner or unknown.
    ///
    /// Normalises the many string variants Cian uses for seller type.
    /// Falls back to sellerName when sellerType is nil — catches agency brand names
    /// like "Real Estate EXPERT" when the type field is missing from JSON.
    nonisolated func computeSellerBonus(apartment: Apartment) -> Int {
        // Prefer type field; fall back to name to catch agency brands
        let raw = apartment.sellerType ?? apartment.sellerName ?? ""
        let t = raw.lowercased()
        let isProfessional = t.contains("agent") || t.contains("agency")
            || t.contains("риелтор") || t.contains("агент")
            || t.contains("агентство")
            || t.contains("real estate") || t.contains("realty")
            || t.contains("недвижимость")  // ИНКОМ-Недвижимость, Этажи и т.п.
            || t.contains("developer") || t.contains("застройщик")
        return isProfessional ? 3 : 0
    }

    nonisolated func demandLevel(perDay: Double, thresholds: DemandThresholds) -> DemandLevel {
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
    nonisolated func extractOkrug(from address: String) -> String {
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

// MARK: - District Extraction

extension FlipAnalyzer {

    /// Extract the Moscow district name from an address string.
    /// Cian addresses contain "р-н <DistrictName>" as a comma-separated fragment.
    nonisolated func extractDistrict(from address: String) -> String? {
        let pattern = "р-н\\s+([^,]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: address, range: NSRange(address.startIndex..., in: address)),
              let range = Range(match.range(at: 1), in: address) else { return nil }
        return String(address[range]).trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - Helpers

private extension FlipAnalyzer {

    nonisolated func percentile(of values: [Double], target: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        if target <= 0.0 { return sorted.first ?? 0 }
        if target >= 1.0 { return sorted.last ?? 0 }
        let index = Double(sorted.count - 1) * target
        let lower = Int(floor(index))
        let upper = Int(ceil(index))
        if lower == upper { return sorted[lower] }
        let weight = index - Double(lower)
        return sorted[lower] * (1.0 - weight) + sorted[upper] * weight
    }

}
