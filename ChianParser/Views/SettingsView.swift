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
    var body: some View {
        TabView {
            DemandSettingsTab()
                .tabItem {
                    Label("Спрос", systemImage: "chart.bar.fill")
                }
                .tag(0)

            MetroBanlistTab()
                .tabItem {
                    Label("Станции МЦД", systemImage: "tram.fill")
                }
                .tag(1)

            SearchURLListTab()
                .tabItem {
                    Label("Ссылки поиска", systemImage: "link")
                }
                .tag(2)

            ParserSettingsTab()
                .tabItem {
                    Label("Парсинг", systemImage: "gearshape.2")
                }
                .tag(3)
        }
        .frame(width: 520)
    }
}

// MARK: - Tab 1: Demand Thresholds

private struct DemandSettingsTab: View {
    @AppStorage("demandThresholdModerate") private var moderate: Int = DemandThresholds.default.moderate
    @AppStorage("demandThresholdMarket")   private var market: Int   = DemandThresholds.default.market
    @AppStorage("demandThresholdHot")      private var hot: Int      = DemandThresholds.default.hot

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

    @State private var newStation: String = ""
    @State private var searchText: String = ""

    private var bannedStations: [String] {
        let all = MetroBanlist.decode(from: metroBanlistJSON).sorted()
        guard !searchText.isEmpty else { return all }
        return all.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
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
    @AppStorage("parserEnablePagination") private var enablePagination: Bool = true
    @AppStorage("parserMaxPages")         private var maxPages: Int = 1
    @AppStorage("parserMode")             private var parserMode: ParsingMode = .parallel

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
                Stepper(value: $staleDays, in: 1...30) {
                    HStack {
                        Text("Порог устаревания")
                        Spacer()
                        Text("\(staleDays) дн.")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .disabled(!autoCheck)
            } header: {
                Text("Детальный парсинг")
            } footer: {
                Text("Авто-детали — парсить каждую новую квартиру сразу после находки.\nАвто-проверка — перепроверять квартиры, которые не появлялись в поиске дольше порога.")
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

#Preview {
    SettingsView()
}
