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

    nonisolated func analyze(apartment: Apartment, benchmark: BenchmarkContext, thresholds: DemandThresholds, referenceDate: Date = Date()) -> FlipScoreResult {
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

        let priceScore = computePriceScore(priceSqm: priceSqm, benchmarkSqm: benchmarkSqm, benchmark: benchmark)
        
        let (demandLevel, viewsPerDay) = computeDemand(
            apartment: apartment,
            thresholds: thresholds,
            penalizePromotions: benchmark.penalizePromotions,
            extrapolateMorningViews: benchmark.extrapolateMorningViews,
            useYesterdayViews: benchmark.useYesterdayViews,
            referenceDate: referenceDate
        )
        
        let metroScore: Int
        if benchmark.useViewsScoreInsteadOfMetro {
            let maxWeight = benchmark.metroProximityWeight
            switch demandLevel {
            case .hot:      metroScore = maxWeight
            case .market:   metroScore = Int(Double(maxWeight) * 0.60)
            case .moderate: metroScore = Int(Double(maxWeight) * 0.20)
            default:        metroScore = 0
            }
        } else {
            metroScore = computeMetroScore(apartment: apartment, benchmark: benchmark)
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
            viewsPerDay: viewsPerDay,
            maxPriceScore: benchmark.priceScoreWeight,
            maxMetroScore: benchmark.metroProximityWeight,
            maxLocationScore: benchmark.locationFloorWeight,
            maxAreaScore: benchmark.areaScoreWeight
        )
    }
}

// MARK: - Score Components

private extension FlipAnalyzer {

    /// Price score: max priceScoreWeight (default 40 pts).
    nonisolated func computePriceScore(priceSqm: Double?, benchmarkSqm: Double?, benchmark: BenchmarkContext) -> Int {
        let maxWeight = benchmark.priceScoreWeight
        guard let priceSqm, let benchmarkSqm, benchmarkSqm > 0 else {
            return Int(Double(maxWeight) * 0.15)
        }
        let discount = (benchmarkSqm - priceSqm) / benchmarkSqm
        switch discount {
        case 0.25...: return maxWeight
        case 0.15...: return Int(Double(maxWeight) * 0.80)
        case 0.10...: return Int(Double(maxWeight) * 0.60)
        case 0.05...: return Int(Double(maxWeight) * 0.40)
        case 0.0...:  return Int(Double(maxWeight) * 0.20)
        default:      return 0
        }
    }

    /// Metro score: max metroProximityWeight (default 25 pts).
    nonisolated func computeMetroScore(apartment: Apartment, benchmark: BenchmarkContext) -> Int {
        guard let distance = apartment.metroDistance, distance > 0 else { return 0 }
        let isWalk = apartment.metroTransportType == "walk"
        let maxWeight = benchmark.metroProximityWeight
        if isWalk {
            switch distance {
            case ...5:  return maxWeight
            case ...10: return Int(Double(maxWeight) * 0.80)
            case ...15: return Int(Double(maxWeight) * 0.60)
            case ...20: return Int(Double(maxWeight) * 0.40)
            default:    return Int(Double(maxWeight) * 0.20)
            }
        } else {
            switch distance {
            case ...10: return Int(Double(maxWeight) * 0.52)
            case ...20: return Int(Double(maxWeight) * 0.32)
            default:    return Int(Double(maxWeight) * 0.12)
            }
        }
    }

    /// Location score: max locationFloorWeight (default 20 pts).
    nonisolated func computeLocationScore(apartment: Apartment, benchmark: BenchmarkContext) -> (score: Int, isDistrict: Bool) {
        let maxWeight = benchmark.locationFloorWeight
        guard benchmark.useDistrictScore else {
            return (computeFloorScore(apartment: apartment, benchmark: benchmark), false)
        }
        // District mode ON: look up the explicit score for this district
        if let district = apartment.district,
           let score = benchmark.districtScores[district],
           score >= 0 {
            let scaledScore = Int(Double(score) * (Double(maxWeight) / 20.0))
            return (min(scaledScore, maxWeight), true)
        }
        return (Int(Double(maxWeight) * 0.35), true)
    }

    /// Floor score: max locationFloorWeight (default 20 pts).
    nonisolated func computeFloorScore(apartment: Apartment, benchmark: BenchmarkContext) -> Int {
        let maxWeight = benchmark.locationFloorWeight
        guard let floor = apartment.floor, let total = apartment.totalFloors, total > 0 else {
            return Int(Double(maxWeight) * 0.35)
        }
        if floor == 1         { return 0 }
        if floor == total     { return Int(Double(maxWeight) * 0.25) }
        if floor == total - 1 { return Int(Double(maxWeight) * 0.65) }
        return maxWeight
    }

