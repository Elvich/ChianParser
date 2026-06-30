//
//  SettingsView.swift
//  ChianParser
//
//  macOS Settings window — opened via Cmd+, or app menu.
//  Organised as a tabbed interface per Apple HIG.
//

import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var configs: [ScoringConfiguration]

    var body: some View {
        Group {
            if let config = configs.first {
                TabView {
                    DemandSettingsTab(config: config)
                        .tabItem {
                            Label("Спрос", systemImage: "chart.bar.fill")
                        }
                        .tag(0)

                    ScoringSettingsTab(config: config)
                        .tabItem {
                            Label("Скоринг", systemImage: "checklist")
                        }
                        .tag(1)

                    MetroBanlistTab()
                        .tabItem {
                            Label("Станции МЦД", systemImage: "tram.fill")
                        }
                        .tag(2)

                    SearchURLListTab()
                        .tabItem {
                            Label("Ссылки поиска", systemImage: "link")
                        }
                        .tag(3)

                    ParserSettingsTab()
                        .tabItem {
                            Label("Парсинг", systemImage: "gearshape.2")
                        }
                        .tag(4)

                    DistrictsSettingsTab(config: config)
                        .tabItem {
                            Label("Районы", systemImage: "map")
                        }
                        .tag(5)

                    AISettingsTab()
                        .tabItem {
                            Label("AI", systemImage: "sparkles")
                        }
                        .tag(6)
                }
            } else {
                ProgressView("Загрузка настроек...")
                    .frame(width: 520, height: 400)
                    .task {
                        _ = modelContext.fetchOrCreateScoringConfiguration()
                    }
            }
        }
        .frame(width: 520)
    }
}

// MARK: - Tab: Scoring Settings

private struct ScoringSettingsTab: View {
    @Bindable var config: ScoringConfiguration
    
    private var totalWeight: Int {
        config.priceScoreWeight + config.metroProximityWeight + config.locationFloorWeight + config.areaScoreWeight
    }
    
