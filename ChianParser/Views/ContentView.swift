//
//  ContentView.swift
//  ChianParser
//

import SwiftUI
import SwiftData
import WebKit

// MARK: - Entry Point View

struct ContentView: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.modelContext) private var modelContext
    @Query private var apartments: [Apartment]
    @State private var viewModel: ContentViewModel?

    var body: some View {
        Group {
            if let viewModel {
                ContentBody(viewModel: viewModel, apartments: apartments)
            }
        }
        .task {
            guard viewModel == nil else { return }
            viewModel = container.makeContentViewModel(modelContext: modelContext)
        }
    }
}

// MARK: - Main UI Body

struct ContentBody: View {
    @Bindable var viewModel: ContentViewModel
    let apartments: [Apartment]

    // Demand thresholds from AppStorage (shared with SettingsView)
    @AppStorage("demandThresholdModerate") private var moderate: Int = DemandThresholds.default.moderate
    @AppStorage("demandThresholdMarket")   private var market: Int   = DemandThresholds.default.market
    @AppStorage("demandThresholdHot")      private var hot: Int      = DemandThresholds.default.hot

    // Metro banlist — JSON stored in AppStorage, decoded once into @State
    @AppStorage(MetroBanlist.appStorageKey) private var metroBanlistJSON: String = MetroBanlist.defaultJSON
    @State private var metroBanlist: Set<String> = []

    // Search URL list — JSON stored in AppStorage, decoded once into @State
    @AppStorage(SearchURLList.appStorageKey) private var searchURLListJSON: String = SearchURLList.defaultJSON
    @State private var searchURLs: [String] = []

    // District settings — synced to viewModel on change
    @AppStorage("districtModeEnabled")          private var districtModeEnabled: Bool = false
    @AppStorage("districtBenchmarkEnabled")     private var districtBenchmarkEnabled: Bool = false
    @AppStorage(DistrictRanking.scoresKey)      private var districtScoresJSON: String = DistrictRanking.defaultScoresJSON

    // Parser settings from AppStorage (shared with SettingsView → Парсинг tab)
    @AppStorage("parserAutoDetail")        private var autoDetail: Bool = true
    @AppStorage("parserAutoCheck")         private var autoCheck: Bool = true
    @AppStorage("parserStaleDays")         private var staleDays: Int = 3
    @AppStorage("parserEnablePagination")  private var enablePagination: Bool = true
    @AppStorage("parserMaxPages")          private var maxPages: Int = 1
    @AppStorage("parserMode")              private var parserMode: ParsingMode = .parallel
    @AppStorage("parserRequireDetail")     private var requireDetailParsed: Bool = false
    @AppStorage("hideStudios")             private var hideStudios: Bool = false
    @AppStorage("hideApartments")          private var hideApartments: Bool = false
    @AppStorage("metroMaxDistance")        private var maxMetroDistance: Int = 0
    @AppStorage("metroWalkOnly")           private var metroWalkOnly: Bool = false
    @AppStorage("minBuildingFloors")       private var minBuildingFloors: Int = 6

    @Environment(\.openSettings) private var openSettings

    @State private var showURLSearch: Bool = false
    @State private var urlSearchText: String = ""
    @State private var urlSearchResult: Apartment? = nil   // non-nil → show sheet
    @State private var urlSearchNotFound: Bool = false

    private var thresholds: DemandThresholds {
        DemandThresholds(moderate: moderate, market: market, hot: hot)
    }

    var body: some View {
        coreView
            .toolbar { toolbarContent }
            .confirmationDialog(
                "Удалить все данные?",
                isPresented: $viewModel.showClearDataConfirmation,
                titleVisibility: .visible
            ) {
                Button("Удалить все квартиры (\(apartments.count))", role: .destructive) {
                    viewModel.clearAllData(apartments: apartments)
                }
                Button("Отмена", role: .cancel) {}
            } message: {
                Text("Это действие нельзя отменить. Будут удалены все сохранённые квартиры и история цен.")
            }
            .task { syncViewModelSettings() }
    }

