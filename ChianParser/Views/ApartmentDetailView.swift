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
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

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
                    waitingConditionView
                    flipScoreView
                    currentPriceView
                    priceHistoryView
                    characteristicsGrid
                    descriptionView
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
        if apartment.viewsTotal != nil || apartment.viewsToday != nil {
            HStack(spacing: 20) {
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
                    InfoTile(title: "Тип дома", value: material, icon: "bricks.fill")
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
    NavigationStack {
        ApartmentDetailView(
            apartment: {
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
                return apt
            }(),
            flipScore: FlipScoreResult(
                totalScore: 77,
                priceScore: 32,
                metroScore: 20,
                locationScore: 20,
                isDistrictScore: false,
                areaScore: 5,
                priceSqm: 198_675,
                benchmarkSqm: 265_000,
                benchmarkOkrug: "ЦАО",
                benchmarkSampleSize: 38,
                demandLevel: .market,
                viewsPerDay: 12
            )
        )
    }
}
