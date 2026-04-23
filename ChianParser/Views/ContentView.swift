//
//  ContentView.swift
//  ChianParser
//

import SwiftUI
import SwiftData

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

    @State private var showSettings = false

    private var thresholds: DemandThresholds {
        DemandThresholds(moderate: moderate, market: market, hot: hot)
    }

    var body: some View {
        NavigationSplitView {
            apartmentList
        } detail: {
            scrapingControlPanel
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                SettingsView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Готово") { showSettings = false }
                        }
                    }
            }
            .frame(minWidth: 380, minHeight: 460)
        }
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
        .onAppear { viewModel.refreshScores(from: apartments, thresholds: thresholds) }
        .onChange(of: apartments)                    { _, new in viewModel.scheduleRefresh(from: new, thresholds: thresholds) }
        .onChange(of: viewModel.sortOrder)           { _, _ in viewModel.scheduleRefresh(from: apartments, thresholds: thresholds) }
        .onChange(of: moderate)                      { _, _ in viewModel.scheduleRefresh(from: apartments, thresholds: thresholds) }
        .onChange(of: market)                        { _, _ in viewModel.scheduleRefresh(from: apartments, thresholds: thresholds) }
        .onChange(of: hot)                           { _, _ in viewModel.scheduleRefresh(from: apartments, thresholds: thresholds) }
        .onChange(of: viewModel.activeStatusFilters) { _, _ in viewModel.scheduleRefresh(from: apartments, thresholds: thresholds) }
        .safeAreaInset(edge: .top, spacing: 0) {
            StatusFilterBar(viewModel: viewModel)
        }
        .navigationTitle("Показано: \(viewModel.cachedScores.count)/\(apartments.count)")
        .navigationSubtitle(viewModel.detailLoader.isLoading ? viewModel.detailLoader.statusMessage : "")
        .navigationDestination(for: Apartment.self) { apartment in
            let flipScore = viewModel.cachedScores.first(where: { $0.0.id == apartment.id })?.1
            ApartmentDetailView(apartment: apartment, flipScore: flipScore)
        }
        .toolbar {
            ToolbarItemGroup {
                sortMenu

                Button {
                    viewModel.startDetailParsing(apartments: apartments)
                } label: {
                    Label("Детальный парсинг", systemImage: "arrow.down.circle")
                }
                .disabled(apartments.isEmpty || viewModel.detailLoader.isLoading || viewModel.isScraping)

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

                Button {
                    showSettings = true
                } label: {
                    Label("Настройки", systemImage: "gearshape")
                }
            }
        }
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
    }

    private var sortMenu: some View {
        Menu {
            ForEach(ContentViewModel.SortOrder.allCases) { order in
                Button {
                    viewModel.sortOrder = order
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
    }

    // MARK: - Detail: Scraping Control Panel

    private var scrapingControlPanel: some View {
        VStack {
            HStack {
                TextField("URL поиска Циан", text: $viewModel.urlString)
                    .textFieldStyle(.roundedBorder)

                Toggle("Авто-детали", isOn: $viewModel.autoDetailParsing)
                    .toggleStyle(.switch)
                    .help("Автоматически запускать детальный парсинг для каждой найденной квартиры")

                Toggle("Несколько страниц", isOn: $viewModel.enablePagination)
                    .toggleStyle(.switch)

                if viewModel.enablePagination {
                    Stepper("Страниц: \(viewModel.maxPages)", value: $viewModel.maxPages, in: 1...20)
                        .frame(width: 150)
                }

                Button(viewModel.isScraping ? "Остановить" : "Запустить парсер") {
                    if viewModel.isScraping {
                        viewModel.stopScraping()
                    } else {
                        viewModel.startScraping()
                    }
                }
                .buttonStyle(.borderedProminent)
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

// MARK: - Status Filter Bar

private struct StatusFilterBar: View {
    @Bindable var viewModel: ContentViewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(ApartmentStatus.allCases) { status in
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
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(.regularMaterial)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Apartment.self, inMemory: true)
}