    private var coreView: some View {
        splitView
            .onChange(of: requireDetailParsed) { _, v in
                viewModel.requireDetailParsed = v
                viewModel.scheduleRefresh(from: apartments, thresholds: thresholds, metroBanlist: metroBanlist)
            }
            .onChange(of: hideStudios) { _, v in
                viewModel.hideStudios = v
                viewModel.scheduleRefresh(from: apartments, thresholds: thresholds, metroBanlist: metroBanlist)
            }
            .onChange(of: hideApartments) { _, v in
                viewModel.hideApartments = v
                viewModel.scheduleRefresh(from: apartments, thresholds: thresholds, metroBanlist: metroBanlist)
            }
            .onChange(of: maxMetroDistance) { _, v in
                viewModel.maxMetroDistance = v
                viewModel.scheduleRefresh(from: apartments, thresholds: thresholds, metroBanlist: metroBanlist)
            }
            .onChange(of: metroWalkOnly) { _, v in
                viewModel.metroWalkOnly = v
                viewModel.scheduleRefresh(from: apartments, thresholds: thresholds, metroBanlist: metroBanlist)
            }
            .onChange(of: minBuildingFloors) { _, v in
                viewModel.minBuildingFloors = v
                viewModel.scheduleRefresh(from: apartments, thresholds: thresholds, metroBanlist: metroBanlist)
            }
    }

