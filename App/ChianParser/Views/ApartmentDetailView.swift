//
//  ApartmentDetailView.swift
//  ChianParser
//
//  Детальный вид квартиры
//

import SwiftUI
import SwiftData

struct ApartmentDetailView: View {
    @Bindable var apartment: Apartment
    let flipScore: FlipScoreResult?
    var onAppearAction: (() -> Void)? = nil
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AppContainer.self) private var container
    @AppStorage("useYesterdayViews") private var useYesterdayViews: Bool = true

    // MARK: - AI Analysis state

    private enum AnalysisState {
        case idle, loading
        case ready(ApartmentAnalysis)
        case error(String)

        var isIdle: Bool    { if case .idle    = self { return true }; return false }
        var isLoading: Bool { if case .loading = self { return true }; return false }
    }

    @State private var analysisState: AnalysisState = .idle
    @State private var shimmerOn: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                imagesGalleryView

                VStack(alignment: .leading, spacing: 15) {
                    HStack{
                        headerView
                        Spacer()
                        openLinkButton
                    }
                    metroView
                    statsHighlightView
                    waitingConditionView
                    flipScoreView
                    currentPriceView
                    financialCalculatorView
                    priceHistoryView
                    characteristicsGrid
                    descriptionView
                    aiAnalysisView
                    statusAndNotesView
                    sellerView
                    metadataView
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .navigationTitle("Детали")
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    dismiss()
                } label: {
                    Label("К парсеру", systemImage: "chevron.left")
                }
            }
        }
        .onAppear {
            onAppearAction?()
        }
    }

    // MARK: - AI Analysis

    @ViewBuilder
    private var aiAnalysisView: some View {
        if let description = apartment.apartmentDescription, !description.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("AI-анализ", systemImage: "sparkles")
                        .font(.headline)
                    Spacer()
                    aiActionButton(description: description)
                }

                switch analysisState {
                case .idle:
                    EmptyView()
                case .loading:
                    aiSkeletonView
                case .ready(let analysis):
                    aiResultView(analysis)
                case .error(let msg):
                    Label(msg, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding()
            .background(Color.purple.opacity(0.04))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.purple.opacity(0.18), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
        }
    }

    @ViewBuilder
    private func aiActionButton(description: String) -> some View {
        switch container.llm.state {
        case .idle:
            Button {
                container.llm.loadModel()
            } label: {
                Label("Загрузить модель", systemImage: "arrow.down.circle")
                    .font(.caption.weight(.medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

        case .downloading(let p):
            HStack(spacing: 6) {
                ProgressView(value: p)
                    .frame(width: 60)
                Text("\(Int(p * 100))%")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

        case .loading:
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text("Загрузка…")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

        case .ready:
            Button {
                runAIAnalysis(description: description)
            } label: {
                Label(
                    analysisState.isIdle ? "Сделать AI-сводку" : "Обновить",
                    systemImage: "sparkles"
                )
                .font(.caption.weight(.medium))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(analysisState.isLoading)

        case .generating:
            ProgressView().controlSize(.mini)

        case .error(let msg):
            Button {
                container.llm.loadModel()
            } label: {
                Label("Повторить", systemImage: "arrow.clockwise")
                    .font(.caption.weight(.medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help(msg)
        }
    }

    private func runAIAnalysis(description: String) {
        analysisState = .loading
        Task {
            do {
                let result = try await container.llm.analyzeApartment(description: description)
                analysisState = .ready(result)
            } catch {
                analysisState = .error(error.localizedDescription)
            }
        }
    }

    // MARK: - AI Skeleton

    private var aiSkeletonView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ForEach([72.0, 98.0, 64.0, 82.0], id: \.self) { width in
                    Capsule()
                        .fill(Color.secondary.opacity(0.2))
                        .frame(width: width, height: 28)
                }
            }
            Capsule()
                .fill(Color.purple.opacity(0.18))
                .frame(width: 148, height: 26)
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.2))
                    .frame(maxWidth: .infinity)
                    .frame(height: 14)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.2))
                    .frame(maxWidth: .infinity)
                    .frame(height: 14)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: 180, height: 14)
            }
        }
        .opacity(shimmerOn ? 0.4 : 1.0)
        .animation(.easeInOut(duration: 0.75).repeatForever(autoreverses: true), value: shimmerOn)
        .onAppear { shimmerOn = true }
        .onDisappear { shimmerOn = false }
    }

    // MARK: - AI Result

    private func aiResultView(_ analysis: ApartmentAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(analysis.tags, id: \.self) { tag in
                        Text(tag)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.blue.opacity(0.1))
                            .foregroundStyle(Color.blue)
                            .clipShape(Capsule())
                    }
                }
            }

            HStack(spacing: 8) {
                Image(systemName: "house.fill")
                    .foregroundStyle(.purple)
                    .font(.subheadline)
                Text("Состояние:")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(analysis.condition)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.purple.opacity(0.12))
                    .foregroundStyle(.purple)
                    .clipShape(Capsule())
            }

            VStack(alignment: .leading, spacing: 6) {
                Label("Рекомендации", systemImage: "lightbulb.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                Text(analysis.recommendations)
                    .font(.subheadline)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Status & Notes

    private var statusAndNotesView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Статус")
                    .font(.headline)
                Spacer()
                Menu {
                    ForEach(ApartmentStatus.allCases) { status in
                        Button {
                            apartment.status = status
                            // Clear waiting condition when leaving .waiting
                            if status != .waiting {
                                apartment.waitingConditionJSON = nil
                            }
                        } label: {
                            Label(status.label, systemImage: status.icon)
                        }
                    }
                } label: {
                    Label(apartment.status.label, systemImage: apartment.status.icon)
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(apartment.status.color.opacity(0.15))
                        .foregroundStyle(apartment.status.color)
                        .clipShape(Capsule())
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Заметки")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $apartment.notes)
                    .font(.body)
                    .frame(minHeight: 80)
                    .padding(8)
                    .background(Color(.textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )
            }
        }
        .padding()
        .background(Color(.windowBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }

    // MARK: - Waiting Condition

    @State private var showWaitingSheet = false

    @ViewBuilder
    private var waitingConditionView: some View {
        if apartment.status == .waiting {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Условие ожидания", systemImage: "clock.badge")
                        .font(.headline)
                    Spacer()
                    Button {
                        showWaitingSheet = true
                    } label: {
                        Image(systemName: apartment.waitingCondition == nil ? "plus.circle" : "pencil.circle")
                            .foregroundStyle(.orange)
                    }
                    .buttonStyle(.plain)
                }

                if let condition = apartment.waitingCondition {
                    HStack {
                        Image(systemName: "checkmark.seal")
                            .foregroundStyle(.orange)
                        Text(condition.summary)
                            .font(.subheadline)
                        Spacer()
                        Button {
                            apartment.waitingCondition = nil
                        } label: {
                            Image(systemName: "xmark.circle")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    if !condition.note.isEmpty {
                        Text(condition.note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Условие не задано — квартира будет оставаться в статусе \"Ожидание\" бесконечно")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(Color.orange.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
            .sheet(isPresented: $showWaitingSheet) {
                WaitingConditionSheet(condition: Binding(
                    get: { apartment.waitingCondition ?? WaitingCondition(type: .priceBelow) },
                    set: { apartment.waitingCondition = $0 }
                ))
            }
        }
    }

    // MARK: - FlipScore Section

    @ViewBuilder
    private var flipScoreView: some View {
        if let flipScore {
            FlipScoreCard(result: flipScore)
                .padding(.horizontal)
        }
    }

    // MARK: - Выделенная статистика (Просмотры)

    @ViewBuilder
    private var statsHighlightView: some View {
        if apartment.viewsTotal != nil || apartment.viewsToday != nil || (useYesterdayViews && apartment.yesterdayViews != nil) {
            HStack(spacing: 12) {
                if useYesterdayViews, let yesterday = apartment.yesterdayViews {
                    Label("\(yesterday) вчера", systemImage: "arrow.uturn.backward.circle.fill")
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.green.opacity(0.1))
                        .foregroundColor(.green)
                        .cornerRadius(20)
                }

                if let today = apartment.viewsToday {
                    Label("\(today) сегодня", systemImage: "eye.fill")
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.blue.opacity(0.1))
                        .foregroundColor(.blue)
                        .cornerRadius(20)
                }

                if let total = apartment.viewsTotal {
                    Label("\(total) всего", systemImage: "chart.bar.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - Сетка характеристик

    private var characteristicsGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("О квартире")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 15) {
                if let area = apartment.area {
                    InfoTile(title: "Общая площадь", value: String(format: "%.1f м²", area), icon: "square")
                }
                if let living = apartment.livingArea {
                    InfoTile(title: "Жилая площадь", value: String(format: "%.1f м²", living), icon: "square.fill")
                }
                if let kitchen = apartment.kitchenArea {
                    InfoTile(title: "Площадь кухни", value: String(format: "%.1f м²", kitchen), icon: "square.dashed")
                }
                if let floor = apartment.floor {
                    let total = apartment.totalFloors.map { "/\($0)" } ?? ""
                    InfoTile(title: "Этаж", value: "\(floor)\(total)", icon: "building.2")
                }
                if let rooms = apartment.roomsCount {
                    InfoTile(title: "Комнат", value: "\(rooms)", icon: "door.french.closed")
                }
                if let year = apartment.yearBuilt {
                    InfoTile(title: "Год постройки", value: "\(year)", icon: "calendar")
                }
                if let material = apartment.houseMaterial {
                    InfoTile(title: "Тип дома", value: material, icon: "building.2.fill")
                }
                if let ceiling = apartment.ceilingHeight {
                    InfoTile(title: "Потолки", value: String(format: "%.2f м", ceiling), icon: "arrow.up.and.down")
                }
            }
        }
        .padding()
        .background(Color(.systemGray).opacity(0.05))
        .cornerRadius(12)
        .padding(.horizontal)
    }

    // MARK: - Продавец

    /// Returns true when the seller is identifiable as a professional (agent or agency).
    /// Falls back to sellerName when sellerType is nil — catches cases like "Real Estate EXPERT".
    private var isSellerProfessional: Bool {
        let raw = apartment.sellerType ?? apartment.sellerName ?? ""
        let t = raw.lowercased()
        return t.contains("agent") || t.contains("agency")
            || t.contains("риелтор") || t.contains("агент")
            || t.contains("агентство")
            || t.contains("real estate") || t.contains("realty")
            || t.contains("недвижимость")  // ИНКОМ-Недвижимость, Этажи и т.п.
            || t.contains("developer") || t.contains("застройщик")
    }

    @ViewBuilder
    private var sellerView: some View {
        if let name = apartment.sellerName {
            VStack(alignment: .leading, spacing: 8) {
                Text("Продавец")
                    .font(.headline)

                HStack(spacing: 12) {
                    Image(systemName: "person.circle.fill")
                        .resizable()
                        .frame(width: 40, height: 40)
                        .foregroundColor(.secondary)

                    VStack(alignment: .leading) {
                        Text(name)
                            .fontWeight(.medium)
                        if let type = apartment.sellerType {
                            Text(type)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    Spacer()

                    if isSellerProfessional {
                        Label("+3 балла", systemImage: "person.badge.plus")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.green.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }
            }
            .padding()
            .background(Color(.systemGray).opacity(0.05))
            .cornerRadius(12)
            .padding(.horizontal)
        }
    }

    // Вспомогательный компонент для сетки
    struct InfoTile: View {
        let title: String
        let value: String
        let icon: String

        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: icon)
                        .font(.caption2)
                    Text(title)
                        .font(.caption2)
                }
                .foregroundColor(.secondary)

                Text(value)
                    .font(.subheadline)
                    .fontWeight(.bold)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Метро

    @ViewBuilder
    private var metroView: some View {
        if let metro = apartment.metro {
            HStack(spacing: 8) {
                Image(systemName: "tram.fill")
                    .foregroundColor(.red)
                Text(metro)
                    .fontWeight(.medium)
                if let distance = apartment.metroDistance {
                    HStack(spacing: 4) {
                        if let transportType = apartment.metroTransportType {
                            Image(systemName: transportType == "walk" ? "figure.walk" : "bus.fill")
                                .foregroundColor(.secondary)
                        }
                        Text("\(distance) мин")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .font(.subheadline)
            .padding(.horizontal)
        }
    }

    // MARK: - Описание

    @ViewBuilder
    private var descriptionView: some View {
        if let description = apartment.apartmentDescription {
            VStack(alignment: .leading, spacing: 12) {
                Text("Описание")
                    .font(.headline)

                Text(description)
                    .font(.body)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding()
            .background(Color(.systemGray).opacity(0.1))
            .cornerRadius(12)
            .padding(.horizontal)
        }
    }

    // MARK: - Галерея фотографий

    @ViewBuilder
    private var imagesGalleryView: some View {
        if !apartment.imageURLs.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(apartment.imageURLs, id: \.self) { urlString in
                        if let url = URL(string: urlString) {
                            AsyncImage(url: url) { image in
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 300, height: 200)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            } placeholder: {
                                ProgressView()
                                    .frame(width: 300, height: 200)
                                    .background(Color.secondary.opacity(0.1))
                                    .cornerRadius(12)
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    // MARK: - Заголовок

    private var headerView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(apartment.title)
                .font(.title2)
                .fontWeight(.bold)

            Text(apartment.address)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal)
    }

    // MARK: - Текущая цена

    private var currentPriceView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Текущая цена")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(apartment.price.formatted(.number))")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Text("₽")
                    .font(.title3)
                    .foregroundColor(.secondary)

                Spacer()

                priceChangeView
            }
        }
        .padding()
        .background(Color(.systemGray).opacity(0.1))
        .cornerRadius(12)
        .padding(.horizontal)
    }

    // MARK: - Финансовый калькулятор флиппинга
    
    @ViewBuilder
    private var financialCalculatorView: some View {
        if apartment.targetSellPrice != nil || apartment.repairCost != nil || apartment.netProfit != nil {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "dollarsign.arrow.circlepath")
                        .foregroundColor(.green)
                    Text("Финансовый калькулятор флиппинга")
                        .font(.headline)
                }
                
                VStack(spacing: 8) {
                    if let target = apartment.targetSellPrice {
                        InfoRow(title: "Целевая цена продажи", value: "\(target.formatted(.number)) ₽")
                    }
                    if let repair = apartment.repairCost {
                        InfoRow(title: "Стоимость ремонта", value: "\(repair.formatted(.number)) ₽")
                    }
                    if let taxes = apartment.taxes {
                        InfoRow(title: "Налоги и комиссии", value: "\(taxes.formatted(.number)) ₽")
                    }
                    
                    Divider()
                        .padding(.vertical, 4)
                    
                    if let profit = apartment.netProfit {
                        HStack {
                            Text("Чистая прибыль")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Spacer()
                            Text("\(profit.formatted(.number)) ₽")
                                .font(.headline)
                                .foregroundColor(profit > 0 ? .green : .red)
                        }
                    }
                    if let roi = apartment.roi {
                        HStack {
                            Text("ROI")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Spacer()
                            Text("\(roi, specifier: "%.1f")%")
                                .font(.headline)
                                .foregroundColor(roi > 15 ? .green : .orange)
                        }
                    }
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.green.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.green.opacity(0.2), lineWidth: 1)
            )
            .padding(.horizontal)
        }
    }

    // Изменение цены
    @ViewBuilder
    private var priceChangeView: some View {
        if apartment.priceHistory.count > 1, let firstPoint = apartment.priceHistory.first {
            let firstPrice = firstPoint.price
            let diff = apartment.price - firstPrice
            let percent = Double(diff) / Double(firstPrice) * 100

            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: diff < 0 ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                    Text("\(abs(diff).formatted(.number)) ₽")
                }
                .foregroundColor(diff < 0 ? .green : .red)
                .font(.headline)

                Text("\(abs(percent), specifier: "%.1f")%")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - История цен (упрощённая)

    @ViewBuilder
    private var priceHistoryView: some View {
        if apartment.priceHistory.count > 1 {
            VStack(alignment: .leading, spacing: 8) {
                Text("История цен")
                    .font(.headline)
                    .padding(.horizontal)

                ForEach(apartment.priceHistory.reversed()) { point in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(point.date.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                            Text("\(point.price.formatted(.number)) ₽")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 4)
                }
            }
            .padding()
            .background(Color(.systemGray).opacity(0.1))
            .cornerRadius(12)
            .padding(.horizontal)
        }
    }

    // MARK: - Метаданные

    private var metadataView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Информация")
                .font(.headline)

            VStack(spacing: 8) {
                InfoRow(title: "Впервые найдено", value: apartment.dateAdded.formatted(date: .long, time: .shortened))
                InfoRow(title: "Последнее обновление", value: apartment.lastUpdate.formatted(date: .long, time: .shortened))
                InfoRow(title: "ID объявления", value: apartment.id)
            }
        }
        .padding()
        .background(Color(.systemGray).opacity(0.1))
        .cornerRadius(12)
        .padding(.horizontal)
    }

    // MARK: - Кнопка открыть на сайте

    @ViewBuilder
    private var openLinkButton: some View {
        if let url = URL(string: apartment.url) {
            Link(destination: url) {
                HStack {
                    Image(systemName: "safari")
                    Text("Открыть на Циан")
                    Image(systemName: "arrow.up.forward")
                }
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(12)
                .padding(.horizontal)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Вспомогательные вью

struct CharacteristicRow: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 20)

            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()

            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
        }
    }
}

struct InfoRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
        }
    }
}

#Preview {
    let apt = Apartment(
        id: "123456",
        title: "3-комнатная квартира, 75 м²",
        price: 15_000_000,
        url: "https://cian.ru",
        address: "Москва, ЦАО, Тверская улица, 1"
    )
    apt.area = 75.5
    apt.floor = 5
    apt.totalFloors = 12
    apt.houseMaterial = "Монолит"
    apt.metro = "Тверская"
    apt.metroDistance = 7
    apt.metroTransportType = "walk"
    apt.viewsToday = 12
    apt.viewsTotal = 1543
    apt.apartmentDescription = "Продаётся светлая квартира с высокими потолками 3.1 м. Евроремонт 2021 года, новая сантехника, встроенная кухня. Тихий двор, парковка."

    return NavigationStack {
        ApartmentDetailView(
            apartment: apt,
            flipScore: FlipScoreResult(
                totalScore: 77,
                priceScore: 32,
                metroScore: 20,
                locationScore: 20,
                isDistrictScore: false,
                areaScore: 5,
                sellerBonus: 0,
                priceSqm: 198_675,
                benchmarkSqm: 265_000,
                benchmarkOkrug: "ЦАО",
                benchmarkSampleSize: 38,
                demandLevel: .market,
                viewsPerDay: 12
            )
        )
    }
    .environment(AppContainer())
}