    /// Area score: max areaScoreWeight (default 15 pts).
    nonisolated func computeAreaScore(apartment: Apartment, benchmark: BenchmarkContext) -> Int {
        guard let area = apartment.area else { return 0 }
        let maxWeight = benchmark.areaScoreWeight
        
        var score = 0
        if benchmark.useLiquidityAreaScore {
            switch area {
            case 35.0...50.0: score = maxWeight
            case 25.0..<35.0: score = Int((Double(maxWeight) * 0.7333).rounded())
            case 50.0...70.0: score = Int((Double(maxWeight) * 0.40).rounded())
            default:          score = Int((Double(maxWeight) * 0.1333).rounded())
            }
        } else {
            switch area {
            case 60...: score = maxWeight
            case 45...: score = Int((Double(maxWeight) * 0.7333).rounded())
            case 30...: score = Int((Double(maxWeight) * 0.40).rounded())
            default:    score = Int((Double(maxWeight) * 0.1333).rounded())
            }
        }
        
        // Double rooms bonus (most marginable for flipping)
        if apartment.roomsCount == 2 {
            score = min(maxWeight, score + Int((Double(maxWeight) * 0.2666).rounded()))
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

    /// Вычисление спроса на основе просмотров в день.
    nonisolated func computeDemand(apartment: Apartment, thresholds: DemandThresholds, penalizePromotions: Bool, extrapolateMorningViews: Bool = true, useYesterdayViews: Bool = true, referenceDate: Date = Date()) -> (DemandLevel, Double?) {
        var rawPerDay: Double? = nil
        
        // Вспомогательные DTO для парсинга истории просмотров
        struct CianViewsHistoryDTO: Codable {
            struct DayViews: Codable {
                let date: String
                let views: Int
            }
            let days: [DayViews]
        }
        
        // 1. Приоритет 1: Точное количество просмотров за вчера из детальной истории (или макс вчера/сегодня)
        if useYesterdayViews, let yesterday = apartment.yesterdayViews {
            // Вычисляем также сегодняшние просмотры с экстраполяцией для сравнения (берем максимум, чтобы не занижать спрос при росте)
            var todayExtrapolated: Double = 0.0
            if let viewsToday = apartment.viewsToday, viewsToday > 0 {
                let hour = Calendar.current.component(.hour, from: referenceDate)
                let isEarlyMorning = (0..<8).contains(hour)
                if isEarlyMorning {
                    todayExtrapolated = Double(viewsToday)
                } else {
                    let distribution: [Double] = [
                        0.0, 0.01, 0.02, 0.02, 0.03, 0.03, 0.04, 0.06, 0.10, 0.15, 0.22, 0.30, 0.38,
                        0.45, 0.52, 0.59, 0.66, 0.73, 0.79, 0.85, 0.90, 0.94, 0.97, 0.99, 1.0
                    ]
                    let h = max(0, min(24, hour))
                    let percentage = distribution[h]
                    if percentage >= 0.10 {
                        todayExtrapolated = Double(viewsToday) / percentage
                    } else {
                        todayExtrapolated = Double(viewsToday)
                    }
                }
            }
            rawPerDay = max(Double(yesterday), todayExtrapolated)
        }
        
        // 2. Приоритет 2: Честная дельта общего счетчика за последние N часов (скользящее окно)
        if rawPerDay == nil {
            if let prevTotal = apartment.previousViewsTotal,
               let prevDate = apartment.previousViewsDate,
               let currentTotal = apartment.viewsTotal {
                let hoursPassed = referenceDate.timeIntervalSince(prevDate) / 3600.0
                if hoursPassed > 12.0 {
                    let deltaViews = currentTotal - prevTotal
                    if deltaViews >= 0 {
                        rawPerDay = Double(deltaViews) / (hoursPassed / 24.0)
                    }
                }
            }
        }

        // 3. Приоритет 3: Просмотры "за сегодня" с экстраполяцией (для новинок)
        if rawPerDay == nil, let viewsToday = apartment.viewsToday, viewsToday > 0 {
            let hour = Calendar.current.component(.hour, from: referenceDate)
            let isEarlyMorning = (0..<8).contains(hour)
            
            if extrapolateMorningViews {
                if isEarlyMorning {
                    // Раннее утро (с 00:00 до 08:00): экстраполяция автоматически отключается
                    rawPerDay = Double(viewsToday)
                } else {
                    // Накопленный процент суточных просмотров по часам
                    let distribution: [Double] = [
                        0.0, 0.01, 0.02, 0.02, 0.03, 0.03, 0.04, 0.06, 0.10, 0.15, 0.22, 0.30, 0.38,
                        0.45, 0.52, 0.59, 0.66, 0.73, 0.79, 0.85, 0.90, 0.94, 0.97, 0.99, 1.0
                    ]
                    let h = max(0, min(24, hour))
                    let percentage = distribution[h]
                    
                    if percentage >= 0.10 {
                        rawPerDay = Double(viewsToday) / percentage
                    } else {
                        rawPerDay = Double(viewsToday)
                    }
                }
            } else {
                rawPerDay = Double(viewsToday)
            }
        }
        
        // 4. Приоритет 4: Среднее арифметическое просмотров за последние 3 завершенных дня из истории
        if useYesterdayViews, rawPerDay == nil, let historyJSON = apartment.viewsHistoryJSON, !historyJSON.isEmpty,
           let data = historyJSON.data(using: .utf8),
           let history = try? JSONDecoder().decode(CianViewsHistoryDTO.self, from: data) {
            let dailyViews = history.days
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            let todayStr = formatter.string(from: referenceDate)
            
            // Исключаем сегодня (неполный день) и считаем среднее за последние 3 дня
            let completedDays = dailyViews.filter { $0.date != todayStr }
            let lastNDays = completedDays.suffix(3)
            if !lastNDays.isEmpty {
                let sum = lastNDays.reduce(0) { $0 + $1.views }
                rawPerDay = Double(sum) / Double(lastNDays.count)
            }
        }
        
        // 5. Приоритет 5: Среднее значение за всё время жизни объявления (Legacy fallback)
        if rawPerDay == nil, let total = apartment.viewsTotal, total > 0, let published = apartment.publishedDate {
            let actualDays = referenceDate.timeIntervalSince(published) / 86400.0
            
            if actualDays > 3.0 {
                let days = max(1.0, actualDays)
                rawPerDay = Double(total) / days
            } else {
                let minDays = 2.0 / 24.0
                let effectiveDays = max(minDays, actualDays)
                rawPerDay = Double(total) / effectiveDays
            }
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
            "Академический": "ЮЗАО", "Гагаринский": "ЮЗАО",
            "Зюзино": "ЮЗАО", "Коньково": "ЮЗАО", "Котловка": "ЮЗАО",
            "Ломоносовский": "ЮЗАО", "Обручевский": "ЮЗАО", "Северное Бутово": "ЮЗАО",
            "Тёплый Стан": "ЮЗАО", "Черёмушки": "ЮЗАО", "Южное Бутово": "ЮЗАО",
            "Ясенево": "ЮЗАО",
            // ЗАО
            "Внуково": "ЗАО", "Дорогомилово": "ЗАО", "Крылатское": "ЗАО", "Кунцево": "ЗАО",
            "Можайский": "ЗАО", "Ново-Переделкино": "ЗАО", "Очаково-Матвеевское": "ЗАО",
            "Проспект Вернадского": "ЗАО", "Раменки": "ЗАО", "Солнцево": "ЗАО",
            "Тропарёво-Никулино": "ЗАО", "Филёвский Парк": "ЗАО", "Фили-Давыдково": "ЗАО",
            // СЗАО
            "Куркино": "СЗАО", "Митино": "СЗАО", "Покровское-Стрешнево": "СЗАО",
            "Северное Тушино": "СЗАО", "Строгино": "СЗАО", "Хорошёво-Мнёвники": "СЗАО",
            "Щукино": "СЗАО", "Южное Тушино": "СЗАО"
        ]
        
        // 1. Быстрый точный поиск по извлеченному району (без коллизий подстрок)
        if let districtName = extractDistrict(from: address),
           let okrug = knownDistricts[districtName] {
            return okrug
        }
        
        // 2. Фолбэк: поиск по подстроке с сортировкой по длине названия района (чтобы "Соколиная Гора" проверялась до "Сокол")
        let sortedDistricts = knownDistricts.keys.sorted { $0.count > $1.count }
        for district in sortedDistricts where address.contains(district) {
            if let okrug = knownDistricts[district] {
                return okrug
            }
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