    private var splitView: some View {
        NavigationSplitView {
            apartmentList
        } detail: {
            scrapingControlPanel
        }
        .onChange(of: metroBanlistJSON) { _, new in
            metroBanlist = MetroBanlist.decode(from: new)
            viewModel.scheduleRefresh(from: apartments, thresholds: thresholds, metroBanlist: metroBanlist)
        }
        .onChange(of: districtModeEnabled) { _, v in
            viewModel.useDistrictScore = v
            viewModel.activeDistrictFilters = []
            viewModel.scheduleRefresh(from: apartments, thresholds: thresholds, metroBanlist: metroBanlist)
        }
        .onChange(of: districtBenchmarkEnabled) { _, v in
            viewModel.useDistrictBenchmark = v
            viewModel.scheduleRefresh(from: apartments, thresholds: thresholds, metroBanlist: metroBanlist)
        }
        .onChange(of: districtScoresJSON) { _, new in
            viewModel.districtScores = DistrictRanking.decodeScores(from: new)
            viewModel.scheduleRefresh(from: apartments, thresholds: thresholds, metroBanlist: metroBanlist)
        }
        .onChange(of: searchURLListJSON) { _, new in searchURLs = SearchURLList.decode(from: new) }
        .onChange(of: autoDetail)        { _, v in viewModel.autoDetailParsing = v }
        .onChange(of: autoCheck)         { _, v in viewModel.autoCheckActivity = v }
        .onChange(of: staleDays)         { _, v in viewModel.staleDaysThreshold = v }
        .onChange(of: enablePagination)  { _, v in viewModel.enablePagination = v }
        .onChange(of: maxPages)          { _, v in viewModel.maxPages = v }
        .onChange(of: parserMode)        { _, v in viewModel.parsingMode = v }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            sortMenu
        }
        ToolbarItemGroup {
            Button {
                viewModel.startDetailParsing(apartments: apartments)
            } label: {
                Label("Детальный парсинг", systemImage: "arrow.down.circle")
            }
            .disabled(apartments.isEmpty || viewModel.detailLoader.isLoading || viewModel.isScraping)

            Button {
                viewModel.checkStaleApartments(from: apartments)
            } label: {
                Label("Проверить активность", systemImage: "arrow.clockwise.circle")
            }
            .disabled(apartments.isEmpty || viewModel.detailLoader.isLoading)
            .help("Проверить квартиры, не появлявшиеся в поиске более \(viewModel.staleDaysThreshold) дн.")
        }
        ToolbarItemGroup {
            Menu {
                Button {
                    viewModel.exportData(format: .csv, apartments: apartments)
                } label: {
                    Label("Экспорт в CSV", systemImage: "doc.text")
                }
                Button {
                    viewModel.exportData(format: .json, apartments: apartments)
                } label: {
                    Label("Экспорт в JSON", systemImage: "doc.badge.gearshape")
                }
            } label: {
                Label("Экспорт", systemImage: "square.and.arrow.up")
            }
            .disabled(apartments.isEmpty)

            Button(role: .destructive) {
                viewModel.showClearDataConfirmation = true
            } label: {
                Label("Очистить данные", systemImage: "trash")
            }
            .disabled(apartments.isEmpty)
        }
        ToolbarItemGroup {
            Button {
                showURLSearch.toggle()
                if !showURLSearch {
                    urlSearchText = ""
                    urlSearchNotFound = false
                }
            } label: {
                Label("Поиск по ссылке", systemImage: showURLSearch ? "magnifyingglass.circle.fill" : "magnifyingglass.circle")
            }
            .help("Найти квартиру по ссылке Циан")

            Button {
                openSettings()
            } label: {
                Label("Настройки", systemImage: "gearshape")
            }
        }
    }

    // MARK: - Settings sync

    private func syncViewModelSettings() {
        metroBanlist = MetroBanlist.decode(from: metroBanlistJSON)
        searchURLs   = SearchURLList.decode(from: searchURLListJSON)
        viewModel.useDistrictScore     = districtModeEnabled
        viewModel.useDistrictBenchmark = districtBenchmarkEnabled
        viewModel.districtScores       = DistrictRanking.decodeScores(from: districtScoresJSON)
        viewModel.autoDetailParsing    = autoDetail
        viewModel.autoCheckActivity    = autoCheck
        viewModel.staleDaysThreshold   = staleDays
        viewModel.enablePagination     = enablePagination
        viewModel.maxPages             = maxPages
        viewModel.parsingMode          = parserMode
        viewModel.requireDetailParsed  = requireDetailParsed
        viewModel.hideStudios          = hideStudios
        viewModel.hideApartments       = hideApartments
        viewModel.maxMetroDistance     = maxMetroDistance
        viewModel.metroWalkOnly        = metroWalkOnly
        viewModel.minBuildingFloors    = minBuildingFloors
        // Re-run scoring so all persisted settings take effect on first render
        viewModel.scheduleRefresh(from: apartments, thresholds: thresholds, metroBanlist: metroBanlist)
    }

    // MARK: - Sidebar: Apartment List

    private var apartmentList: some View {
        List {
            ForEach(viewModel.cachedScores, id: \.0.id) { apartment, flipScore in
                NavigationLink(value: apartment) {
                    ApartmentRow(apartment: apartment, flipScore: flipScore)
                }
            }
        }
        .onAppear { viewModel.refreshScores(from: apartments, thresholds: thresholds, metroBanlist: metroBanlist) }
        .onChange(of: apartments)                    { _, new in viewModel.scheduleRefresh(from: new, thresholds: thresholds, metroBanlist: metroBanlist) }
        .onChange(of: viewModel.sortOrder) { _, _ in
            // Sort is a user action — animate the reorder visually
            withAnimation(.easeInOut(duration: 0.2)) {
                viewModel.refreshScores(from: apartments, thresholds: thresholds, metroBanlist: metroBanlist)
            }
        }
        .onChange(of: moderate)                      { _, _ in viewModel.scheduleRefresh(from: apartments, thresholds: thresholds, metroBanlist: metroBanlist) }
        .onChange(of: market)                        { _, _ in viewModel.scheduleRefresh(from: apartments, thresholds: thresholds, metroBanlist: metroBanlist) }
        .onChange(of: hot)                           { _, _ in viewModel.scheduleRefresh(from: apartments, thresholds: thresholds, metroBanlist: metroBanlist) }
        .onChange(of: viewModel.activeStatusFilters) { _, _ in viewModel.scheduleRefresh(from: apartments, thresholds: thresholds, metroBanlist: metroBanlist) }
        .onChange(of: viewModel.activeOkrugFilters)  { _, _ in viewModel.scheduleRefresh(from: apartments, thresholds: thresholds, metroBanlist: metroBanlist) }
        .onChange(of: viewModel.showAuctions)        { _, _ in viewModel.scheduleRefresh(from: apartments, thresholds: thresholds, metroBanlist: metroBanlist) }
        .onChange(of: viewModel.showDeposits)        { _, _ in viewModel.scheduleRefresh(from: apartments, thresholds: thresholds, metroBanlist: metroBanlist) }
        .onChange(of: viewModel.activeRoomFilters)     { _, _ in viewModel.scheduleRefresh(from: apartments, thresholds: thresholds, metroBanlist: metroBanlist) }
        .onChange(of: viewModel.activeDistrictFilters) { _, _ in viewModel.scheduleRefresh(from: apartments, thresholds: thresholds, metroBanlist: metroBanlist) }

        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                if showURLSearch {
                    URLSearchBar(
                        text: $urlSearchText,
                        notFound: urlSearchNotFound,
                        onSubmit: {
                            let result = viewModel.lookupApartment(byURL: urlSearchText)
                            if let result {
                                urlSearchResult = result
                                urlSearchNotFound = false
                            } else {
                                urlSearchNotFound = true
                            }
                        },
                        onClose: {
                            showURLSearch = false
                            urlSearchText = ""
                            urlSearchNotFound = false
                        }
                    )
                    Divider()
                }
                StatusFilterBar(viewModel: viewModel)
                if !viewModel.availableRoomCounts.isEmpty {
                    Divider()
                    RoomFilterBar(viewModel: viewModel)
                }
                if !viewModel.availableOkrugs.isEmpty {
                    Divider()
                    OkrugFilterBar(viewModel: viewModel)
                }
                if viewModel.useDistrictScore && !viewModel.availableDistricts.isEmpty {
                    Divider()
                    DistrictFilterBar(viewModel: viewModel)
                }
            }
        }
        .sheet(item: $urlSearchResult) { apartment in
            NavigationStack {
                let flipScore = viewModel.cachedScores.first(where: { $0.0.id == apartment.id })?.1
                ApartmentDetailView(apartment: apartment, flipScore: flipScore)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Закрыть") { urlSearchResult = nil }
                        }
                    }
            }
            .frame(minWidth: 600, minHeight: 500)
        }
        .navigationTitle("Показано: \(viewModel.cachedScores.count)/\(apartments.count)")
        .navigationSubtitle(viewModel.detailLoader.isLoading ? viewModel.detailLoader.statusMessage : "")
        .navigationDestination(for: Apartment.self) { apartment in
            let flipScore = viewModel.cachedScores.first(where: { $0.0.id == apartment.id })?.1
            ApartmentDetailView(apartment: apartment, flipScore: flipScore)
        }
    }

    private var sortMenu: some View {
        HStack(spacing: 4) {
            Menu {
                ForEach(ContentViewModel.SortOrder.allCases) { order in
                    Button {
                        viewModel.sortOrder = order
                        viewModel.sortAscending = order.naturalAscending
                    } label: {
                        Label(order.rawValue, systemImage: order.icon)
                        if viewModel.sortOrder == order {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            } label: {
                Label("Сортировка: \(viewModel.sortOrder.rawValue)", systemImage: "arrow.up.arrow.down")
            }

            Button {
                viewModel.sortAscending.toggle()
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.refreshScores(from: apartments, thresholds: thresholds, metroBanlist: metroBanlist)
                }
            } label: {
                Image(systemName: viewModel.sortAscending ? "arrow.up" : "arrow.down")
            }
            .help(viewModel.sortAscending ? "По возрастанию" : "По убыванию")
        }
    }

    // MARK: - Detail: Scraping Control Panel

    private var scrapingControlPanel: some View {
        VStack {
            HStack {
                // URL list status indicator
                VStack(alignment: .leading, spacing: 2) {
                    if viewModel.isScraping {
                        Text("Ссылка \(viewModel.currentURLIndex + 1) из \(viewModel.searchURLs.count)")
                            .font(.subheadline.weight(.medium))
                        if let currentURL = viewModel.currentURL {
                            Text(currentURL.absoluteString)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    } else {
                        Text(searchURLs.isEmpty ? "Нет ссылок" : "\(searchURLs.count) ссылок в очереди")
                            .font(.subheadline)
                            .foregroundStyle(searchURLs.isEmpty ? .red : .secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Compact settings summary — change in Settings (Cmd+,)
                HStack(spacing: 8) {
                    Label(viewModel.autoDetailParsing ? "Авто-детали" : "Без авто-деталей",
                          systemImage: viewModel.autoDetailParsing ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(viewModel.autoDetailParsing ? .green : .secondary)
                    if viewModel.enablePagination {
                        Label("\(viewModel.maxPages) стр.", systemImage: "doc.on.doc")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.caption)
                .help("Настройки парсинга — Cmd+,")

                Button(viewModel.isScraping ? "Остановить" : "Запустить парсер") {
                    if viewModel.isScraping {
                        viewModel.stopScraping()
                    } else {
                        viewModel.startScraping(urls: searchURLs)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.isScraping && searchURLs.isEmpty)
            }
            .padding()

            if viewModel.isScraping, let url = viewModel.currentURL {
                CianWebView(url: url, onDataReceived: { jsonString in
                    viewModel.parseReceivedData(jsonString)
                }, onCaptchaDetected: {
                    viewModel.handleCaptchaDetected()
                })
                .background(Color.black.opacity(0.05))
                .cornerRadius(8)
                .padding()

                if viewModel.showCaptchaAlert {
                    captchaAlert
                }
            } else if viewModel.detailLoader.isLoading, let detailWebView = viewModel.detailLoader.webView {
                ExistingWebView(webView: detailWebView)
                    .background(Color.black.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding()

                if viewModel.detailLoader.captchaDetected {
                    detailCaptchaAlert
                }
            } else {
                ContentUnavailableView(
                    "Парсер не запущен",
                    systemImage: "magnifyingglass",
                    description: Text("Введите URL поиска и нажмите Запустить")
                )
            }

            if viewModel.detailLoader.isLoading {
                detailParsingProgress
            }

            Spacer()

            Text(viewModel.log)
                .font(.caption)
                .monospaced()
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.1))
        }
    }

    // MARK: - Detail Captcha Alert

    private var detailCaptchaAlert: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text("Капча при детальном парсинге")
                    .fontWeight(.semibold)
            }
            .font(.headline)

            Text("Решите капчу в браузере выше — парсинг продолжится автоматически после загрузки страницы")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(12)
        .padding()
    }

    // MARK: - Captcha Alert

    private var captchaAlert: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text("Обнаружена капча")
                    .fontWeight(.semibold)
            }
            .font(.headline)

            Text("Решите капчу в окне браузера выше, затем нажмите \"Продолжить\"")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            Button("Продолжить парсинг") {
                viewModel.dismissCaptcha()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(12)
        .padding()
    }

    // MARK: - Detail Parsing Progress

    private var detailParsingProgress: some View {
        VStack(spacing: 12) {
            ProgressView(
                value: Double(viewModel.detailLoader.currentProgress),
                total: Double(viewModel.detailLoader.totalPages)
            ) {
                HStack {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundColor(.blue)
                    Text("Детальный парсинг")
                        .fontWeight(.semibold)
                }
            } currentValueLabel: {
                Text("\(viewModel.detailLoader.currentProgress) из \(viewModel.detailLoader.totalPages)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Text(viewModel.detailLoader.statusMessage)
                .font(.caption)
                .foregroundColor(.secondary)

            Button("Остановить") {
                viewModel.detailLoader.stopLoading()
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .background(Color.blue.opacity(0.1))
        .cornerRadius(12)
        .padding()
    }
}

// MARK: - Apartment Row

private struct ApartmentRow: View {
    let apartment: Apartment
    let flipScore: FlipScoreResult

    @State private var isHovered = false

    private var daysSinceLastSeen: Int {
        Calendar.current.dateComponents([.day], from: apartment.lastSeenInSearch, to: Date()).day ?? 0
    }

    var body: some View {
        HStack(spacing: 0) {
            // Status color strip
            Rectangle()
                .fill(apartment.status.color)
                .frame(width: 3)
                .clipShape(RoundedRectangle(cornerRadius: 1.5))

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(apartment.title)
                        .font(.headline)
                    if daysSinceLastSeen >= 7 {
                        Image(systemName: "eye.slash")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            .help("Не появлялась в поиске \(daysSinceLastSeen) дн. — возможно снята с продажи")
                    }
                    Spacer()
                    if isHovered {
                        QuickStatusButtons(apartment: apartment)
                    } else {
                        FlipScoreBadge(score: flipScore.totalScore)
                    }
                }

                HStack {
                    Text("\(apartment.price.formatted(.number)) ₽")
                        .foregroundColor(.blue)
                        .font(.subheadline.weight(.semibold))

                    if apartment.priceHistory.count > 1 {
                        let oldPrice = apartment.priceHistory[apartment.priceHistory.count - 2].price
                        let diff = apartment.price - oldPrice
                        if diff != 0 {
                            HStack(spacing: 2) {
                                Image(systemName: diff < 0 ? "arrow.down" : "arrow.up")
                                Text("\(abs(diff).formatted(.number))")
                            }
                            .font(.caption)
                            .foregroundColor(diff < 0 ? .green : .red)
                        }
                    }

                    Spacer()
                    DemandBadge(level: flipScore.demandLevel)
                }

                Text(apartment.address)
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack(spacing: 12) {
                    if let area = apartment.area {
                        Label(String(format: "%.1f м²", area), systemImage: "square")
                            .font(.caption2)
                    }
                    if let floor = apartment.floor, let total = apartment.totalFloors {
                        Label("\(floor)/\(total)", systemImage: "building.2")
                            .font(.caption2)
                    }
                    if let priceSqm = flipScore.priceSqm {
                        Label(String(format: "%.0f ₽/м²", priceSqm), systemImage: "chart.bar")
                            .font(.caption2)
                    }
                }
                .foregroundColor(.secondary)
            }
            .padding(.leading, 8)
            .padding(.vertical, 4)
        }
        .onHover { isHovered = $0 }
    }
}

// MARK: - Quick Status Buttons (shown on hover)

private struct QuickStatusButtons: View {
    let apartment: Apartment

    var body: some View {
        HStack(spacing: 4) {
            ForEach(quickActions, id: \.self) { status in
                Button {
                    apartment.status = status
                } label: {
                    Image(systemName: status.icon)
                        .foregroundStyle(status.color)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .help(status.label)
            }
        }
    }

    /// Show the next logical statuses + ban, excluding the current one
    private var quickActions: [ApartmentStatus] {
        let all: [ApartmentStatus] = [.study, .call, .visit, .calc, .deal, .waiting, .ban]
        return all.filter { $0 != apartment.status }
    }
}

// MARK: - URL Search Bar

private struct URLSearchBar: View {
    @Binding var text: String
    let notFound: Bool
    let onSubmit: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Вставьте ссылку на квартиру Циан...", text: $text)
                .textFieldStyle(.plain)
                .onSubmit(onSubmit)
            if notFound {
                Label("Не найдено", systemImage: "questionmark.circle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial)
    }
}

// MARK: - Room Filter Bar

private struct RoomFilterBar: View {
    @Bindable var viewModel: ContentViewModel

    private func label(for bucket: Int) -> String {
        switch bucket {
        case 0:  return "Студия"
        case 4:  return "4К+"
        default: return "\(bucket)К"
        }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(viewModel.availableRoomCounts, id: \.self) { bucket in
                    let isActive = viewModel.activeRoomFilters.contains(bucket)
                    Button {
                        viewModel.toggleRoomFilter(bucket)
                    } label: {
                        Text(label(for: bucket))
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(isActive ? Color.indigo.opacity(0.18) : Color.clear)
                            .foregroundStyle(isActive ? Color.indigo : .secondary)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(
                                isActive ? Color.indigo.opacity(0.5) : Color.secondary.opacity(0.3),
                                lineWidth: 1
                            ))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .background(.regularMaterial)
    }
}

// MARK: - District Filter Bar

private struct DistrictFilterBar: View {
    @Bindable var viewModel: ContentViewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(viewModel.availableDistricts, id: \.self) { district in
                    let isActive = viewModel.activeDistrictFilters.contains(district)
                    Button {
                        viewModel.toggleDistrictFilter(district)
                    } label: {
                        Text(district)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(isActive ? Color.green.opacity(0.18) : Color.clear)
                            .foregroundStyle(isActive ? Color.green : .secondary)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(
                                isActive ? Color.green.opacity(0.5) : Color.secondary.opacity(0.3),
                                lineWidth: 1
                            ))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .background(.regularMaterial)
    }
}

// MARK: - Okrug Filter Bar

private struct OkrugFilterBar: View {
    @Bindable var viewModel: ContentViewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(viewModel.availableOkrugs, id: \.self) { okrug in
                    let isActive = viewModel.activeOkrugFilters.contains(okrug)
                    Button {
                        viewModel.toggleOkrugFilter(okrug)
                    } label: {
                        Text(okrug)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(isActive ? Color.blue.opacity(0.18) : Color.clear)
                            .foregroundStyle(isActive ? Color.blue : .secondary)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(
                                isActive ? Color.blue.opacity(0.5) : Color.secondary.opacity(0.3),
                                lineWidth: 1
                            ))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .background(.regularMaterial)
    }
}

// MARK: - Status Filter Bar

private struct StatusFilterBar: View {
    @Bindable var viewModel: ContentViewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(ApartmentStatus.allCases.filter { $0 != .auction && $0 != .deposit }) { status in
                    let isActive = viewModel.activeStatusFilters.contains(status)
                    Button {
                        viewModel.toggleStatusFilter(status)
                    } label: {
                        Label(status.label, systemImage: status.icon)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(isActive ? status.color.opacity(0.2) : Color.clear)
                            .foregroundStyle(isActive ? status.color : .secondary)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(isActive ? status.color.opacity(0.5) : Color.secondary.opacity(0.3), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }

                Divider().frame(height: 16)

                autoFlagChip(
                    label: "Аукционы",
                    icon: "hammer",
                    isShown: viewModel.showAuctions,
                    color: .brown
                ) { viewModel.showAuctions.toggle() }

                autoFlagChip(
                    label: "Залог",
                    icon: "banknote",
                    isShown: viewModel.showDeposits,
                    color: .teal
                ) { viewModel.showDeposits.toggle() }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(.regularMaterial)
    }

    private func autoFlagChip(
        label: String,
        icon: String,
        isShown: Bool,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(isShown ? color.opacity(0.2) : Color.clear)
                .foregroundStyle(isShown ? color : .secondary)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(isShown ? color.opacity(0.5) : Color.secondary.opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help(isShown ? "Скрыть \(label.lowercased())" : "Показать \(label.lowercased())")
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Apartment.self, inMemory: true)
}
// MARK: - Wrapper for an externally-owned WKWebView

/// Embeds an existing WKWebView instance into the SwiftUI view hierarchy without recreating it.
/// Used to display DetailPageLoader's hidden webview so the user can see and solve captchas.
struct ExistingWebView: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