    var body: some View {
        Form {
            Section("Режимы оценки") {
                Toggle("Оценка площади (FlipCurve)", isOn: $config.isCustomAreaScoreEnabled)
                    .help("Оптимизирует баллы площади под флиппинг (максимум за 35-50 м², штраф за неликвидные размеры).")
                    .accessibilityIdentifier("settings.scoring.isCustomAreaScoreEnabled")
                Toggle("Верхняя граница рынка (перцентиль)", isOn: $config.isPercentileBenchmarkEnabled)
                    .help("Расчет относительно цен верхнего сегмента рынка для оценки флип-маржи.")
                    .accessibilityIdentifier("settings.scoring.isPercentileBenchmarkEnabled")
            }
            
            if config.isPercentileBenchmarkEnabled {
                Section {
                    Slider(value: $config.targetPercentile, in: 0.50...0.95, step: 0.05) {
                        Text("Уровень перцентиля")
                    } minimumValueLabel: {
                        Text("50%")
                    } maximumValueLabel: {
                        Text("95%")
                    }
                    .accessibilityIdentifier("settings.scoring.targetPercentileSlider")
                    
                    HStack {
                        Text("Текущий эталон:")
                        Spacer()
                        Text("\(Int(config.targetPercentile * 100))%-й перцентиль")
                            .foregroundStyle(.secondary)
                            .bold()
                    }
                    .font(.caption)
                } header: {
                    Text("Бенчмарк рынка")
                } footer: {
                    Text("50% — обычная медиана. 80-90% — цена готовой квартиры с ремонтом.")
                }
            }
            
            Section("Глобальные исключения") {
                Toggle("Автоматически отсеивать студии", isOn: $config.excludeStudios)
                    .help("Не добавлять студии в базу данных при парсинге.")
                    .accessibilityIdentifier("settings.scoring.excludeStudiosToggle")
                Toggle("Автоматически отсеивать апартаменты", isOn: $config.excludeApartments)
                    .help("Не добавлять коммерческие апартаменты в базу данных.")
                    .accessibilityIdentifier("settings.scoring.excludeApartmentsToggle")
            }
            
            Section {
                Stepper(value: $config.priceScoreWeight, in: 0...100, step: 5) {
                    HStack {
                        Text("Вес скидки цены")
                        Spacer()
                        Text("\(config.priceScoreWeight) б.")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .accessibilityIdentifier("settings.scoring.priceWeightStepper")
                Stepper(value: $config.metroProximityWeight, in: 0...100, step: 5) {
                    HStack {
                        Text("Вес близости к метро")
                        Spacer()
                        Text("\(config.metroProximityWeight) б.")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .accessibilityIdentifier("settings.scoring.metroWeightStepper")
                Stepper(value: $config.locationFloorWeight, in: 0...100, step: 5) {
                    HStack {
                        Text("Вес этажности/локации")
                        Spacer()
                        Text("\(config.locationFloorWeight) б.")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .accessibilityIdentifier("settings.scoring.locationWeightStepper")
                Stepper(value: $config.areaScoreWeight, in: 0...100, step: 5) {
                    HStack {
                        Text("Вес площади")
                        Spacer()
                        Text("\(config.areaScoreWeight) б.")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .accessibilityIdentifier("settings.scoring.areaWeightStepper")
            } header: {
                Text("Веса метрик FlipScore")
            } footer: {
                HStack {
                    Text("Суммарный вес:")
                    Spacer()
                    Text("\(totalWeight) / 100")
                        .bold()
                        .foregroundColor(totalWeight == 100 ? .green : .orange)
                }
            }
        }
        .formStyle(.grouped)
        .frame(minHeight: 400)
    }
}

// MARK: - Tab 1: Demand Thresholds

private struct DemandSettingsTab: View {
    @Bindable var config: ScoringConfiguration

    @AppStorage("demandThresholdModerate") private var moderate: Int = DemandThresholds.default.moderate
    @AppStorage("demandThresholdMarket")   private var market: Int   = DemandThresholds.default.market
    @AppStorage("demandThresholdHot")      private var hot: Int      = DemandThresholds.default.hot

    @AppStorage("useViewsScoreInsteadOfMetro") private var useViewsScoreInsteadOfMetro: Bool = false

    var body: some View {
        Form {
            Section {
                stepper("Умеренный спрос от", value: $moderate, range: 10...500)
                stepper("Рыночный спрос от",  value: $market,   range: 10...500)
                stepper("Горячий спрос от",   value: $hot,      range: 10...1000)
            } header: {
                Text("Пороги (просмотров / день)")
            } footer: {
                Text("Определяют уровень интереса к объявлению на основе количества просмотров в сутки.")
            }

            Section("Предпросмотр уровней") {
                demandRow(.low,      label: "< \(moderate) просм./день")
                demandRow(.moderate, label: "≥ \(moderate) просм./день")
                demandRow(.market,   label: "≥ \(market) просм./день")
                demandRow(.hot,      label: "≥ \(hot) просм./день")
            }

            Section {
                Toggle("Кривая ликвидности для площади", isOn: $config.isCustomAreaScoreEnabled)
                Toggle("Баллы за просмотры вместо метро", isOn: $useViewsScoreInsteadOfMetro)
            } header: {
                Text("Оценка площади (FlipScore)")
            } footer: {
                Text("Оптимизирует баллы под флиппинг (максимум за 35-50 м², штраф за неликвидные размеры). При включении просмотра вместо метро, очки за спрос заменяют баллы удаленности от метро.")
            }

            Section {
                Button("Сбросить по умолчанию") {
                    moderate = DemandThresholds.default.moderate
                    market   = DemandThresholds.default.market
                    hot      = DemandThresholds.default.hot
                }
                .foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
        .frame(minHeight: 360)
    }

    private func stepper(_ label: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        Stepper(value: value, in: range, step: 10) {
            HStack {
                Text(label)
                Spacer()
                Text("≥ \(value.wrappedValue)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    private func demandRow(_ level: DemandLevel, label: String) -> some View {
        HStack {
            Image(systemName: level.icon)
                .foregroundStyle(level.color)
                .frame(width: 20)
            Text(level.label)
            Spacer()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Tab 2: Metro Banlist

private struct MetroBanlistTab: View {
    @AppStorage(MetroBanlist.appStorageKey) private var metroBanlistJSON: String = MetroBanlist.defaultJSON
    @AppStorage("metroMaxDistance")  private var maxMetroDistance: Int = 0
    @AppStorage("metroWalkOnly")     private var metroWalkOnly: Bool = false
    @AppStorage("minBuildingFloors") private var minBuildingFloors: Int = 6

    @State private var newStation: String = ""
    @State private var searchText: String = ""

    private var bannedStations: [String] {
        let all = MetroBanlist.decode(from: metroBanlistJSON).sorted()
        guard !searchText.isEmpty else { return all }
        return all.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Metro distance + walk-only filters
            VStack(spacing: 0) {
                HStack {
                    Toggle("Только пешком", isOn: $metroWalkOnly)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)

                Divider()

                HStack {
                    Text("Макс. расстояние")
                    Spacer()
                    if maxMetroDistance == 0 {
                        Text("Без ограничения")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("\(maxMetroDistance) мин.")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Stepper("", value: $maxMetroDistance, in: 0...60)
                        .labelsHidden()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)

                Divider()

                HStack {
                    Text("Мин. этажей в доме")
                    Spacer()
                    if minBuildingFloors == 0 {
                        Text("Без ограничения")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("от \(minBuildingFloors) эт.")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Stepper("", value: $minBuildingFloors, in: 0...50)
                        .labelsHidden()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
            .background(.bar)

            Divider()

            // Search + add bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Поиск станции...", text: $searchText)
                    .textFieldStyle(.plain)

                Divider().frame(height: 16)

                TextField("Добавить станцию", text: $newStation)
                    .textFieldStyle(.plain)
                    .onSubmit { addStation() }

                Button(action: addStation) {
                    Image(systemName: "plus.circle.fill")
                }
                .buttonStyle(.plain)
                .disabled(newStation.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)

            Divider()

            // Station list
            if bannedStations.isEmpty {
                ContentUnavailableView(
                    searchText.isEmpty ? "Список пуст" : "Ничего не найдено",
                    systemImage: searchText.isEmpty ? "tram" : "magnifyingglass",
                    description: Text(searchText.isEmpty
                        ? "Все станции разрешены"
                        : "Попробуйте другой запрос")
                )
                .frame(maxHeight: .infinity)
            } else {
                List {
                    ForEach(bannedStations, id: \.self) { station in
                        HStack {
                            Image(systemName: "tram.fill")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                                .frame(width: 16)
                            Text(station)
                            Spacer()
                            Button {
                                removeStation(station)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .listStyle(.inset)
            }

            Divider()

            // Footer with count + reset
            HStack {
                Text("\(MetroBanlist.decode(from: metroBanlistJSON).count) станций в банлисте")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Сбросить по умолчанию") {
                    metroBanlistJSON = MetroBanlist.defaultJSON
                    searchText = ""
                }
                .foregroundStyle(.red)
                .buttonStyle(.plain)
                .font(.caption)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)
        }
        .frame(minHeight: 360)
    }

    private func addStation() {
        let name = newStation.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        var current = MetroBanlist.decode(from: metroBanlistJSON)
        current.insert(name)
        metroBanlistJSON = MetroBanlist.encode(current)
        newStation = ""
    }

    private func removeStation(_ station: String) {
        var current = MetroBanlist.decode(from: metroBanlistJSON)
        current.remove(station)
        metroBanlistJSON = MetroBanlist.encode(current)
    }
}

// MARK: - Tab 3: Search URL List

private struct SearchURLListTab: View {
    @AppStorage(SearchURLList.appStorageKey) private var searchURLListJSON: String = SearchURLList.defaultJSON

    @State private var newURLString: String = ""
    @State private var searchText: String = ""

    private var allURLs: [String] {
        SearchURLList.decode(from: searchURLListJSON)
    }

    private var filteredURLs: [String] {
        guard !searchText.isEmpty else { return allURLs }
        return allURLs.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search + add bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Фильтр...", text: $searchText)
                    .textFieldStyle(.plain)

                Divider().frame(height: 16)

                TextField("Добавить URL", text: $newURLString)
                    .textFieldStyle(.plain)
                    .onSubmit { addURL() }

                Button(action: addURL) {
                    Image(systemName: "plus.circle.fill")
                }
                .buttonStyle(.plain)
                .disabled(newURLString.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)

            Divider()

            if filteredURLs.isEmpty {
                ContentUnavailableView(
                    searchText.isEmpty ? "Список пуст" : "Ничего не найдено",
                    systemImage: searchText.isEmpty ? "link" : "magnifyingglass",
                    description: Text(searchText.isEmpty
                        ? "Добавьте URL поиска Циан выше"
                        : "Попробуйте другой запрос")
                )
                .frame(maxHeight: .infinity)
            } else {
                List {
                    ForEach(Array(filteredURLs.enumerated()), id: \.element) { index, url in
                        HStack(spacing: 8) {
                            // Index badge
                            Text("\(allURLs.firstIndex(of: url).map { $0 + 1 } ?? (index + 1))")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 20, alignment: .trailing)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(SearchURLList.shortLabel(for: url))
                                    .font(.subheadline.weight(.medium))
                                Text(url)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }

                            Spacer()

                            Button {
                                removeURL(url)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 2)
                    }
                }
                .listStyle(.inset)
            }

            Divider()

            // Footer
            HStack {
                Text("\(allURLs.count) ссылок в очереди")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Сбросить по умолчанию") {
                    searchURLListJSON = SearchURLList.defaultJSON
                    searchText = ""
                }
                .foregroundStyle(.red)
                .buttonStyle(.plain)
                .font(.caption)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)
        }
        .frame(minHeight: 400)
    }

    private func addURL() {
        let url = newURLString.trimmingCharacters(in: .whitespaces)
        guard !url.isEmpty else { return }
        var current = SearchURLList.decode(from: searchURLListJSON)
        guard !current.contains(url) else { newURLString = ""; return }
        current.append(url)
        searchURLListJSON = SearchURLList.encode(current)
        newURLString = ""
    }

    private func removeURL(_ url: String) {
        var current = SearchURLList.decode(from: searchURLListJSON)
        current.removeAll { $0 == url }
        searchURLListJSON = SearchURLList.encode(current)
    }
}

// MARK: - Tab 4: Parser Settings

private struct ParserSettingsTab: View {
    @AppStorage("parserAutoDetail")       private var autoDetail: Bool = true
    @AppStorage("parserAutoCheck")        private var autoCheck: Bool = true
    @AppStorage("parserStaleDays")        private var staleDays: Int = 3
    @AppStorage("moderateReparseHours")   private var moderateReparseHours: Int = 12
    @AppStorage("parserEnablePagination") private var enablePagination: Bool = true
    @AppStorage("parserMaxPages")         private var maxPages: Int = 1
    @AppStorage("parserMode")             private var parserMode: ParsingMode = .parallel
    @AppStorage("parserRequireDetail")    private var requireDetailParsed: Bool = true
    @AppStorage("hideStudios")            private var hideStudios: Bool = false
    @AppStorage("hideApartments")         private var hideApartments: Bool = false
    @AppStorage("penalizePromotions")     private var penalizePromotions: Bool = true
    @AppStorage("extrapolateMorningViews") private var extrapolateMorningViews: Bool = true

    @Environment(AppContainer.self) private var container
    @Environment(\.modelContext) private var modelContext

    @State private var isBackfilling: Bool = false
    @State private var backfillResult: String = ""

    var body: some View {
        Form {
            Section {
                Picker("Режим парсинга", selection: $parserMode) {
                    ForEach(ParsingMode.allCases, id: \.self) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Режим парсинга")
            } footer: {
                Text(parserMode.description)
            }

            Section {
                Toggle("Авто-детали", isOn: $autoDetail)
                Toggle("Авто-проверка активности", isOn: $autoCheck)
                Toggle("Только с детальным парсингом", isOn: $requireDetailParsed)
                Toggle("Скрывать студии", isOn: $hideStudios)
                Toggle("Скрывать апартаменты", isOn: $hideApartments)
                Toggle("Пессимизировать просмотры у рекламы", isOn: $penalizePromotions)
                    .help("Делит просмотры на 1.5 для Стандарта и на 3.0 для ТОП-3 объявлений, чтобы нивелировать накрутку просмотров.")
                Toggle("Экстраполяция утренних просмотров", isOn: $extrapolateMorningViews)
                    .help("Умный пересчёт просмотров 'за сегодня' в утренние часы с учетом суточной кривой активности пользователей.")
                Stepper(value: $staleDays, in: 1...30) {
                    HStack {
                        Text("Порог устаревания")
                        Spacer()
                        Text("\(staleDays) дн.")
                            .foregroundColor(.secondary)
                    }
                }
                Stepper(value: $moderateReparseHours, in: 6...72, step: 6) {
                    HStack {
                        Text("Перепарсинг 'умеренных' квартир")
                        Spacer()
                        Text("каждые \(moderateReparseHours) ч.")
                            .foregroundColor(.secondary)
                    }
                }
                .help("Частота обновления квартир со статусом Умеренный спрос во время простоя парсера.").monospacedDigit()
                .disabled(!autoCheck)
            } header: {
                Text("Детальный парсинг")
            } footer: {
                Text("Авто-детали — парсить каждую новую квартиру сразу после находки.\nАвто-проверка — перепроверять квартиры, которые не появлялись в поиске дольше порога.\nТолько с детальным парсингом — скрывать квартиры без детальных данных.\nСтудии и апартаменты определяются по заголовку, описанию и JSON-полям категории.")
            }

            Section {
                Toggle("Пагинация", isOn: $enablePagination)
                Stepper(value: $maxPages, in: 1...20) {
                    HStack {
                        Text("Страниц на ссылку")
                        Spacer()
                        Text("\(maxPages)")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .disabled(!enablePagination)
            } header: {
                Text("Поисковый парсинг")
            } footer: {
                Text("Пагинация позволяет обходить несколько страниц выдачи по каждой ссылке.")
            }

            Section {
                HStack {
                    Button("Пересчитать округа") {
                        backfillOkrugs()
                    }
                    .disabled(isBackfilling)

                    if isBackfilling {
                        ProgressView()
                            .scaleEffect(0.7)
                            .padding(.leading, 4)
                    } else if !backfillResult.isEmpty {
                        Text(backfillResult)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("База данных")
            } footer: {
                Text("Заполняет поле «округ» для квартир, добавленных до появления этой функции. Округ определяется из адреса (ЦАО, ЮВАО и т.д.).")
            }

            Section {
                Button("Сбросить по умолчанию") {
                    autoDetail = true
                    autoCheck = true
                    staleDays = 3
                    enablePagination = true
                    maxPages = 1
                    parserMode = .parallel
                    requireDetailParsed = true
                }
                .foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
        .frame(minHeight: 480)
    }

    private func backfillOkrugs() {
        isBackfilling = true
        backfillResult = ""
        Task { @MainActor in
            let descriptor = FetchDescriptor<Apartment>()
            let apartments = (try? modelContext.fetch(descriptor)) ?? []
            var count = 0
            for apt in apartments where apt.okrug == nil {
                apt.okrug = container.flipAnalyzer.extractOkrug(from: apt.address)
                count += 1
            }
            try? modelContext.save()
            backfillResult = "Обновлено: \(count)"
            isBackfilling = false
        }
    }
}

// MARK: - Tab 5: Districts

private struct DistrictsSettingsTab: View {
    @Bindable var config: ScoringConfiguration

    @AppStorage("districtModeEnabled")      private var districtMode: Bool = false
    @AppStorage("benchmarkMode")            private var benchmarkMode: BenchmarkMode = .okrug
    @AppStorage(DistrictRanking.scoresKey)  private var scoresJSON: String = DistrictRanking.defaultScoresJSON

    @Environment(AppContainer.self) private var container
    @Environment(\.modelContext) private var modelContext

    @State private var scores: [String: Int] = [:]
    @State private var searchText: String = ""
    @State private var isBackfilling: Bool = false
    @State private var backfillResult: String = ""

    private var displayEntries: [(name: String, score: Int)] {
        let all = DistrictRanking.sortedEntries(from: scores)
        guard !searchText.isEmpty else { return all }
        return all.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Mode toggles + reset bar
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Баллы по районам", isOn: $districtMode)
                        .toggleStyle(.switch)
                        .help("Локация во FlipScore считается по баллу района, а не по этажу")
                    
                    Picker("Эталон цены:", selection: $benchmarkMode) {
                        Text("Округа (АО)").tag(BenchmarkMode.okrug)
                        Text("Районы").tag(BenchmarkMode.district)
                        Text("Умный (Метро → Район)").tag(BenchmarkMode.smart)
                    }
                    .pickerStyle(.menu)
                    .frame(width: 250)
                    .help("Медианная цена. Умный режим ищет 5+ квартир у метро, иначе берёт район, затем АО.")

                    HStack {
                        Text("Перцентиль эталона: \(Int(config.targetPercentile * 100))%")
                            .frame(width: 170, alignment: .leading)
                        Slider(value: $config.targetPercentile, in: 0.1...0.95, step: 0.05)
                            .frame(width: 120)
                            .disabled(!config.isPercentileBenchmarkEnabled)
                    }
                    .help("Перцентиль 50% — обычная медиана. 80-90% — цена готовой квартиры с хорошим ремонтом (верх рынка). Полезно для оценки флип-маржи.")
                }
                .font(.subheadline)
                Spacer()
                Button("Сброс") {
                    scoresJSON = DistrictRanking.defaultScoresJSON
                    districtMode = false
                    benchmarkMode = .okrug
                    config.targetPercentile = 0.5
                }
                .foregroundStyle(.red)
                .font(.caption)
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.bar)

            Divider()

            // Search bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Поиск района или округа...", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.bar)

            Divider()

            // Score list
            List {
                Section {
                    ForEach(displayEntries, id: \.name) { entry in
                        DistrictScoreRow(
                            name: entry.name,
                            score: entry.score,
                            onChange: { newScore in
                                scores[entry.name] = newScore
                                scoresJSON = DistrictRanking.encodeScores(scores)
                            }
                        )
                    }
                } header: {
                    Text("Баллы за локацию")
                } footer: {
                    Text("Балл −1 = квартира всегда скрыта. 0–20 = очки «Локации» во FlipScore. Режим районов должен быть включён.")
                }

                Section {
                    HStack {
                        Button("Пересчитать районы") { backfillDistricts() }
                            .disabled(isBackfilling)
                        if isBackfilling {
                            ProgressView().scaleEffect(0.7).padding(.leading, 4)
                        } else if !backfillResult.isEmpty {
                            Text(backfillResult).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("База данных")
                } footer: {
                    Text("Заполняет поле «район» для квартир, добавленных до появления этой функции.")
                }
            }
            .listStyle(.inset)
        }
        .onAppear { scores = DistrictRanking.decodeScores(from: scoresJSON) }
        .onChange(of: scoresJSON) { _, new in scores = DistrictRanking.decodeScores(from: new) }
        .frame(minHeight: 480)
    }

    private func backfillDistricts() {
        isBackfilling = true
        backfillResult = ""
        Task { @MainActor in
            let descriptor = FetchDescriptor<Apartment>()
            let apartments = (try? modelContext.fetch(descriptor)) ?? []
            var count = 0
            for apt in apartments where apt.district == nil {
                apt.district = container.flipAnalyzer.extractDistrict(from: apt.address)
                count += 1
            }
            try? modelContext.save()
            backfillResult = "Обновлено: \(count)"
            isBackfilling = false
        }
    }
}

// MARK: - District Score Row

private struct DistrictScoreRow: View {
    let name: String
    let score: Int
    let onChange: (Int) -> Void

    @State private var inputText: String = ""
    @FocusState private var isEditing: Bool

    private var isBanned: Bool { score < 0 }

    var body: some View {
        HStack(spacing: 8) {
            // Editable score badge — click to type a value directly
            TextField("", text: $inputText)
                .font(.caption.monospacedDigit().bold())
                .foregroundStyle(isBanned ? .white : scoreColor)
                .multilineTextAlignment(.center)
                .textFieldStyle(.plain)
                .frame(width: 46)
                .padding(.vertical, 3)
                .background(isBanned ? Color.red : scoreColor.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .focused($isEditing)
                .onSubmit { commitInput() }
                .onChange(of: isEditing) { _, focused in if !focused { commitInput() } }
                .onAppear { syncText() }
                .onChange(of: score) { _, _ in if !isEditing { syncText() } }

            Text(name)
                .strikethrough(isBanned, color: .red)
                .foregroundStyle(isBanned ? Color.red.opacity(0.7) : .primary)

            Spacer()

            Stepper("", value: Binding(
                get: { score },
                set: { onChange(max(-1, min(20, $0))) }
            ), in: -1...20)
            .labelsHidden()
        }
    }

    private func syncText() {
        inputText = score < 0 ? "-1" : "\(score)"
    }

    private func commitInput() {
        let trimmed = inputText.trimmingCharacters(in: .whitespaces)
        if let value = Int(trimmed) {
            let clamped = max(-1, min(20, value))
            onChange(clamped)
            inputText = clamped < 0 ? "-1" : "\(clamped)"
        } else {
            syncText()  // reset on invalid input
        }
    }

    private var scoreColor: Color {
        switch score {
        case 17...: return .green
        case 13...: return .blue
        case  9...: return .orange
        default:    return .red
        }
    }
}

// MARK: - Tab 6: AI Settings

private struct AISettingsTab: View {
    @Environment(AppContainer.self) private var container

    @AppStorage("llmAnalysisTemperature") private var analysisTemp: Double = 0.3
    @AppStorage("llmChatTemperature")     private var chatTemp: Double = 0.7
    @AppStorage("llmMaxTokens")           private var maxTokens: Int = 512
    @AppStorage("llmHFEndpoint")          private var hfEndpoint: String = "https://huggingface.co"

    @State private var cacheSize: String = "…"
    @State private var isDeletingCache: Bool = false
    @State private var deleteError: String? = nil

    @State private var terminalCopied: Bool = false

    var body: some View {
        Form {
            modelStatusSection
            networkSection
            manualDownloadSection
            generationParamsSection
        }
        .formStyle(.grouped)
        .frame(minHeight: 520)
        .task { refreshCacheSize() }
    }

    // MARK: - Model Status

    private var modelStatusSection: some View {
        Section {
            // Info row
            LabeledContent("Модель") {
                Text("Gemma 4 E2B · 4-bit")
                    .foregroundStyle(.secondary)
            }
            LabeledContent("Источник") {
                Text("mlx-community/gemma-4-e2b-it-4bit")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            LabeledContent("Кэш на диске") {
                Text(cacheSize)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            LabeledContent("Статус") {
                statusBadge
            }

            // Actions
            HStack(spacing: 10) {
                // Load / retry
                if case .idle = container.llm.state {
                    Button("Загрузить модель") { container.llm.loadModel() }
                        .buttonStyle(.borderedProminent)
                } else if case .error = container.llm.state {
                    Button("Повторить загрузку") { container.llm.loadModel() }
                        .buttonStyle(.borderedProminent)
                }

                // Unload from RAM
                if case .ready = container.llm.state {
                    Button("Выгрузить из памяти") { container.llm.unloadModel() }
                }

                // Delete cache
                if LLMManager.modelCacheURL != nil {
                    Button(role: .destructive) {
                        deleteCache()
                    } label: {
                        if isDeletingCache {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Удалить кэш")
                        }
                    }
                    .disabled(isDeletingCache)
                }
            }

            if let err = deleteError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            // Download progress
            if case .downloading(let p) = container.llm.state {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Загрузка…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(p * 100))%")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(value: p)
                }
            }

        } header: {
            Text("Локальная модель")
        } footer: {
            Text("Модель хранится локально (~3 ГБ). Инференс происходит полностью на вашем устройстве без интернета. Требуется ~3 ГБ unified memory.")
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch container.llm.state {
        case .idle:
            Label("Не загружена", systemImage: "circle")
                .foregroundStyle(.secondary)
        case .downloading:
            Label("Загружается…", systemImage: "arrow.down.circle")
                .foregroundStyle(.blue)
        case .loading:
            Label("Инициализация…", systemImage: "gearshape")
                .foregroundStyle(.blue)
        case .ready:
            Label("Готова", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .generating:
            Label("Генерация…", systemImage: "waveform")
                .foregroundStyle(.yellow)
        case .error(let msg):
            Label("Ошибка", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .help(msg)
        }
    }

    // MARK: - Manual download

    private var manualCacheDir: String {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
            .first?.path ?? "~/Library/Caches"
        return "\(base)/models/mlx-community/gemma-4-e2b-it-4bit"
    }

    private var terminalCommand: String {
        """
        pip install -q huggingface_hub && \\
        HF_ENDPOINT=https://hf-mirror.com \\
        huggingface-cli download mlx-community/gemma-4-e2b-it-4bit \\
          --local-dir "\(manualCacheDir)" \\
          --local-dir-use-symlinks False
        """
    }

    private var manualDownloadSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Text("Если автозагрузка не работает, запустите в Терминале:")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(terminalCommand)
                    .font(.system(.caption2, design: .monospaced))
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .textSelection(.enabled)

                HStack {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(terminalCommand, forType: .string)
                        terminalCopied = true
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            terminalCopied = false
                        }
                    } label: {
                        Label(terminalCopied ? "Скопировано!" : "Скопировать команду",
                              systemImage: terminalCopied ? "checkmark" : "doc.on.doc")
                            .font(.caption.weight(.medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Spacer()

                    Text("После загрузки нажмите «Повторить загрузку»")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        } header: {
            Text("Ручная загрузка (Терминал)")
        } footer: {
            Text("Требует Python и pip. Загрузка займёт ~5-15 минут. После завершения нажмите «Повторить загрузку» в разделе выше — приложение подхватит файлы из кэша.")
        }
    }

    // MARK: - Network

    private var networkSection: some View {
        Section {
            Picker("Источник загрузки", selection: $hfEndpoint) {
                Text("Hugging Face (по умолчанию)").tag("https://huggingface.co")
                Text("hf-mirror.com (зеркало для РФ)").tag("https://hf-mirror.com")
            }
            .pickerStyle(.menu)
        } header: {
            Text("Сеть")
        } footer: {
            Text("Если загрузка зависает или обрывается, попробуйте зеркало hf-mirror.com. При смене источника повторите загрузку.")
        }
    }

    // MARK: - Generation Parameters

    private var generationParamsSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("Температура анализа")
                    Spacer()
                    Text(String(format: "%.2f", analysisTemp))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(width: 36)
                }
                Slider(value: $analysisTemp, in: 0.1...1.0, step: 0.05)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("Температура чата")
                    Spacer()
                    Text(String(format: "%.2f", chatTemp))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(width: 36)
                }
                Slider(value: $chatTemp, in: 0.1...1.0, step: 0.05)
            }

            Stepper(value: $maxTokens, in: 128...2048, step: 128) {
                HStack {
                    Text("Макс. токенов")
                    Spacer()
                    Text("\(maxTokens)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            Button("Сбросить по умолчанию") {
                analysisTemp = 0.3
                chatTemp = 0.7
                maxTokens = 512
            }
            .foregroundStyle(.red)

        } header: {
            Text("Параметры генерации")
        } footer: {
            Text("Температура анализа — для структурированного JSON (ниже = точнее). Температура чата — для свободных ответов (выше = разнообразнее).")
        }
    }

    // MARK: - Helpers

    private func refreshCacheSize() {
        let bytes = LLMManager.modelCacheSizeBytes()
        if bytes == 0 {
            cacheSize = LLMManager.modelCacheURL == nil ? "Не загружена" : "0 Б"
        } else {
            cacheSize = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        }
    }

    private func deleteCache() {
        isDeletingCache = true
        deleteError = nil
        if case .ready = container.llm.state { container.llm.unloadModel() }
        Task {
            do {
                try LLMManager.deleteModelCache()
                await MainActor.run {
                    isDeletingCache = false
                    refreshCacheSize()
                }
            } catch {
                await MainActor.run {
                    deleteError = error.localizedDescription
                    isDeletingCache = false
                }
            }
        }
    }
}

#Preview {
    SettingsView()
}
